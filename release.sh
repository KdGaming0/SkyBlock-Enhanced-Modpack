#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════╗
# ║         SkyBlock Enhanced · Release Wizard              ║
# ║  Run from repo root: ./release.sh                       ║
# ╚══════════════════════════════════════════════════════════╝
set -euo pipefail

# ─── Colours ────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

print_header() {
    echo -e "\n${BOLD}${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║  $1${NC}"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════╝${NC}\n"
}
print_step()  { echo -e "${CYAN}  ▶ $1${NC}"; }
print_ok()    { echo -e "${GREEN}  ✔ $1${NC}"; }
print_warn()  { echo -e "${YELLOW}  ⚠ $1${NC}"; }
print_err()   { echo -e "${RED}  ✖ $1${NC}" >&2; }
print_sep()   { echo -e "${BOLD}  ──────────────────────────────────────${NC}"; }

# ─── Paths ──────────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_DIR="$REPO_ROOT/SkyBlock_Enhanced_Modern_Edition_1.21.11"
PAKKU_JSON="$PACK_DIR/pakku.json"
MODPACK_JSON="$PACK_DIR/.pakku/overrides/packcore/modpack.json"
LOCK_FILE="$PACK_DIR/pakku-lock.json"
ROOT_CHANGELOG="$REPO_ROOT/CHANGELOG.md"
PACKCORE_MD_DIR="$PACK_DIR/.pakku/overrides/packcore/markdown"

# ─── Globals (populated in steps) ───────────────────────────────────────────
NEW_VERSION=""
BUMP_TYPE=""
RELEASE_TYPE="release"      # "release" or "beta"
TMP_OLD_LOCK=""
CHANGELOG_BODY=""
ROLLBACK_NEEDED=false
OLD_PAKKU_JSON_CONTENT=""
OLD_MODPACK_JSON_CONTENT=""

if command -v pakku-mc &>/dev/null; then
    PAKKU_CMD="pakku-mc"
elif command -v pakku &>/dev/null; then
    PAKKU_CMD="pakku"
else
    echo "pakku not found"
    exit 1
fi

# Set VERBOSE=1 to see pakku diff debug output in step_changelog
# e.g.: VERBOSE=1 ./release.sh

# ─── Dependency check ───────────────────────────────────────────────────────
check_deps() {
    local missing=()
    for cmd in jq git; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    for f in "$PAKKU_JSON" "$LOCK_FILE"; do
        if [[ ! -f "$f" ]]; then
            print_err "Expected file not found: $f"
            exit 1
        fi
    done

    if [[ ! -f "$MODPACK_JSON" ]]; then
        echo ""
        print_err "CRITICAL: modpack.json not found at:"
        echo -e "      ${CYAN}$MODPACK_JSON${NC}"
        print_warn "Without this file, the in-game UI and versioning will be out of sync."
        echo ""
        read -rp "  Abort release to fix this? [Y/n]: " stop_choice
        stop_choice="${stop_choice:-Y}"
        if [[ "$stop_choice" =~ ^[Yy]$ ]]; then
            print_err "Release aborted. Please restore modpack.json and try again."
            exit 1
        fi
        print_warn "Proceeding without modpack.json (not recommended)."
    fi
}

# ─── Rollback ───────────────────────────────────────────────────────────────
save_json_state() {
    OLD_PAKKU_JSON_CONTENT=$(cat "$PAKKU_JSON")
    [[ -f "$MODPACK_JSON" ]] && OLD_MODPACK_JSON_CONTENT=$(cat "$MODPACK_JSON") || true
    ROLLBACK_NEEDED=true
}

rollback_json() {
    if [[ "$ROLLBACK_NEEDED" == true ]]; then
        print_warn "Rolling back JSON changes..."
        echo "$OLD_PAKKU_JSON_CONTENT" > "$PAKKU_JSON"
        [[ -n "$OLD_MODPACK_JSON_CONTENT" ]] && echo "$OLD_MODPACK_JSON_CONTENT" > "$MODPACK_JSON"
        print_ok "JSON files restored."
    fi
}

