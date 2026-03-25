#!/usr/bin/env bash
# .github/scripts/get_modpack_info.sh
# ─────────────────────────────────────────────────────────────────────────────
# Extracts modpack metadata from pakku.json and exports it as GitHub Actions
# step outputs. Safe to run locally too — it just prints to stdout in that case.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# Accept PACK_DIR from the environment (set in the workflow's env: block)
# so the directory name only needs to live in one place.
PACK_DIR="${PACK_DIR:-SkyBlock_Enhanced_Modern_Edition_1.21.11}"
PAKKU_JSON="$PACK_DIR/pakku.json"

if [[ ! -f "$PAKKU_JSON" ]]; then
    echo "::error::$PAKKU_JSON not found. Run from repo root." >&2
    exit 1
fi

# ── Read pakku.json fields ────────────────────────────────────────────────────
MODPACK_VERSION=$(jq -r '.version // empty' "$PAKKU_JSON")
MODPACK_NAME=$(jq -r '.name // "SkyBlock_Enhanced_Modern_Edition"' "$PAKKU_JSON")

# mc_version field — pakku uses different key names across versions; try all
MINECRAFT_VERSION=$(jq -r '
    .mc_version //
    .minecraft  //
    .["minecraft-version"] //
    "1.21.11"
' "$PAKKU_JSON")

# Loader — pakku may store as string "fabric" or object {"type":"fabric",...}
MODPACK_LOADER=$(jq -r '
    if .loader | type == "string" then .loader
    elif .loader | type == "object" then (.loader.type // "fabric")
    else "fabric"
    end
' "$PAKKU_JSON")

if [[ -z "$MODPACK_VERSION" ]]; then
    echo "::error::Could not read .version from $PAKKU_JSON" >&2
    exit 1
fi

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
}

# Write to GITHUB_OUTPUT if running in Actions, else print to stdout
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    output_vars >> "$GITHUB_OUTPUT"
fi

# Always print for visibility in logs
output_vars
