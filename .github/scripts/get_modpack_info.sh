#!/usr/bin/env bash
# .github/scripts/get_modpack_info.sh
# ─────────────────────────────────────────────────────────────────────────────
# Extracts modpack metadata from pakku.json and pakku-lock.json and exports it
# as GitHub Actions step outputs. Safe to run locally too — it just prints to
# stdout in that case.
#
# Source of truth:
#   • pakku.json       → modpack name + version (user-facing)
#   • pakku-lock.json  → Minecraft version + loader (authoritative build target)
#
# The Minecraft version and loader are read from pakku-lock.json because that
# is the only file pakku populates with the real export target. pakku.json has
# never carried an mc_version field, so any default here would be a guess that
# silently goes stale on a Minecraft version bump.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# Accept PACK_DIR from the environment (set in the workflow's env: block)
# so the directory name only needs to live in one place.
PACK_DIR="${PACK_DIR:-SkyBlock_Enhanced_Modern_Edition_26.1}"
PAKKU_JSON="$PACK_DIR/pakku.json"
PAKKU_LOCK="$PACK_DIR/pakku-lock.json"

if [[ ! -f "$PAKKU_JSON" ]]; then
    echo "::error::$PAKKU_JSON not found. Run from repo root." >&2
    exit 1
fi

if [[ ! -f "$PAKKU_LOCK" ]]; then
    echo "::error::$PAKKU_LOCK not found. Run from repo root." >&2
    exit 1
fi

# ── Read pakku.json fields (user-facing metadata) ────────────────────────────
MODPACK_VERSION=$(jq -r '.version // empty' "$PAKKU_JSON")
MODPACK_NAME=$(jq -r '.name // "SkyBlock_Enhanced_Modern_Edition"' "$PAKKU_JSON")

if [[ -z "$MODPACK_VERSION" ]]; then
    echo "::error::Could not read .version from $PAKKU_JSON" >&2
    exit 1
fi

# ── Read build target from pakku-lock.json (authoritative) ───────────────────
# mc_versions is an array (a pack can target multiple MC versions). We take the
# first entry. If you ever add a second target version, the headless client
# test will only exercise this one — revisit then.
MINECRAFT_VERSION=$(jq -r '.mc_versions[0] // empty' "$PAKKU_LOCK")

if [[ -z "$MINECRAFT_VERSION" ]]; then
    echo "::error::Could not read .mc_versions[0] from $PAKKU_LOCK" >&2
    exit 1
fi

# Loader is stated explicitly in the lock file under .loaders, e.g.
# {"fabric": "0.19.3"}. keys[0] grabs the first declared loader. For a
# multi-loader ("multiplatform") export this only reports the first — fine for
# a single-loader pack.
MODPACK_LOADER=$(jq -r '.loaders | keys[0] // "fabric"' "$PAKKU_LOCK")

# ── Git metadata ──────────────────────────────────────────────────────────────
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

# Previous tag (the one before HEAD; handles detached HEAD on tag push in CI)
PREVIOUS_TAG=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "none")

# Version in the previous tag's pakku.json (used for version-bump validation)
if [[ "$PREVIOUS_TAG" != "none" ]]; then
    PREVIOUS_MODPACK_VERSION=$(
        git show "${PREVIOUS_TAG}:${PAKKU_JSON}" 2>/dev/null \
            | jq -r '.version // empty' 2>/dev/null \
        || echo "none"
    )
else
    PREVIOUS_MODPACK_VERSION="none"
fi

# ── Read config version from pack.json ────────────────────────────────────────
CONFIG_PACK_JSON="$PACK_DIR/.pakku/overrides/packcore/configs/pack.json"

if [[ -f "$CONFIG_PACK_JSON" ]]; then
    CONFIG_VERSION=$(jq -r '.version // empty' "$CONFIG_PACK_JSON")
else
    CONFIG_VERSION="none"
fi

# Previous config version (from previous tag's pack.json)
if [[ "$PREVIOUS_TAG" != "none" ]]; then
    PREVIOUS_CONFIG_VERSION=$(
        git show "${PREVIOUS_TAG}:${CONFIG_PACK_JSON}" 2>/dev/null \
            | jq -r '.version // empty' 2>/dev/null \
        || echo "none"
    )
else
    PREVIOUS_CONFIG_VERSION="none"
fi

# Markdown anchor for changelog links  e.g. "1.4.3" → "update-143"
VERSION_ANCHOR="update-$(echo "$MODPACK_VERSION" | tr -d '.')"

# ── Release type (always 'release' per project preference) ───────────────────
RELEASE_TYPE="release"

# ── Emit outputs ─────────────────────────────────────────────────────────────
emit() { echo "$1=$2"; }

output_vars() {
    emit "modpack_version"          "$MODPACK_VERSION"
    emit "modpack_name"             "$MODPACK_NAME"
    emit "minecraft_version"        "$MINECRAFT_VERSION"
    emit "modpack_loader"           "$MODPACK_LOADER"
    emit "current_branch"           "$CURRENT_BRANCH"
    emit "previous_tag"             "$PREVIOUS_TAG"
    emit "previous_modpack_version" "$PREVIOUS_MODPACK_VERSION"
    emit "version_anchor"           "$VERSION_ANCHOR"
    emit "release_type"             "$RELEASE_TYPE"
    emit "config_version"           "$CONFIG_VERSION"
    emit "previous_config_version"  "$PREVIOUS_CONFIG_VERSION"
}

# Write to GITHUB_OUTPUT if running in Actions, else print to stdout
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    output_vars >> "$GITHUB_OUTPUT"
fi

# Always print for visibility in logs
output_vars