trap_handler() {
    local ec=$?
    if [[ $ec -ne 0 ]]; then
        echo ""
        print_err "Script failed with exit code $ec."
        rollback_json
        # Clean up temp files
        [[ -n "${TMP_OLD_LOCK:-}" && -f "$TMP_OLD_LOCK" ]] && rm -f "$TMP_OLD_LOCK"
    fi
}
trap 'trap_handler' EXIT

# ═══════════════════════════════════════════════════════════════════════════
#  STEP 1 · VERSION BUMP
# ═══════════════════════════════════════════════════════════════════════════
step_version() {
    print_header "Step 1 · Version Bump"

    local cur
    cur=$(jq -r '.version // empty' "$PAKKU_JSON")
    [[ -z "$cur" ]] && { print_err "Could not read .version from $PAKKU_JSON"; exit 1; }

    print_step "Current version: ${BOLD}${cur}${NC}"

    # Strip any beta suffix to get the stable base version for bump arithmetic
    # e.g.  3.1.2-beta.1  →  base=3.1.2  (so next patch suggests 3.1.3)
    local cur_base
    cur_base="${cur%%-beta.*}"

    # Parse semver of the stable base
    if ! [[ "$cur_base" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        print_warn "Version '$cur_base' is not strict semver (X.Y.Z). Custom bump only."
        local MAJOR=0 MINOR=0 PATCH=0
    else
        local MAJOR="${BASH_REMATCH[1]}"
        local MINOR="${BASH_REMATCH[2]}"
        local PATCH="${BASH_REMATCH[3]}"
    fi

    local V_PATCH="$MAJOR.$MINOR.$((PATCH + 1))"
    local V_MINOR="$MAJOR.$((MINOR + 1)).0"
    local V_MAJOR="$((MAJOR + 1)).0.0"

    echo ""
    echo -e "    ${BOLD}[1]${NC}  patch  →  ${GREEN}$V_PATCH${NC}"
    echo -e "    ${BOLD}[2]${NC}  minor  →  ${YELLOW}$V_MINOR${NC}"
    echo -e "    ${BOLD}[3]${NC}  major  →  ${RED}$V_MAJOR${NC}"
    echo -e "    ${BOLD}[4]${NC}  custom"
    echo ""

    local choice
    read -rp "  Bump type [1]: " choice
    choice="${choice:-1}"

    local base_version=""
    case "$choice" in
        1) base_version="$V_PATCH" ; BUMP_TYPE="patch" ;;
        2) base_version="$V_MINOR" ; BUMP_TYPE="minor" ;;
        3) base_version="$V_MAJOR" ; BUMP_TYPE="major" ;;
        4)
            read -rp "  Enter version (X.Y.Z or X.Y.Z-beta.N): " base_version
            # Accept either a stable or already-qualified beta version
            if [[ "$base_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$ ]]; then
                NEW_VERSION="$base_version"
                BUMP_TYPE="custom"
                RELEASE_TYPE="beta"
                # Skip the beta sub-menu — the user already typed the full version
                print_step "Bumping: ${BOLD}${cur}${NC} → ${BOLD}${YELLOW}${NEW_VERSION}${NC} (beta)"
                save_json_state
                _apply_version_files
                return
            elif ! [[ "$base_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                print_err "Invalid version: '$base_version' (expected X.Y.Z or X.Y.Z-beta.N)"
                exit 1
            fi
            BUMP_TYPE="custom"
            ;;
        *) print_err "Invalid choice: $choice"; exit 1 ;;
    esac

    # ── Beta sub-menu ────────────────────────────────────────────────────────
    echo ""
    echo -e "  Is ${BOLD}${GREEN}${base_version}${NC} a stable release or a beta?"
    echo ""
    echo -e "    ${BOLD}[1]${NC}  stable  →  ${GREEN}${base_version}${NC}"

    # Work out the next beta number.
    # If the current version is already a beta of the *same* base (e.g. 3.1.2-beta.1
    # and we're about to release 3.1.2-beta.2), suggest the next beta index.
    local next_beta_n=1
    if [[ "$cur" =~ ^${base_version}-beta\.([0-9]+)$ ]]; then
        next_beta_n=$(( BASH_REMATCH[1] + 1 ))
    fi
    local V_BETA="${base_version}-beta.${next_beta_n}"

    echo -e "    ${BOLD}[2]${NC}  beta    →  ${YELLOW}${V_BETA}${NC}"
    echo -e "    ${BOLD}[3]${NC}  custom beta number"
    echo ""

    local beta_choice
    read -rp "  Choice [1]: " beta_choice
    beta_choice="${beta_choice:-1}"

    case "$beta_choice" in
        1)
            NEW_VERSION="$base_version"
            RELEASE_TYPE="release"
            ;;
        2)
            NEW_VERSION="$V_BETA"
            RELEASE_TYPE="beta"
            ;;
        3)
            local beta_n
            read -rp "  Enter beta number (e.g. 3 for ${base_version}-beta.3): " beta_n
            if ! [[ "$beta_n" =~ ^[0-9]+$ ]] || [[ "$beta_n" -lt 1 ]]; then
                print_err "Beta number must be a positive integer"
                exit 1
            fi
            NEW_VERSION="${base_version}-beta.${beta_n}"
            RELEASE_TYPE="beta"
            ;;
        *) print_err "Invalid choice: $beta_choice"; exit 1 ;;
    esac

    if [[ "$RELEASE_TYPE" == "beta" ]]; then
        print_step "Bumping: ${BOLD}${cur}${NC} → ${BOLD}${YELLOW}${NEW_VERSION}${NC} (beta pre-release)"
    else
        print_step "Bumping: ${BOLD}${cur}${NC} → ${BOLD}${GREEN}${NEW_VERSION}${NC}"
    fi

    save_json_state
    _apply_version_files
}

