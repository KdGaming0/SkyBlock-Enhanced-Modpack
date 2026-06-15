#!/usr/bin/env python3
"""
hudsync.py - Keep SkyBlock Enhanced "Default Configs" in sync across resolutions,
while preserving the per-resolution HUD/GUI element positions you've set.

Layout this script expects (same as copy_zips.sh's $SOURCE folder):

    <base>/
        1080p_default_configs/
        1080p_default_configs_2x_/
        1440p_default_configs/
        1440p_default_configs_ultrawide_/
        4k_default_configs/
        4k_default_configs_ultrawide_/

Each of those folders is the full contents of one resolution's config zip
(pack.json, options.txt, config/, resourcepacks/, shaderpacks/, servers.dat).

------------------------------------------------------------------------
WHAT IT DOES
------------------------------------------------------------------------

You edit ONE resolution's files as normal (toggle a feature, change a
threshold, whatever). Then run:

    python3 hudsync.py --source 1080p_default_configs --targets all

For every file under the source folder (except pack.json - see below),
for every other target folder:

  - If the target doesn't have that file yet -> it's copied over as-is.

  - If the target already has the file AND it's JSON/JSONC/JSON5-shaped
    (comments and trailing commas are fine) -> the file becomes a copy of
    the source file, EXCEPT for "GUI position" fields, which keep the
    TARGET's existing values. Comments and formatting are preserved -
    only the specific position values that need to differ are edited in
    place.

  - If the target already has the file but it ISN'T JSON-shaped (e.g.
    options.txt, servers.dat, resource/shader packs) -> it's left
    completely untouched. These files routinely hold per-resolution data
    (options.txt has its own guiScale/window settings per resolution)
    that this tool has no safe way to selectively merge.

"GUI position" fields (kept per-target, never overwritten by sync):
  - x, y, scale, centerX, centerY, ignoreCustomScale
  - relative_x, relative_y  (Skyblocker HUD widgets)
  - anything ending in X / Y in camelCase (mapX, scoreX, ...)
  - anything ending in Scale / Scaling (globalScale, tabHudScale, ...)
  - plus whatever you pass via --exclude-keys (see DEFAULT_EXTRA_KEEP
    below for two ultrawide-related keys kept by default)

pack.json is SKIPPED entirely - it holds each resolution's identity
(targetWidth/targetHeight/name/description/guiScale), and its `version`
field is already kept in sync by copy_zips.sh's version-bump step.

Always run with --dry-run first to see what would change.

------------------------------------------------------------------------
USAGE
------------------------------------------------------------------------

    python3 hudsync.py --source 1080p_default_configs --targets all --dry-run
    python3 hudsync.py --source 1080p_default_configs --targets all

    # only push to specific resolutions:
    python3 hudsync.py --source 1080p_default_configs \
        --targets 1440p_default_configs 4k_default_configs

    # treat extra keys as resolution-specific (kept per-target):
    python3 hudsync.py --source 1080p_default_configs --targets all \
        --exclude-keys "someOtherToggle,anotherOne"
"""

import argparse
import json
import re
import sys
from pathlib import Path

from jsonc_parser import parse_jsonc, ParseError


# ----------------------------------------------------------------------
# "Is this a GUI position field?" heuristic
# ----------------------------------------------------------------------

_EXACT_POSITION_KEYS = {
    "x", "y",
    "relative_x", "relative_y",
    "scale",
    "centerX", "centerY",
    "ignoreCustomScale",
}

# camelCase fields ending in X / Y (mapX, mapY, scoreX, scoreY, ...) and any
# field ending in "Scale" / "Scaling" (globalScale, titleContainerScale,
# tabHudScale, mapScaling, guiScale, ...) are also resolution-dependent.
_POSITION_KEY_RE = re.compile(r"(?:[a-z](?:X|Y)|Scale|Scaling)$")


def is_position_key(key: str) -> bool:
    return key in _EXACT_POSITION_KEYS or bool(_POSITION_KEY_RE.search(key))


