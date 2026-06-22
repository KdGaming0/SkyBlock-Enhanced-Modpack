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

Empty folders that exist in the source (e.g. an empty resourcepacks/) are
also created in each target, so directory structure stays in sync.

------------------------------------------------------------------------
MIRRORING / DELETING (opt-in, --prune)
------------------------------------------------------------------------

By default nothing is ever deleted. Files that exist in a target but not
in the source are simply reported so you can see the drift.

With --prune, the tool makes each target mirror the source by deleting
orphaned files (present in target, absent in source). For safety, --prune
ONLY deletes JSON-shaped config files - the kind this tool manages, e.g.
a config left behind by a mod you removed. Non-JSON per-resolution files
(options.txt, servers.dat, resourcepacks/*, shaderpacks/*) and pack.json
are NEVER auto-deleted, because they legitimately differ per resolution;
they're reported instead.

If you really want a full byte-for-byte mirror that also removes orphaned
NON-JSON files, add --prune-non-json on top of --prune. This is dangerous
(it can wipe per-resolution resource/shader packs) - always --dry-run it.

Empty directories left behind after pruning are cleaned up automatically
(but only ones that don't exist in the source).

------------------------------------------------------------------------
"GUI position" fields (kept per-target, never overwritten by sync)
------------------------------------------------------------------------
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

    # mirror the source: also delete stale JSON configs from targets
    python3 hudsync.py --source 1080p_default_configs --targets all --prune --dry-run
    python3 hudsync.py --source 1080p_default_configs --targets all --prune

    # only push to specific resolutions:
    python3 hudsync.py --source 1080p_default_configs \
        --targets 1440p_default_configs 4k_default_configs

    # treat extra keys as resolution-specific (kept per-target):
    python3 hudsync.py --source 1080p_default_configs --targets all \
        --exclude-keys "someOtherToggle,anotherOne"
"""

import argparse
import json
import os
import re
import sys
import tempfile
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


# Canonical list, used as a fallback when target auto-discovery finds
# nothing. Normally "--targets all" discovers sibling *default_configs*
# folders dynamically, so adding a new resolution needs no code change.
ALL_RESOLUTIONS = [
    "1080p_default_configs",
    "1080p_default_configs_2x_",
    "1440p_default_configs",
    "1440p_default_configs_ultrawide_",
    "4k_default_configs",
    "4k_default_configs_ultrawide_",
]

# Folders that are never valid sync targets even if they sit next to the
# resolution folders.
NON_TARGET_DIRS = {"__pycache__", "archive", ".git", ".idea", ".vscode"}

# Files relative to a resolution folder's root that are NEVER touched
# (neither synced nor pruned).
SKIP_FILES = {"pack.json"}


# ----------------------------------------------------------------------
# Small IO / text helpers
# ----------------------------------------------------------------------

def _strip_bom(text: str) -> str:
    """Drop a leading UTF-8 BOM so the parser doesn't choke on it."""
    return text[1:] if text and text[0] == "\ufeff" else text


def _atomic_write_bytes(path: Path, data: bytes) -> None:
    """Write `data` to `path` atomically: write a temp file in the same
    directory, then os.replace() it into place. A crash mid-write can
    never leave a half-written config behind."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".hudsync-", suffix=".tmp")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _looks_like_json(path: Path) -> bool:
    """True if `path` parses as JSON/JSONC/JSON5. Used to decide whether an
    orphaned target file is the kind of config this tool manages."""
    try:
        text = _strip_bom(path.read_bytes().decode("utf-8"))
        parse_jsonc(text)
        return True
    except (OSError, UnicodeDecodeError, ParseError):
        return False


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
        # "new" | "unchanged" | "synced" | "patched" | "skipped"
        self.status = status
        self.detail = detail


def sync_file(src_path: Path, tgt_path: Path, extra_keep, dry_run: bool) -> FileResult:
    if not tgt_path.exists():
        if not dry_run:
            _atomic_write_bytes(tgt_path, src_path.read_bytes())
        return FileResult("new")

    src_bytes = src_path.read_bytes()
    tgt_bytes = tgt_path.read_bytes()

    try:
        src_text = _strip_bom(src_bytes.decode("utf-8"))
        tgt_text = _strip_bom(tgt_bytes.decode("utf-8"))
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
            _atomic_write_bytes(tgt_path, src_bytes)
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
        _atomic_write_bytes(tgt_path, out_bytes)
    return FileResult("patched", "\n".join(detail_lines))


# ----------------------------------------------------------------------
# Walking the source tree
# ----------------------------------------------------------------------

def iter_source_files(source_dir: Path):
    for p in sorted(source_dir.rglob("*")):
        if p.is_symlink() or not p.is_file():
            continue
        rel = p.relative_to(source_dir)
        if rel.as_posix() in SKIP_FILES:
            continue
        yield rel


def iter_empty_source_dirs(source_dir: Path):
    """Yield directories under the source that contain no files anywhere
    beneath them. Non-empty dirs don't need explicit creation - copying a
    file into them makes them exist - so we only need these."""
    for p in sorted(source_dir.rglob("*")):
        if p.is_symlink() or not p.is_dir():
            continue
        if not any(c.is_file() for c in p.rglob("*")):
            yield p.relative_to(source_dir)


def source_dir_set(source_dir: Path):
    return {
        p.relative_to(source_dir).as_posix()
        for p in source_dir.rglob("*")
        if p.is_dir() and not p.is_symlink()
    }


def find_orphans(source_dir: Path, target_dir: Path):
    """Files present in the target but absent from the source (excluding
    SKIP_FILES), i.e. candidates for pruning."""
    src_files = {
        p.relative_to(source_dir).as_posix()
        for p in source_dir.rglob("*")
        if p.is_file() and not p.is_symlink()
    }
    orphans = []
    for p in sorted(target_dir.rglob("*")):
        if p.is_symlink() or not p.is_file():
            continue
        rel = p.relative_to(target_dir)
        if rel.as_posix() in SKIP_FILES:
            continue
        if rel.as_posix() not in src_files:
            orphans.append(rel)
    return orphans


def discover_targets(base: Path, source: str):
    """All sibling resolution folders (name contains 'default_configs'),
    minus the source and any known non-target dir."""
    found = []
    for p in sorted(base.iterdir()):
        if not p.is_dir():
            continue
        if p.name == source or p.name in NON_TARGET_DIRS:
            continue
        if "default_configs" in p.name:
            found.append(p.name)
    return found


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
                              '(every other sibling *default_configs* folder). '
                              'Default: all')
    parser.add_argument("--dry-run", action="store_true",
                         help="Show what would change without writing or "
                              "deleting any files")
    parser.add_argument("--prune", action="store_true",
                         help="Mirror the source: delete files that exist in "
                              "a target but not in the source. Only JSON-shaped "
                              "configs are deleted; non-JSON per-resolution "
                              "files (options.txt, servers.dat, resource/shader "
                              "packs) and pack.json are kept and just reported.")
    parser.add_argument("--prune-non-json", action="store_true",
                         help="With --prune, ALSO delete orphaned non-JSON "
                              "files. DANGEROUS - can wipe per-resolution "
                              "resource/shader packs. Always --dry-run first.")
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

    if args.prune_non_json and not args.prune:
        print("!! --prune-non-json has no effect without --prune; ignoring it.")
        args.prune_non_json = False

    extra_keep = set(DEFAULT_EXTRA_KEEP)
    if args.exclude_keys:
        extra_keep |= {k.strip() for k in args.exclude_keys.split(",") if k.strip()}

    if args.targets == ["all"]:
        targets = discover_targets(base, args.source)
        if not targets:
            targets = [r for r in ALL_RESOLUTIONS
                       if r != args.source and (base / r).is_dir()]
        if not targets:
            sys.exit("No target folders found next to the source.")
    else:
        # Guard: never sync a folder to itself.
        targets = [t for t in args.targets if t != args.source]
        dropped = [t for t in args.targets if t == args.source]
        if dropped:
            print(f"!! ignoring source listed as its own target: {args.source}")

    source_files = list(iter_source_files(source_dir))
    empty_dirs = list(iter_empty_source_dirs(source_dir))
    src_dirs = source_dir_set(source_dir)

    mode = "DRY RUN - " if args.dry_run else ""
    grand_removed = 0

    for target_name in targets:
        target_dir = base / target_name
        if not target_dir.is_dir():
            print(f"!! skipping missing target folder: {target_dir}")
            continue

        print(f"== {mode}Syncing {args.source} -> {target_name} ==")
        counts = {"new": 0, "unchanged": 0, "synced": 0, "patched": 0,
                  "skipped": 0, "newdir": 0, "error": 0}

        # 1) sync files
        for rel in source_files:
            src_file = source_dir / rel
            tgt_file = target_dir / rel
            try:
                result = sync_file(src_file, tgt_file, extra_keep, args.dry_run)
            except Exception as exc:  # one bad file must not kill the run
                counts["error"] += 1
                print(f"  !! ERROR on {rel}: {exc} (target left as-is)")
                continue
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

        # 2) propagate empty source directories
        for rel in empty_dirs:
            d = target_dir / rel
            if not d.exists():
                if not args.dry_run:
                    d.mkdir(parents=True, exist_ok=True)
                counts["newdir"] += 1
                print(f"  + new dir: {rel}")

        # 3) orphans (target has it, source doesn't)
        orphans = find_orphans(source_dir, target_dir)
        removed = []
        pruned_parents = set()
        for rel in orphans:
            tgt_file = target_dir / rel
            is_json = _looks_like_json(tgt_file)
            delete_it = args.prune and (is_json or args.prune_non_json)
            if delete_it:
                if not args.dry_run:
                    try:
                        tgt_file.unlink()
                    except OSError as exc:
                        counts["error"] += 1
                        print(f"  !! couldn't delete {rel}: {exc}")
                        continue
                removed.append(rel)
                for parent in rel.parents:
                    if parent != Path("."):
                        pruned_parents.add(parent)
                print(f"  - removed (not in source): {rel}")
            elif args.prune and not is_json:
                print(f"  ? kept orphan (non-JSON; --prune-non-json to delete): {rel}")
            else:
                tag = "" if is_json else " (non-JSON)"
                print(f"  ? orphan in target, not source{tag} (--prune to delete): {rel}")

        # 4) clean up directories emptied by pruning (and not in source)
        if args.prune and not args.dry_run:
            for parent in sorted(pruned_parents, key=lambda p: len(p.parts), reverse=True):
                if parent.as_posix() in src_dirs:
                    continue
                d = target_dir / parent
                try:
                    if d.is_dir() and not any(d.iterdir()):
                        d.rmdir()
                        print(f"  - removed empty dir: {parent}")
                except OSError:
                    pass

        grand_removed += len(removed)
        print(f"     new={counts['new']} synced={counts['synced']} "
              f"patched={counts['patched']} unchanged={counts['unchanged']} "
              f"skipped={counts['skipped']} newdir={counts['newdir']} "
              f"removed={len(removed)} errors={counts['error']}")

    if args.dry_run:
        print("\n(dry run - no files written or deleted)")
    else:
        print("\nDone.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
    except BrokenPipeError:
        # Output was piped into something like `head`/`less` that closed
        # the pipe early; exit quietly instead of dumping a traceback.
        try:
            devnull = os.open(os.devnull, os.O_WRONLY)
            os.dup2(devnull, sys.stdout.fileno())
        except OSError:
            pass
        sys.exit(0)