# ── Internal: write NEW_VERSION into pakku.json + modpack.json ───────────────
_apply_version_files() {

    local update_failed=false

    # --- Update pakku.json ---
    local tmp_p
    tmp_p=$(mktemp)
    if jq --arg v "$NEW_VERSION" '.version = $v' "$PAKKU_JSON" > "$tmp_p" && mv "$tmp_p" "$PAKKU_JSON"; then
        print_ok "pakku.json updated"
    else
        print_err "Failed to update pakku.json!"
        update_failed=true
    fi

    # --- Update modpack.json ---
    if [[ -f "$MODPACK_JSON" ]]; then
        local tmp_m
        tmp_m=$(mktemp)
        if jq --arg v "$NEW_VERSION" '.modpackVersion = $v' "$MODPACK_JSON" > "$tmp_m" && mv "$tmp_m" "$MODPACK_JSON"; then
            print_ok "modpack.json updated (modpackVersion)"
        else
            print_err "Failed to update modpack.json!"
            update_failed=true
        fi
    else
        print_warn "modpack.json missing — version not synced."
        update_failed=true
    fi

    # --- Strict Check ---
    if [[ "$update_failed" == true ]]; then
        echo ""
        print_warn "One or more version files failed to update correctly."
        read -rp "  Continue anyway? [y/N]: " cont
        cont="${cont:-N}"
        if [[ ! "$cont" =~ ^[Yy]$ ]]; then
            rollback_json
            print_err "Aborted by user to fix version files."
            exit 1
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
#  STEP 2 · PAKKU UPDATE
# ═══════════════════════════════════════════════════════════════════════════
step_pakku() {
    print_header "Step 2 · Pakku Update"

    # Snapshot lock file BEFORE updating so we can diff later
    TMP_OLD_LOCK=$(mktemp /tmp/pakku-old-lock.XXXXXX.json)
    cp "$LOCK_FILE" "$TMP_OLD_LOCK"
    print_ok "Saved lock snapshot → $TMP_OLD_LOCK"

    cd "$PACK_DIR"

    print_step "pakku update --all"
    if ! $PAKKU_CMD update --all; then
        cd "$REPO_ROOT"
        print_err "pakku update --all failed"
        exit 1
    fi

    print_step "pakku fetch"
    if ! $PAKKU_CMD fetch; then
        cd "$REPO_ROOT"
        print_err "pakku fetch failed"
        exit 1
    fi

    print_step "pakku export"
    if ! $PAKKU_CMD export; then
        cd "$REPO_ROOT"
        print_err "pakku export failed"
        exit 1
    fi

    cd "$REPO_ROOT"
    print_ok "Pakku pipeline complete"
}

# ═══════════════════════════════════════════════════════════════════════════
#  STEP 3 · CHANGELOG
# ═══════════════════════════════════════════════════════════════════════════

# Build a dynamic summary line based on what changed
_dynamic_summary() {
    local -i n_mod_upd=$1 n_mod_add=$2 n_mod_rem=$3
    local -i n_rp_upd=$4  n_rp_add=$5  n_rp_rem=$6
    local -i n_sh_upd=$7  n_sh_add=$8  n_sh_rem=$9
    local -i total=$(( n_mod_upd + n_mod_add + n_mod_rem + n_rp_upd + n_rp_add + n_rp_rem + n_sh_upd + n_sh_add + n_sh_rem ))
    local -i n_added=$(( n_mod_add + n_rp_add + n_sh_add ))
    local -i n_removed=$(( n_mod_rem + n_rp_rem + n_sh_rem ))
    local -i n_rp=$(( n_rp_upd + n_rp_add + n_rp_rem ))
    local -i n_shader=$(( n_sh_upd + n_sh_add + n_sh_rem ))

    if   (( total == 0 ));                     then echo "Internal version bump with no mod changes."
    elif (( n_added > 0 && n_removed > 0 ));   then echo "A notable update featuring mod additions, removals, and various updates."
    elif (( n_added > 3 ));                    then echo "A new update featuring several new mods and improvements across the board."
    elif (( n_added > 0 ));                    then echo "An update bringing in some new mods along with the usual maintenance updates."
    elif (( n_removed > 0 ));                  then echo "A cleanup update removing outdated mods and keeping everything current."
    elif (( total > 15 ));                     then echo "A large maintenance update with widespread mod and resource pack refreshes."
    elif (( n_rp > 0 && n_shader > 0 ));       then echo "A visual polish update covering mods, resource packs, and shaders."
    elif (( n_rp > 0 ));                       then echo "A visual polish update with mod and resource pack improvements."
    elif (( n_shader > 0 ));                   then echo "A stability update with mod and shader refreshes."
    elif (( total > 5 ));                      then echo "A mid-cycle maintenance update with several mod updates."
    else                                            echo "A small patch with a few mod updates and stability improvements."
    fi
}

# Heuristic: classify a name/filename as rp / shader / mod.
# Two-tier approach:
#   1. Explicit slug allowlist — catches known packs whose names contain no
#      generic keywords (e.g. "furfsky-reborn", "defrosted_pack", "looshy").
#   2. Keyword fallback — catches anything that looks like a shader/RP by name.
_classify_entry() {
    local name="$1"
    local lower
    lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')

    # ── Explicit resource-pack slugs (from pakku ls) ──────────────────────────
    # Add new RP slugs here if the modpack gains more packs whose names wouldn't
    # be caught by the keyword regex below.
    local rp_slugs=(
        furfsky-reborn furfsky_reborn
        packshq packs-hq
        dark-mode-skyblock dark_mode_skyblock
        skyblock-dark-ui skyblock_dark_ui
        sophies-enchants sophie sophies
        defrosted defrosted_pack defrosted-pack
        looshy
    )
    for slug in "${rp_slugs[@]}"; do
        if [[ "$lower" == *"$slug"* ]]; then
            echo "rp"
            return
        fi
    done

    # ── Explicit shader slugs ─────────────────────────────────────────────────
    local shader_slugs=(
        complementary-unbound complementary_unbound
        makeup-ultra-fast makeup_ultra_fast
        bsl seus rethink sildur
    )
    for slug in "${shader_slugs[@]}"; do
        if [[ "$lower" == *"$slug"* ]]; then
            echo "shader"
            return
        fi
    done

    # ── Keyword fallback ──────────────────────────────────────────────────────
    if echo "$lower" | grep -qE 'shader|complementary|rethink|sildur|makeup|ultra.?fast'; then
        echo "shader"
    elif echo "$lower" | grep -qE 'resource.?pack|texture|continuity|fabriulous|connected|stay.?true|clarity|faithful|sphax|compliance|enchant.?book|enchantment.?book'; then
        echo "rp"
    else
        echo "mod"
    fi
}

# Strip version suffix from a filename, then convert the slug to a human-readable
# display name: hyphens/underscores → spaces, each word title-cased.
# e.g. "iris-fabric-1.10.7+mc1.21.11.jar"  → "Iris Fabric"
#      "furfsky-reborn-v3.4.mrpack"         → "Furfsky Reborn"
#      "defrosted_pack"                      → "Defrosted Pack"
#      "looshy-v3.4.mrpack"                 → "Looshy"
_clean_name() {
    local raw="$1"
    raw="${raw%.jar}"
    raw="${raw%.mrpack}"
    raw="${raw%.zip}"
    # Strip trailing version-like segments: -1.2.3, +mc1.21, _1.21, -v3.4, etc.
    raw=$(echo "$raw" | sed -E 's/[-_+]v?[0-9].*$//')
    # Replace hyphens and underscores with spaces, then title-case each word
    echo "$raw" | tr '-' ' ' | tr '_' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2); print}'
}