# Extra keys treated as resolution-specific (kept per-target) by default,
# on top of is_position_key(). These don't follow the x/y/Scale naming
# pattern but were found to legitimately differ between the normal and
# ultrawide variants of this pack. Override/extend with --exclude-keys.
DEFAULT_EXTRA_KEEP = {"widenConfig", "wide-moulconfig"}


ALL_RESOLUTIONS = [
    "1080p_default_configs",
    "1080p_default_configs_2x_",
    "1440p_default_configs",
    "1440p_default_configs_ultrawide_",
    "4k_default_configs",
    "4k_default_configs_ultrawide_",
]

# Files relative to a resolution folder's root that are NEVER touched.
SKIP_FILES = {"pack.json"}


# ----------------------------------------------------------------------
# merge / diff over parsed JSON trees
# ----------------------------------------------------------------------

def merge(source_val, target_val, extra_keep=frozenset()):
    """Return the value the TARGET should hold: identical to `source_val`,
    except that for any key matching is_position_key() (or in
    `extra_keep`), the TARGET's existing value is kept (if it has one)."""

    if isinstance(source_val, dict) and isinstance(target_val, dict):
        result = {}
        for k, sv in source_val.items():
            if is_position_key(k) or k in extra_keep:
                result[k] = target_val[k] if k in target_val else sv
            elif k in target_val:
                result[k] = merge(sv, target_val[k], extra_keep)
            else:
                result[k] = sv
        return result

    if isinstance(source_val, list) and isinstance(target_val, list):
        if (len(source_val) == len(target_val)
                and all(isinstance(x, dict) for x in source_val)
                and all(isinstance(x, dict) for x in target_val)):
            return [merge(s, t, extra_keep) for s, t in zip(source_val, target_val)]
        return source_val

    return source_val


def diff_paths(old, new, path=()):
    """Yield (path_tuple, old_value, new_value) for every leaf where `old`
    and `new` differ. Recurses into dicts (by key) and equal-length lists
    (by index) so the path matches the span keys from parse_jsonc()."""

    if isinstance(old, dict) and isinstance(new, dict):
        for k in sorted(set(old) | set(new), key=str):
            yield from diff_paths(old.get(k), new.get(k), path + (k,))
    elif isinstance(old, list) and isinstance(new, list) and len(old) == len(new):
        for i, (o, n) in enumerate(zip(old, new)):
            yield from diff_paths(o, n, path + (i,))
    elif old != new:
        yield (path, old, new)


def format_path(path):
    parts = []
    for p in path:
        parts.append(f"[{p}]" if isinstance(p, int) else str(p))
    out = parts[0] if parts else ""
    for p in parts[1:]:
        out += p if p.startswith("[") else f".{p}"
    return out or "(root)"


# ----------------------------------------------------------------------
# Per-file sync
# ----------------------------------------------------------------------

class FileResult:
    def __init__(self, status, detail=""):
        self.status = status   # "new" | "unchanged" | "synced" | "patched" | "skipped"
        self.detail = detail


def sync_file(src_path: Path, tgt_path: Path, extra_keep, dry_run: bool) -> FileResult:
    if not tgt_path.exists():
        if not dry_run:
            tgt_path.parent.mkdir(parents=True, exist_ok=True)
            tgt_path.write_bytes(src_path.read_bytes())
        return FileResult("new")

    src_bytes = src_path.read_bytes()
    tgt_bytes = tgt_path.read_bytes()

    try:
        src_text = src_bytes.decode("utf-8")
        tgt_text = tgt_bytes.decode("utf-8")
        src_tree, src_spans = parse_jsonc(src_text)
        tgt_tree, _ = parse_jsonc(tgt_text)
    except (UnicodeDecodeError, ParseError):
        if src_bytes == tgt_bytes:
            return FileResult("unchanged")
        return FileResult("skipped", "not JSON-shaped; target left as-is")

    merged = merge(src_tree, tgt_tree, extra_keep)
    diffs = list(diff_paths(src_tree, merged))

    # Only keep diffs we can actually patch: scalar (or null) leaves with
    # a recorded span in the source text.
    patches = []
    unpatchable = []
    for path, old_val, new_val in diffs:
        if path not in src_spans or isinstance(new_val, (dict, list)):
            unpatchable.append(path)
            continue
        start, end = src_spans[path]
        patches.append((start, end, json.dumps(new_val, ensure_ascii=False), path, old_val, new_val))

    if not patches and not unpatchable:
        if src_bytes == tgt_bytes:
            return FileResult("unchanged")
        if not dry_run:
            tgt_path.write_bytes(src_bytes)
        return FileResult("synced")

    out_text = src_text
    for start, end, repl, *_ in sorted(patches, key=lambda p: p[0], reverse=True):
        out_text = out_text[:start] + repl + out_text[end:]

    out_bytes = out_text.encode("utf-8")
    detail_lines = [
        f"{format_path(path)}: {old!r} -> {new!r}" for _, _, _, path, old, new in patches
    ]
    for path in unpatchable:
        detail_lines.append(f"{format_path(path)}: kept source value (couldn't preserve target's)")

    if out_bytes == tgt_bytes:
        return FileResult("unchanged")

    if not dry_run:
        tgt_path.write_bytes(out_bytes)
    return FileResult("patched", "\n".join(detail_lines))


