# hudsync.py — keep your 6 resolution configs in sync

A small command-line tool for your `SkyBlock_Enhanced_Modpack/Default Configs`
folder. You edit one resolution's files like normal; this tool pushes every
*setting* change to the other five resolutions while leaving each one's
HUD/GUI positions, scales, and other per-resolution values exactly as they
are.

There's no longer a separate command for moving individual overlays — edit
GUI positions in-game/in the files as you normally would, then run this to
propagate everything else.

## Setup

Two files, dropped together anywhere:

- `hudsync.py`
- `jsonc_parser.py` (small helper module, must be in the same folder)

Run it from (or point `--base` at) your `Default Configs` folder — the same
folder `copy_zips.sh` calls `$SOURCE`, containing:

```
1080p_default_configs/
1080p_default_configs_2x_/
1440p_default_configs/
1440p_default_configs_ultrawide_/
4k_default_configs/
4k_default_configs_ultrawide_/
```

Requires Python 3, no extra packages.

## Usage

Edit one resolution's files as normal — toggle a feature, change a value,
whatever. Then:

```bash
# preview first - shows every change without writing anything
python3 hudsync.py --source 1080p_default_configs --targets all --dry-run

# do it for real
python3 hudsync.py --source 1080p_default_configs --targets all
```

`--targets all` picks every sibling folder whose name contains
`default_configs` (excluding the source and noise folders like
`__pycache__`/`archive`), so adding a new resolution folder later needs no
code change. You can also pass one or more specific folders instead:

```bash
python3 hudsync.py --source 1080p_default_configs \
    --targets 1440p_default_configs 4k_default_configs
```

## What it actually does, per file

For every file under the source folder (recursively — `config/`,
`options.txt`, `resourcepacks/`, etc.), for each target resolution:

- **Target doesn't have this file** → copied over as-is (1:1).
- **Target has the file, and it's JSON/JSONC/JSON5** (comments and trailing
  commas are fine — covers every mod config including the `.jsonc`/`.json5`
  ones like feesh, sbo, skyblockpv, skyocean, roughlyenoughitems) → the file
  becomes a copy of source, **except** GUI position fields keep the
  **target's** existing values. Comments and formatting are left alone —
  only the specific position numbers that need to stay different are edited
  in place.
- **Target has the file, but it isn't JSON-shaped** (`options.txt`,
  `servers.dat`, resource/shader packs) → left completely untouched. These
  hold real per-resolution data (e.g. `options.txt` has its own `guiScale`
  per resolution) that can't be safely auto-merged.

Empty folders that exist in the source (e.g. an empty `resourcepacks/`) are
also created in each target, so the directory structure stays in sync.

`pack.json` is **never touched** — it holds each resolution's identity
(`targetWidth`, `targetHeight`, `name`, `description`, `guiScale`), and its
`version` is already kept in sync by `copy_zips.sh`'s version-bump step.

## Mirroring / deleting stale files (`--prune`)

By default the tool only **adds and updates** — it never deletes anything.
Files that exist in a target but not in the source are just *reported* so
you can see what's drifted:

```
? orphan in target, not source (--prune to delete): config/oldmod/conf.json
```

Add `--prune` to make each target mirror the source by deleting those
orphans (e.g. a config left behind by a mod you removed):

```bash
python3 hudsync.py --source 1080p_default_configs --targets all --prune --dry-run
python3 hudsync.py --source 1080p_default_configs --targets all --prune
```

For safety, `--prune` **only deletes JSON-shaped config files** — the kind
this tool manages. Non-JSON per-resolution files (`options.txt`,
`servers.dat`, `resourcepacks/*`, `shaderpacks/*`) and `pack.json` are
**never** auto-deleted, because they legitimately differ per resolution;
they're reported and kept. Directories left empty by pruning are cleaned up
automatically (only ones that don't exist in the source).

If you truly want a full byte-for-byte mirror that **also** removes orphaned
non-JSON files, add `--prune-non-json` on top of `--prune`. This is
dangerous — it can wipe per-resolution resource/shader packs — so always
`--dry-run` it first.

## "GUI position" fields (always kept per-target)

- `x`, `y`, `scale`, `centerX`, `centerY`, `ignoreCustomScale`
- `relative_x`, `relative_y` (Skyblocker HUD widgets)
- anything ending in `X` / `Y` in camelCase (`mapX`, `scoreX`, `mapY`, ...)
- anything ending in `Scale` / `Scaling` (`globalScale`, `tabHudScale`,
  `mapScaling`, ...)

Two extra keys are kept per-target **by default**, because they were found
to legitimately differ between the normal and ultrawide variants of this
pack: `widenConfig` and `wide-moulconfig`.

If you spot something else in the dry-run output that's getting synced but
should actually stay different per resolution, add it with `--exclude-keys`
(comma-separated, on top of the defaults above):

```bash
python3 hudsync.py --source 1080p_default_configs --targets all \
    --exclude-keys "someOtherToggle,anotherOne"
```

## Robustness

- **Writes are atomic** — each file is written to a temp file and renamed
  into place, so a crash mid-run can't leave a half-written config.
- **One bad file won't kill the run** — if a single file can't be read or
  parsed, it's reported as an error and the rest of the sync continues:
  ```
  !! ERROR on config/x.json: <reason> (target left as-is)
  ```
- Files with a UTF-8 BOM still parse correctly (they used to be silently
  skipped).
- Symlinks are skipped rather than followed.
- `--dry-run` writes and deletes **nothing** — it only reports.

## Reading the output

```
== Syncing 1080p_default_configs -> 1440p_default_configs ==
  ~ synced, kept 1440p_default_configs's GUI position(s): config/skyhanni/config.json
      gui.titlePosition.x: 190 -> 510
      gui.titlePosition.y: 161 -> 160
  ~ synced (no GUI positions to preserve): config/skyocean/config.jsonc
  + new file: config/odin/odin.json
  + new dir: resourcepacks
  ! skipped (not JSON-shaped; target left as-is): options.txt
  ? orphan in target, not source (--prune to delete): config/oldmod/conf.json
     new=1 synced=2 patched=1 unchanged=29 skipped=1 newdir=1 removed=0 errors=0
```

- `new file` — target didn't have it, copied as-is.
- `new dir` — an empty source folder created in the target.
- `synced (no GUI positions to preserve)` — whole file now matches source.
- `synced, kept ...'s GUI position(s)` — matches source except the listed
  fields, which kept the target's own values (the right-hand side of
  `190 -> 510` is the value that **stays**).
- `skipped` — left completely alone (not JSON-shaped).
- `orphan ...` — in the target but not the source; deleted only with
  `--prune` (see above).
- `removed` — deleted by `--prune`.
- Files not mentioned were already identical/up to date.

The summary line counts: `new` (copied), `synced`/`patched` (updated),
`unchanged`, `skipped` (non-JSON, left alone), `newdir` (empty dirs made),
`removed` (pruned), `errors` (files that failed and were left as-is).

## Suggested workflow

1. Tweak a setting (or several) in one resolution's configs as normal.
2. `python3 hudsync.py --source <that resolution> --targets all --dry-run`
   and skim the output — make sure nothing unexpected is being synced,
   preserved, or (with `--prune`) deleted.
3. Re-run without `--dry-run`. Add `--prune` if you want stale configs
   removed from the other resolutions too.
4. Run `copy_zips.sh` as usual to zip/deploy/version-bump everything.