# Returns 0 (true) if string looks like a bare MC version number, e.g. "1.21.11"
_is_version_string() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]
}

# Parse pakku diff output and write formatted changelog body to stdout.
#
# Pakku diff format (plain / --verbose):
#   + Name          → added
#   - Name          → removed
#   ! old -> new    → updated  (filenames, not display names)
_build_changelog() {
    local diff_text="$1"
    local version="$2"

    # Sections
    local mod_added="" mod_removed="" mod_updated=""
    local rp_added="" rp_removed="" rp_updated=""
    local sh_added="" sh_removed="" sh_updated=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local type entry name v_old v_new

        case "$line" in
            "! "*)
                # UPDATED
                local clean="${line#! }"
                local old_raw="${clean%% -> *}"
                local new_raw="${clean##* -> }"

                # Trim
                old_raw="${old_raw#"${old_raw%%[![:space:]]*}"}"
                old_raw="${old_raw%"${old_raw##*[![:space:]]}"}"
                new_raw="${new_raw#"${new_raw%%[![:space:]]*}"}"
                new_raw="${new_raw%"${new_raw##*[![:space:]]}"}"

                name=$(_clean_name "$old_raw")

                v_old=$(echo "$old_raw" | grep -oE '[0-9]+(\.[0-9]+)+[^ ]*' | head -n1 || true)
                v_new=$(echo "$new_raw" | grep -oE '[0-9]+(\.[0-9]+)+[^ ]*' | head -n1 || true)

                # Remove file extensions from versions
                v_old="${v_old%.jar}"
                v_old="${v_old%.zip}"
                v_old="${v_old%.mrpack}"
                v_old="${v_old%%+mc*}"

                v_new="${v_new%.jar}"
                v_new="${v_new%.zip}"
                v_new="${v_new%.mrpack}"
                v_new="${v_new%%+mc*}"

                [[ -z "$v_old" ]] && v_old="old"
                [[ -z "$v_new" ]] && v_new="new"

                entry="- **$name**: $v_old -> **$v_new**"
                type=$(_classify_entry "$old_raw")

                case "$type" in
                    shader) sh_updated+="$entry"$'\n' ;;
                    rp)     rp_updated+="$entry"$'\n' ;;
                    *)      mod_updated+="$entry"$'\n' ;;
                esac
                ;;

            "+ "*)
                # ADDED
                local raw="${line#+ }"
                raw="${raw#"${raw%%[![:space:]]*}"}"
                raw="${raw%"${raw##*[![:space:]]}"}"

                name=$(_clean_name "$raw")
                entry="- **$name**"
                type=$(_classify_entry "$raw")

                case "$type" in
                    shader) sh_added+="$entry"$'\n' ;;
                    rp)     rp_added+="$entry"$'\n' ;;
                    *)      mod_added+="$entry"$'\n' ;;
                esac
                ;;

            "- "*)
                # REMOVED
                local raw="${line#- }"
                raw="${raw#"${raw%%[![:space:]]*}"}"
                raw="${raw%"${raw##*[![:space:]]}"}"

                name=$(_clean_name "$raw")
                entry="- **$name**"
                type=$(_classify_entry "$raw")

                case "$type" in
                    shader) sh_removed+="$entry"$'\n' ;;
                    rp)     rp_removed+="$entry"$'\n' ;;
                    *)      mod_removed+="$entry"$'\n' ;;
                esac
                ;;
        esac

    done <<< "$diff_text"

    # Helper to build grouped sections
    build_section() {
        local title="$1"
        local mods="$2"
        local rps="$3"
        local shaders="$4"

        local out=""

        [[ -n "$mods" ]] && out+="### Mods\n$mods\n"
        [[ -n "$rps" ]] && out+="### Resource Packs\n$rps\n"
        [[ -n "$shaders" ]] && out+="### Shaders\n$shaders\n"

        [[ -n "$out" ]] && echo -e "## $title\n$out"
    }

    local sections=""

    local s_added s_removed s_updated

    s_added=$(build_section "➕ Added" "$mod_added" "$rp_added" "$sh_added")
    s_removed=$(build_section "➖ Removed" "$mod_removed" "$rp_removed" "$sh_removed")
    s_updated=$(build_section "🔄 Updated" "$mod_updated" "$rp_updated" "$sh_updated")

    [[ -n "$s_added" ]] && sections+="$s_added\n"
    [[ -n "$s_removed" ]] && sections+="$s_removed\n"
    [[ -n "$s_updated" ]] && sections+="$s_updated\n"

    [[ -z "$sections" ]] && sections="Internal version bump with no mod changes.\n"

    cat <<EOF