# ----------------------------------------------------------------------
# Walking the source tree
# ----------------------------------------------------------------------

def iter_source_files(source_dir: Path):
    for p in sorted(source_dir.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(source_dir)
        if rel.as_posix() in SKIP_FILES:
            continue
        yield rel


# ----------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", default=".",
                         help="Folder containing the resolution subfolders "
                              "(defaults to current directory)")
    parser.add_argument("--source", required=True,
                         help="Resolution folder you edited")
    parser.add_argument("--targets", nargs="+", default=["all"],
                         help='One or more resolution folders, or "all" '
                              '(every other known resolution). Default: all')
    parser.add_argument("--dry-run", action="store_true",
                         help="Show what would change without writing any files")
    parser.add_argument("--exclude-keys", default=None,
                         help="Comma-separated extra key names to treat as "
                              "resolution-specific (kept per-target instead "
                              f"of synced), in addition to the defaults "
                              f"({', '.join(sorted(DEFAULT_EXTRA_KEEP))})")
    args = parser.parse_args()

    base = Path(args.base)
    source_dir = base / args.source
    if not source_dir.is_dir():
        sys.exit(f"Source folder not found: {source_dir}")

    extra_keep = set(DEFAULT_EXTRA_KEEP)
    if args.exclude_keys:
        extra_keep |= {k.strip() for k in args.exclude_keys.split(",") if k.strip()}

    if args.targets == ["all"]:
        targets = [r for r in ALL_RESOLUTIONS if r != args.source]
    else:
        targets = args.targets

    source_files = list(iter_source_files(source_dir))

    mode = "DRY RUN - " if args.dry_run else ""
    for target_name in targets:
        target_dir = base / target_name
        if not target_dir.is_dir():
            print(f"!! skipping missing target folder: {target_dir}")
            continue

        print(f"== {mode}Syncing {args.source} -> {target_name} ==")
        counts = {"new": 0, "unchanged": 0, "synced": 0, "patched": 0, "skipped": 0}
        for rel in source_files:
            src_file = source_dir / rel
            tgt_file = target_dir / rel
            result = sync_file(src_file, tgt_file, extra_keep, args.dry_run)
            counts[result.status] += 1

            if result.status == "new":
                print(f"  + new file: {rel}")
            elif result.status == "synced":
                print(f"  ~ synced (no GUI positions to preserve): {rel}")
            elif result.status == "patched":
                print(f"  ~ synced, kept {target_name}'s GUI position(s): {rel}")
                for line in result.detail.splitlines():
                    print(f"      {line}")
            elif result.status == "skipped":
                print(f"  ! skipped ({result.detail}): {rel}")
            # "unchanged" -> silent

        print(f"     new={counts['new']} synced={counts['synced']} "
              f"patched={counts['patched']} unchanged={counts['unchanged']} "
              f"skipped={counts['skipped']}")

    print("\n(dry run - no files written)" if args.dry_run else "\nDone.")


if __name__ == "__main__":
    main()
