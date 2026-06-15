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

`--targets` can also be one or more specific folders instead of `all`:

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

`pack.json` is **never touched** — it holds each resolution's identity
(`targetWidth`, `targetHeight`, `name`, `description`, `guiScale`), and its
`version` is already kept in sync by `copy_zips.sh`'s version-bump step.

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

## Reading the output

```
== Syncing 1080p_default_configs -> 1440p_default_configs ==
  ~ synced, kept 1440p_default_configs's GUI position(s): config/skyhanni/config.json
      gui.titlePosition.x: 190 -> 510
      gui.titlePosition.y: 161 -> 160
  ~ synced (no GUI positions to preserve): config/skyocean/config.jsonc
  ! skipped (not JSON-shaped; target left as-is): options.txt
     new=0 synced=2 patched=2 unchanged=29 skipped=0
```

- `new file` — target didn't have it, copied as-is.
- `synced (no GUI positions to preserve)` — whole file now matches source.
- `synced, kept ...'s GUI position(s)` — matches source except the listed
  fields, which kept the target's own values (shown as `target -> ...` is
  read as "target keeps its X instead of source's Y" — the right-hand side
  is what stays).
- `skipped` — left completely alone (not JSON-shaped).
- Files not mentioned were already identical/up to date.

## Suggested workflow

1. Tweak a setting (or several) in one resolution's configs as normal.
2. `python3 hudsync.py --source <that resolution> --targets all --dry-run`
   and skim the output — make sure nothing unexpected is being synced or
   preserved.
3. Re-run without `--dry-run`.
4. Run `copy_zips.sh` as usual to zip/deploy/version-bump everything.