# 🛠 Update $version

$(echo -e "$sections")

---

### 🛠 Troubleshooting & Tips
- The first launch after updating may take slightly longer than usual.
- If Minecraft appears frozen while loading, wait a moment before closing it.
- If Modrinth does not show the update, refresh the instance page.

### 💡 Need Help?
Join us on **[Fluxer](https://fluxer.gg/3jJy9cp6)** (recommended) or **[Discord](https://discord.gg/pdwxyjTta7)** for support.

Thanks for using SkyBlock Enhanced!
EOF
}

step_changelog() {
    print_header "Step 3 · Changelog"

    cd "$PACK_DIR"

    # ── Create a temp workspace to satisfy naming requirements ──────────────
    local DIFF_DIR
    DIFF_DIR=$(mktemp -d /tmp/pakku-diff-XXXXXX)
    cp "$TMP_OLD_LOCK" "$DIFF_DIR/pakku-lock.json"

    print_step "Running pakku diff (with filename alignment)..."
    local raw_diff=""
    local diff_ok=false

    # Run diff using the specifically named temporary file
    if [[ "${VERBOSE:-}" == "1" ]]; then
        echo -e "  ${CYAN}[DEBUG]${NC} Comparing:"
        echo -e "          Old: $DIFF_DIR/pakku-lock.json"
        echo -e "          New: $(pwd)/pakku-lock.json"
    fi

    raw_diff=$($PAKKU_CMD diff "$DIFF_DIR/pakku-lock.json" "pakku-lock.json" -v 2>&1) || {
        print_warn "pakku diff command returned an error."
    }

    if [[ "${VERBOSE:-}" == "1" ]]; then
        echo -e "  ${CYAN}[DEBUG] Raw diff output:${NC}"
        echo "----------------------------------------"
        echo "$raw_diff"
        echo "----------------------------------------"
    fi

    if [[ -n "$raw_diff" && "$raw_diff" != *"no changes"* ]]; then
        diff_ok=true
        print_ok "Diff captured."
    fi

    # Cleanup the temp directory
    rm -rf "$DIFF_DIR"

    cd "$REPO_ROOT"

    # ── Build auto-changelog ─────────────────────────────────────────────────
    if [[ "$diff_ok" == false ]]; then
        print_warn "pakku diff produced no output — using empty template."
        CHANGELOG_BODY=$(_build_changelog "" "$NEW_VERSION")
    else
        CHANGELOG_BODY=$(_build_changelog "$raw_diff" "$NEW_VERSION")
    fi

    # ── Preview ─────────────────────────────────────────────────────────────
    echo ""
    print_sep
    echo -e "${BOLD}  Changelog Preview:${NC}"
    print_sep
    echo "$CHANGELOG_BODY" | sed 's/^/  /'
    print_sep
    echo ""

    echo -e "  ${BOLD}[1]${NC}  Use as-is"
    echo -e "  ${BOLD}[2]${NC}  Add custom notes to the top"
    echo -e "  ${BOLD}[3]${NC}  Replace entirely — opens \$EDITOR with this as a template"
    echo ""
    local cl_choice
    read -rp "  Choice [1]: " cl_choice
    cl_choice="${cl_choice:-1}"

    case "$cl_choice" in
        1)
            : # keep as-is
            ;;
        2)
            echo ""
            echo -e "  Enter notes (blank line to finish):"
            local notes=""
            local line
            while IFS= read -rp "  > " line; do
                [[ -z "$line" ]] && break
                notes+="${line}"$'\n'
            done
            if [[ -n "$notes" ]]; then
                # Insert notes after the version header + summary (after blank line on line 4)
                local header
                header=$(echo "$CHANGELOG_BODY" | head -n4)
                local rest
                rest=$(echo "$CHANGELOG_BODY" | tail -n +5)
                CHANGELOG_BODY="${header}"$'\n\n'"${notes}"$'\n'"${rest}"
            fi
            ;;
        3)
            local tmp_cl
            tmp_cl=$(mktemp /tmp/changelog-XXXXXX.md)
            echo "$CHANGELOG_BODY" > "$tmp_cl"
            echo -e "  Opening ${BOLD}${EDITOR:-nano}${NC}..."
            sleep 0.5
            "${EDITOR:-nano}" "$tmp_cl"
            CHANGELOG_BODY=$(cat "$tmp_cl")
            rm -f "$tmp_cl"
            ;;
        *)
            print_err "Invalid choice"
            exit 1
            ;;
    esac

    # ── Final approval ───────────────────────────────────────────────────────
    echo ""
    print_sep
    echo -e "${BOLD}  Final Changelog:${NC}"
    print_sep
    echo "$CHANGELOG_BODY" | sed 's/^/  /'
    print_sep
    echo ""

    local approval
    read -rp "  Approve and continue? [Y/n]: " approval
    approval="${approval:-Y}"
    if [[ ! "$approval" =~ ^[Yy]$ ]]; then
        print_err "Aborted by user."
        exit 1
    fi

    # ── Write files ──────────────────────────────────────────────────────────

    # Prepend to main CHANGELOG.md
    if [[ -f "$ROOT_CHANGELOG" ]]; then
        local existing
        existing=$(cat "$ROOT_CHANGELOG")
        printf '%s\n\n---\n\n%s\n' "$CHANGELOG_BODY" "$existing" > "$ROOT_CHANGELOG"
    else
        echo "$CHANGELOG_BODY" > "$ROOT_CHANGELOG"
    fi
    print_ok "Updated CHANGELOG.md"

    # Optionally write to packcore markdown dir
    if [[ -d "$PACKCORE_MD_DIR" ]]; then
        echo "$CHANGELOG_BODY" > "$PACKCORE_MD_DIR/CHANGELOG-v${NEW_VERSION}.md"
        print_ok "Wrote changelog to packcore/markdown/"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
#  STEP 4 · GIT COMMIT, TAG & PUSH
# ═══════════════════════════════════════════════════════════════════════════
step_git() {
    print_header "Step 4 · Commit, Tag & Push"

    local tag="v${NEW_VERSION}"

    # Sanity: check for existing tag
    if git rev-parse "$tag" &>/dev/null; then
        print_err "Tag $tag already exists locally — delete it first: git tag -d $tag"
        exit 1
    fi

    print_step "Staging all changes..."
    git add -A

    print_step "Committing..."
    local commit_msg
    if [[ "$RELEASE_TYPE" == "beta" ]]; then
        commit_msg="release: ${tag} (beta pre-release)"
    else
        commit_msg="release: ${tag}"
    fi
    git commit -m "$commit_msg"

    print_step "Creating tag ${tag}..."
    git tag "$tag"

    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    print_step "Pushing branch ${current_branch} to origin..."
    if ! git push origin "$current_branch"; then
        print_err "git push ${current_branch} failed — removing local tag"
        git tag -d "$tag"
        exit 1
    fi

    print_step "Pushing tag ${tag} to origin..."
    if ! git push origin "$tag"; then
        print_err "git push tag failed — removing local tag"
        git tag -d "$tag"
        exit 1
    fi

    # If we reach here the git push is done — disable JSON rollback
    ROLLBACK_NEEDED=false
    rm -f "$TMP_OLD_LOCK"

    print_ok "Pushed ${tag}"

    # Derive GitHub URL
    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    local actions_url=""
    if [[ "$remote_url" =~ github\.com[:/](.+?)(.git)?$ ]]; then
        local slug="${BASH_REMATCH[1]}"
        slug="${slug%.git}"
        actions_url="https://github.com/${slug}/actions"
    fi

    echo ""
    echo -e "${BOLD}${GREEN}  ✔ Release triggered!${NC}"
    [[ -n "$actions_url" ]] && echo -e "  Monitor CI: ${CYAN}${actions_url}${NC}"
}

# ═══════════════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════════════
main() {
    clear
    echo -e "${BOLD}${GREEN}"
    echo "  ╔══════════════════════════════════════════════╗"
    echo "  ║     SkyBlock Enhanced · Release Wizard       ║"
    echo "  ╚══════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_deps
    step_version
    step_pakku
    step_changelog
    step_git

    if [[ "$RELEASE_TYPE" == "beta" ]]; then
        print_header "🧪 Beta Release Complete"
    else
        print_header "🎉 Release Complete"
    fi
    echo -e "  Version   : ${BOLD}${NEW_VERSION}${NC}"
    echo -e "  Type      : ${BOLD}${RELEASE_TYPE}${NC}"
    echo -e "  Tag       : ${BOLD}v${NEW_VERSION}${NC}"
    echo -e "  Changelog : ${BOLD}CHANGELOG.md${NC} + packcore/markdown/"
    echo ""
}

main "$@"
