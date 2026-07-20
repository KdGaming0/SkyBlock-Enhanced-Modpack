#!/usr/bin/env bash
source .env.release
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
# ┌─ PLACEHOLDER #1 ────────────────────────────────────────────────────────┐
# │ PACK_DIR_NAME must be the EXACT folder name in your repo root, and must  │
# │ match PACK_DIR in the Jenkinsfile and release.yml (both use             │
# │ "SkyBlock_Enhanced"). Do NOT leave these out of sync.                    │
# └─────────────────────────────────────────────────────────────────────────┘
PACK_DIR_NAME="SkyBlock_Enhanced"

# ┌─ PLACEHOLDER #2 · Jenkins remote trigger (Option 3) ─────────────────────┐
# │ After pushing the branch, the script POSTs to Jenkins to start a build   │
# │ immediately (no Poll SCM delay). Fill these in, or leave JENKINS_URL     │
# │ empty to disable the auto-trigger entirely (falls back to whatever       │
# │ trigger you configured in the Jenkins UI).                               │
# │                                                                          │
# │ Secrets: DO NOT hardcode tokens here if this file is committed. Prefer   │
# │ exporting them in your shell / a local untracked env file:               │
# │     export JENKINS_API_TOKEN=...      (User → Configure → API Token)      │
# │     export JENKINS_BUILD_TOKEN=...    (job's "Trigger builds remotely")   │
# │ The script reads those env vars if the vars below are left blank.         │
# └──────────────────────────────────────────────────────────────────────────┘
JENKINS_URL="https://jenkins.home.lab"        # base URL, no trailing slash
JENKINS_JOB="modpack-publish"                  # the job name
JENKINS_USER="KD1"           # your Jenkins login
JENKINS_API_TOKEN="${JENKINS_API_TOKEN:-}"     # from env by default
JENKINS_BUILD_TOKEN="${JENKINS_BUILD_TOKEN:-}" # from env by default

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_DIR="$REPO_ROOT/$PACK_DIR_NAME"
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
PREV_TAG="none"              # previous release tag (resolved in step_pakku)
CHANGELOG_BODY=""
ROLLBACK_NEEDED=false
OLD_PAKKU_JSON_CONTENT=""
OLD_MODPACK_JSON_CONTENT=""
DRY_RUN=false               # --dry-run skips git commit/tag/push
RELEASE_TAG=""              # actual git tag; usually v$NEW_VERSION
HOTFIX_N=0                  # >0 when doing a same-version hotfix re-release

if command -v pakku-mc &>/dev/null; then
    PAKKU_CMD="pakku-mc"
elif command -v pakku &>/dev/null; then
    PAKKU_CMD="pakku"
elif command -v Pakku &>/dev/null; then
    PAKKU_CMD="Pakku"
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

    # ── Retry eligibility ────────────────────────────────────────────────────
    # If v<cur> was never actually tagged on the remote (previous attempt died
    # somewhere between "push branch" and "Jenkins tags it"), offer to retry
    # the SAME version instead of forcing a bump. This is silent/best-effort:
    # network hiccups just mean the retry option doesn't show, not a hard fail.
    local remote_tag_exists=false
    if git ls-remote --exit-code --tags origin "refs/tags/v${cur}" &>/dev/null; then
        remote_tag_exists=true
    fi

    # ── Hotfix eligibility ───────────────────────────────────────────────────
    # Re-release the SAME pack version under a NEW tag. Used when a release run
    # was cancelled/aborted mid-flight (e.g. a mod updated seconds after you
    # kicked it off), or when v<cur> exists but nothing actually shipped.
    # Find the highest existing v<cur>-hotfix-N so we can offer N+1.
    local next_hotfix=1
    local existing_hotfix
    existing_hotfix=$(git ls-remote --tags origin "refs/tags/v${cur}-hotfix-*" 2>/dev/null \
        | sed -E 's#.*refs/tags/v'"${cur//./\\.}"'-hotfix-([0-9]+).*#\1#' \
        | grep -E '^[0-9]+$' | sort -n | tail -n1 || true)
    [[ -n "$existing_hotfix" ]] && next_hotfix=$(( existing_hotfix + 1 ))
    local V_HOTFIX_TAG="v${cur}-hotfix-${next_hotfix}"

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

    # If we're already on a beta, offer a [0] next-beta shortcut.
    # e.g. currently 3.1.2-beta.1 → offer 3.1.2-beta.2 as option [0].
    local IS_CURRENT_BETA=false
    local V_NEXT_BETA=""
    if [[ "$cur" =~ ^([0-9]+\.[0-9]+\.[0-9]+)-beta\.([0-9]+)$ ]]; then
        IS_CURRENT_BETA=true
        local cur_beta_base="${BASH_REMATCH[1]}"
        local cur_beta_n="${BASH_REMATCH[2]}"
        V_NEXT_BETA="${cur_beta_base}-beta.$(( cur_beta_n + 1 ))"
    fi

    echo ""
    if [[ "$IS_CURRENT_BETA" == true ]]; then
        echo -e "    ${BOLD}[0]${NC}  next beta →  ${YELLOW}${V_NEXT_BETA}${NC}  (iterate current beta)"
        echo -e "    ${BOLD}[6]${NC}  promote →  ${GREEN}${cur_base}${NC}  (release current beta as stable)"
    fi
    echo -e "    ${BOLD}[1]${NC}  patch   →  ${GREEN}$V_PATCH${NC}"
    echo -e "    ${BOLD}[2]${NC}  minor   →  ${YELLOW}$V_MINOR${NC}"
    echo -e "    ${BOLD}[3]${NC}  major   →  ${RED}$V_MAJOR${NC}"
    echo -e "    ${BOLD}[4]${NC}  custom"
    if [[ "$remote_tag_exists" == false ]]; then
        echo -e "    ${BOLD}[R]${NC}  retry   →  ${CYAN}${cur}${NC}  (release same version again — v${cur} was never tagged)"
    fi
    echo -e "    ${BOLD}[H]${NC}  hotfix  →  ${CYAN}${cur}${NC}  (same version, new tag ${BOLD}${V_HOTFIX_TAG}${NC})"
    echo ""

    local choice
    read -rp "  Bump type [1]: " choice
    choice="${choice:-1}"

    # ── Retry path: same version, no bump. pakku update/fetch/export still
    # runs in step_pakku (so any mod changes since the last attempt are
    # picked up), and step_changelog will reuse the existing changelog for
    # this version instead of regenerating it from a diff.
    if [[ "${choice,,}" == "r" ]]; then
        if [[ "$remote_tag_exists" == true ]]; then
            print_err "Tag v${cur} already exists remotely — nothing to retry. Bump the version instead."
            exit 1
        fi
        NEW_VERSION="$cur"
        BUMP_TYPE="retry"
        RELEASE_TYPE=$([[ "$cur" == *-beta.* ]] && echo "beta" || echo "release")
        print_step "Retrying release: ${BOLD}${CYAN}${NEW_VERSION}${NC} (no version bump — previous attempt never published)"
        save_json_state
        return
    fi

    # ── Hotfix path: same pack version, NEW tag. ─────────────────────────────
    # pakku update/fetch/export still runs, so any mod updates released since
    # the aborted run get picked up. The changelog reuses the previously
    # approved entry for this version and merges in this run's new entries.
    if [[ "${choice,,}" == "h" ]]; then
        NEW_VERSION="$cur"
        BUMP_TYPE="hotfix"
        HOTFIX_N="$next_hotfix"
        RELEASE_TAG="$V_HOTFIX_TAG"
        RELEASE_TYPE=$([[ "$cur" == *-beta.* ]] && echo "beta" || echo "release")
        print_step "Hotfix re-release: ${BOLD}${CYAN}${NEW_VERSION}${NC} → tag ${BOLD}${RELEASE_TAG}${NC}"
        save_json_state
        return
    fi

    # ── Next-beta shortcut: iterate the current beta without a version bump.
    if [[ "$choice" == "0" ]]; then
        if [[ "$IS_CURRENT_BETA" != true ]]; then
            print_err "Option [0] is only available when the current version is a beta."
            exit 1
        fi
        NEW_VERSION="$V_NEXT_BETA"
        BUMP_TYPE="beta-iterate"
        RELEASE_TYPE="beta"
        print_step "Bumping: ${BOLD}${cur}${NC} → ${BOLD}${YELLOW}${NEW_VERSION}${NC} (beta pre-release)"
        save_json_state
        _apply_version_files
        return
    fi

    # ── Promote path: release the current beta's base version as stable.
    # e.g. 5.0.0-beta.1 → 5.0.0 (previously the menu could only offer 5.0.1).
    if [[ "$choice" == "6" ]]; then
        if [[ "$IS_CURRENT_BETA" != true ]]; then
            print_err "Option [6] is only available when the current version is a beta."
            exit 1
        fi
        NEW_VERSION="$cur_base"
        BUMP_TYPE="promote"
        RELEASE_TYPE="release"
        print_step "Promoting: ${BOLD}${cur}${NC} → ${BOLD}${GREEN}${NEW_VERSION}${NC} (stable release)"
        save_json_state
        _apply_version_files
        return
    fi

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

    # Every path through step_version that isn't a hotfix leaves RELEASE_TAG
    # empty, meaning "tag = v<version>" as before.
    [[ -z "$RELEASE_TAG" ]] && RELEASE_TAG="v${NEW_VERSION}"

    # ── Changelog baseline ───────────────────────────────────────────────────
    # Diff against the pakku-lock.json from the PREVIOUS RELEASE TAG, not a
    # snapshot taken right now. Mods added/updated manually between releases
    # are therefore included in the changelog — a pre-update snapshot would
    # only ever capture what `pakku update --all` changes during this run.
    TMP_OLD_LOCK=$(mktemp /tmp/pakku-old-lock.XXXXXX.json)
    local lock_rel="${LOCK_FILE#"$REPO_ROOT"/}"

    PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "none")

    # ── Hotfix baseline ──────────────────────────────────────────────────────
    # Diff against whatever this same version last shipped as, so the changelog
    # only shows what actually changed since the aborted/previous attempt.
    if [[ "$BUMP_TYPE" == "hotfix" ]]; then
        local hf_base=""
        if [[ "$HOTFIX_N" -gt 1 ]]; then
            hf_base="v${NEW_VERSION}-hotfix-$(( HOTFIX_N - 1 ))"
        elif git ls-remote --exit-code --tags origin "refs/tags/v${NEW_VERSION}" &>/dev/null; then
            hf_base="v${NEW_VERSION}"
        fi
        if [[ -n "$hf_base" ]]; then
            PREV_TAG="$hf_base"
            print_ok "Hotfix baseline: ${hf_base}"
        fi
    fi

    local baseline_tag="$PREV_TAG"
    if [[ "$PREV_TAG" == *-beta.* ]]; then
        # The previous release was a beta. When promoting to stable, players on
        # the stable channel usually want the changelog since the LAST STABLE,
        # not just the changes since the final beta — so offer both.
        local prev_stable
        prev_stable=$(git tag --list 'v*' --sort=-v:refname \
            | grep -vE 'beta|hotfix' | head -n1 || true)
        if [[ -n "$prev_stable" ]]; then
            echo ""
            echo -e "  Previous tag ${BOLD}${PREV_TAG}${NC} is a beta. Diff the changelog against:"
            echo -e "    ${BOLD}[1]${NC}  ${YELLOW}${PREV_TAG}${NC}  (changes since that beta)"
            echo -e "    ${BOLD}[2]${NC}  ${GREEN}${prev_stable}${NC}  (all changes since the last stable)"
            local bl_choice
            read -rp "  Changelog baseline [1]: " bl_choice
            [[ "${bl_choice:-1}" == "2" ]] && baseline_tag="$prev_stable"
        fi
    fi

    if [[ "$baseline_tag" != "none" ]] \
        && git show "${baseline_tag}:${lock_rel}" > "$TMP_OLD_LOCK" 2>/dev/null \
        && [[ -s "$TMP_OLD_LOCK" ]]; then
        print_ok "Changelog baseline: pakku-lock.json @ ${baseline_tag}"
    else
        cp "$LOCK_FILE" "$TMP_OLD_LOCK"
        print_warn "No usable previous tag — baseline is the current lock file"
        print_warn "(changelog will only show what this run's pakku update changes)."
    fi

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
    elif (( n_shader > 0 ));                    then echo "A stability update with mod and shader refreshes."
    elif (( total > 5 ));                      then echo "A mid-cycle maintenance update with several mod updates."
    else                                            echo "A small patch with a few mod updates and stability improvements."
    fi
}

# ─── Project-type lookup (authoritative, from pakku-lock.json) ───────────────
# pakku-lock.json already knows the type of every project (MOD /
# RESOURCE_PACK / SHADER — the same column `pakku ls` prints), so we read it
# instead of maintaining slug lists by hand. Both the baseline and the current
# lock file are loaded, so removed projects still classify correctly.
declare -A TYPE_LOOKUP=()

_norm_key() {
    echo "$1" | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

_load_type_lookup() {
    TYPE_LOOKUP=()
    local lock key type
    for lock in "$@"; do
        [[ -f "$lock" ]] || continue
        while IFS=$'\t' read -r key type; do
            [[ -z "$key" || -z "$type" ]] && continue
            TYPE_LOOKUP[$(_norm_key "$key")]="$type"
        done < <(jq -r '
            .projects[]?
            | ((.type // "mod") | ascii_downcase
               | if test("resource") then "rp"
                 elif test("shader") then "shader"
                 else "mod" end) as $t
            | ((.name // empty), (.files[]?.fileName // empty))
            | select(. != null and . != "")
            | "\(.)\t\($t)"
        ' "$lock" 2>/dev/null)
    done
    if [[ "${VERBOSE:-}" == "1" ]]; then
        echo -e "  ${CYAN}[DEBUG]${NC} Type lookup loaded: ${#TYPE_LOOKUP[@]} keys"
    fi
}

# Classify a diff entry (project name for +/- lines, file name for ! lines)
# as rp / shader / mod.
#   1. Exact match against pakku-lock.json project names and file names.
#   2. Slug/keyword fallback for anything the lock files don't cover.
_classify_entry() {
    local name="$1"
    local lower
    lower=$(_norm_key "$name")

    # ── 1. Authoritative: pakku-lock.json ────────────────────────────────────
    if [[ -n "${TYPE_LOOKUP[$lower]:-}" ]]; then
        echo "${TYPE_LOOKUP[$lower]}"
        return
    fi

    # ── 2. Fallback slugs (only used when the lock lookup misses) ────────────
    local rp_slugs=(
        furfsky-reborn furfsky_reborn fursky
        faithful
        hypixel-plus hypixel_plus "hypixel plus"
        hypixel-skyblock-legacy "hypixel skyblock legacy" skyblock-legacy
        dark-mode-skyblock dark_mode_skyblock "skyblock dark mode" "dark mode"
        skyblock-dark-ui skyblock_dark_ui "skyblock dark ui" "dark ui"
        sophies-enchants sophies sophie
        packshq packs-hq
        defrosted defrosted_pack defrosted-pack
        looshy
    )
    for slug in "${rp_slugs[@]}"; do
        if [[ "$lower" == *"$slug"* ]]; then
            echo "rp"
            return
        fi
    done

    local shader_slugs=(
        complementary-unbound complementary_unbound complementary
        makeup-ultra-fast makeup_ultra_fast makeupultrafast makeup
        bsl seus rethink sildur
    )
    for slug in "${shader_slugs[@]}"; do
        if [[ "$lower" == *"$slug"* ]]; then
            echo "shader"
            return
        fi
    done

    # ── 3. Keyword fallback ──────────────────────────────────────────────────
    if echo "$lower" | grep -qE 'shader|ultra.?fast'; then
        echo "shader"
    elif echo "$lower" | grep -qE 'resource.?pack|texture|continuity|fabriulous|connected|stay.?true|clarity|sphax|compliance|enchant.?book|enchantment.?book'; then
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

    # ── Summary line ─────────────────────────────────────────────────────────
    # Count "- " entries per category and feed _dynamic_summary. (The custom
    # notes flow in step_changelog inserts after line 4, i.e. right after this
    # summary — it was written with this line in mind.)
    count_entries() { [[ -z "$1" ]] && echo 0 || printf '%s' "$1" | grep -c '^- '; }
    local -i c_mod_upd c_mod_add c_mod_rem c_rp_upd c_rp_add c_rp_rem c_sh_upd c_sh_add c_sh_rem
    c_mod_upd=$(count_entries "$mod_updated"); c_mod_add=$(count_entries "$mod_added"); c_mod_rem=$(count_entries "$mod_removed")
    c_rp_upd=$(count_entries "$rp_updated");   c_rp_add=$(count_entries "$rp_added");   c_rp_rem=$(count_entries "$rp_removed")
    c_sh_upd=$(count_entries "$sh_updated");   c_sh_add=$(count_entries "$sh_added");   c_sh_rem=$(count_entries "$sh_removed")

    local -i total=$(( c_mod_upd + c_mod_add + c_mod_rem + c_rp_upd + c_rp_add + c_rp_rem + c_sh_upd + c_sh_add + c_sh_rem ))
    local summary=""
    if (( total > 0 )); then
        # sections already carries the "internal version bump" text when empty
        summary=$(_dynamic_summary "$c_mod_upd" "$c_mod_add" "$c_mod_rem" \
                                   "$c_rp_upd" "$c_rp_add" "$c_rp_rem" \
                                   "$c_sh_upd" "$c_sh_add" "$c_sh_rem")
    fi

    cat <<EOF
# 🛠 Update $version

${summary:+$summary

}$(echo -e "$sections")

---

### 🛠 Troubleshooting & Tips
- The first launch after updating may take slightly longer than usual.
- If Modrinth does not show the update, refresh the instance page or just wait abit.

### 💡 Need Help?
Join us on **[Discord](https://discord.gg/pdwxyjTta7)** or **[Fluxer](https://fluxer.gg/3jJy9cp6)** for support.

Thanks for using SkyBlock Enhanced!
EOF
}

# Merge a freshly generated changelog into a previously approved one (hotfix).
#   $1 = prior changelog body (approved during the aborted run)
#   $2 = newly generated changelog body (this run's pakku diff)
#
# Rules, applied per entry line ("- **Name**: old -> **new**"):
#   • Same project already listed  → replace that line (newer version wins).
#     For an "updated" entry the old->new range is widened so it reads as the
#     full jump from what last shipped to what ships now.
#   • Project not listed yet       → append under the matching "### " subsection
#     of the matching "## " section, creating either if absent.
# Everything outside the entry sections (title, summary, footer) is taken from
# the prior changelog, so hand-written notes survive.
_merge_changelog() {
    local prior="$1"
    local fresh="$2"

    # Entry lines from the fresh body, tagged with the section/subsection they
    # live under: "<## section>\t<### subsection>\t<line>"
    local tagged
    tagged=$(awk -F'\n' '
        /^## /  { section=$0; subsection=""; next }
        /^### / { subsection=$0; next }
        /^---$/ { section=""; subsection=""; next }
        /^- /   { if (section != "") printf "%s\t%s\t%s\n", section, subsection, $0 }
    ' <<< "$fresh")

    [[ -z "$tagged" ]] && { printf '%s' "$prior"; return; }

    local merged="$prior"
    local sec subsec line pname old_line

    while IFS=$'\t' read -r sec subsec line; do
        [[ -z "$line" ]] && continue
        pname=$(sed -E 's/^- \*\*([^*]+)\*\*.*/\1/' <<< "$line")
        [[ -z "$pname" ]] && continue

        old_line=$(grep -m1 -F -- "- **${pname}**" <<< "$merged" || true)

        if [[ -n "$old_line" ]]; then
            # Already listed → replace in place. For an update entry, keep the
            # ORIGINAL "from" version and take the NEW "to" version, so
            # 1.0 -> 1.1 merged with 1.1 -> 1.2 reads as 1.0 -> 1.2.
            local repl="$line"
            if [[ "$old_line" == *" -> "* && "$line" == *" -> "* ]]; then
                local from_v to_v
                from_v=$(sed -E 's/^- \*\*[^*]+\*\*: (.+) -> \*\*.*/\1/' <<< "$old_line")
                to_v=$(sed -E 's/^.* -> \*\*(.+)\*\*[[:space:]]*$/\1/' <<< "$line")
                if [[ -n "$from_v" && -n "$to_v" && "$from_v" != "$to_v" ]]; then
                    repl="- **${pname}**: ${from_v} -> **${to_v}**"
                fi
            fi
            merged=$(REPL="$repl" NEEDLE="- **${pname}**" awk '
                index($0, ENVIRON["NEEDLE"]) == 1 { print ENVIRON["REPL"]; next }
                { print }
            ' <<< "$merged")
            continue
        fi

        # Not listed yet → insert under the matching headings, creating them if
        # they are missing. New sections go just before the "---" footer.
        merged=$(SEC="$sec" SUBSEC="$subsec" LINE="$line" awk '
            { buf[NR] = $0 }
            END {
                sec = ENVIRON["SEC"]; subsec = ENVIRON["SUBSEC"]; line = ENVIRON["LINE"]
                sec_start = 0; sec_end = 0; sub_start = 0; sub_end = 0; footer = 0

                for (i = 1; i <= NR; i++) {
                    if (footer == 0 && buf[i] == "---") footer = i
                    if (sec_start == 0 && buf[i] == sec) { sec_start = i; continue }
                    if (sec_start && sec_end == 0 && i > sec_start &&
                        (substr(buf[i],1,3) == "## " || buf[i] == "---")) sec_end = i
                }
                if (sec_start && sec_end == 0) sec_end = (footer ? footer : NR + 1)

                if (sec_start && subsec != "") {
                    for (i = sec_start + 1; i < sec_end; i++) {
                        if (sub_start == 0 && buf[i] == subsec) { sub_start = i; continue }
                        if (sub_start && sub_end == 0 && substr(buf[i],1,4) == "### ") sub_end = i
                    }
                    if (sub_start && sub_end == 0) sub_end = sec_end
                }

                # Back the insertion point up over trailing blank lines so the
                # entry lands at the end of the list, not after a gap.
                if (sub_start)      { ins = sub_end; pre = "" }
                else if (sec_start) { ins = sec_end; pre = subsec }
                else                { ins = (footer ? footer : NR + 1); pre = (subsec == "" ? sec : sec "\n" subsec) }
                while (ins > 1 && buf[ins-1] == "") ins--

                for (i = 1; i <= NR; i++) {
                    if (i == ins) {
                        if (pre != "") print ""
                        if (pre != "") print pre
                        print line
                        print ""
                    }
                    print buf[i]
                }
                if (ins > NR) {
                    if (pre != "") { print ""; print pre }
                    print line
                }
            }
        ' <<< "$merged")
    done <<< "$tagged"

    # Collapse any runs of blank lines introduced by the insertions.
    awk 'NF == 0 { if (blank++) next } NF { blank = 0 } { print }' <<< "$merged"
}

step_changelog() {
    print_header "Step 3 · Changelog"

    # ── Retry: reuse the existing changelog for this version instead of ─────
    # regenerating it. pakku still ran in step_pakku (mods may have changed
    # since the last failed attempt), but the changelog TEXT is left as
    # whatever was previously written/approved for this version — we just
    # let the user re-review/edit it via the normal menu below.
    # Hotfix behaves the same way, except it does NOT stop there: the pakku
    # diff still runs and its new entries get merged into the prior changelog
    # below, so mods that updated since the aborted run are recorded.
    local PRIOR_CL=""
    if [[ "$BUMP_TYPE" == "retry" || "$BUMP_TYPE" == "hotfix" ]]; then
        # Prefer the newest hotfix changelog for this version, then the plain
        # one, then the top entry of CHANGELOG.md.
        local cand=""
        if [[ -d "$PACKCORE_MD_DIR" ]]; then
            # Highest-numbered hotfix changelog for this version, if any.
            # Numeric sort so -hotfix-10 beats -hotfix-2.
            local f n best_n=-1
            for f in "$PACKCORE_MD_DIR"/CHANGELOG-v"${NEW_VERSION}"-hotfix-*.md; do
                [[ -f "$f" ]] || continue
                n=$(sed -E 's/.*-hotfix-([0-9]+)\.md$/\1/' <<< "$f")
                [[ "$n" =~ ^[0-9]+$ ]] || continue
                if (( n > best_n )); then best_n=$n; cand="$f"; fi
            done
            if [[ -n "$cand" ]]; then
                PRIOR_CL=$(cat "$cand")
            elif [[ -f "$PACKCORE_MD_DIR/CHANGELOG-v${NEW_VERSION}.md" ]]; then
                PRIOR_CL=$(cat "$PACKCORE_MD_DIR/CHANGELOG-v${NEW_VERSION}.md")
            fi
        fi
        if [[ -z "$PRIOR_CL" ]] && [[ -f "$ROOT_CHANGELOG" ]] \
            && [[ "$(head -n1 "$ROOT_CHANGELOG")" == "# 🛠 Update ${NEW_VERSION}" ]]; then
            # Pull just the top entry (up to the second "---") out of CHANGELOG.md
            PRIOR_CL=$(awk '/^---$/{c++; if(c==2){exit}} {print}' "$ROOT_CHANGELOG")
        fi
    fi

    if [[ "$BUMP_TYPE" == "retry" ]]; then
        if [[ -n "$PRIOR_CL" ]]; then
            print_ok "Reusing existing changelog for v${NEW_VERSION} (retry — not regenerated from diff)."
            CHANGELOG_BODY="$PRIOR_CL"
        else
            print_warn "No previous changelog found for v${NEW_VERSION} — generating a new one from the pakku diff instead."
        fi
    elif [[ "$BUMP_TYPE" == "hotfix" ]]; then
        if [[ -n "$PRIOR_CL" ]]; then
            print_ok "Found existing changelog for v${NEW_VERSION} — this run's changes will be merged into it."
        else
            print_warn "No previous changelog found for v${NEW_VERSION} — generating a fresh one from the pakku diff."
        fi
    fi

    if [[ -z "$CHANGELOG_BODY" ]]; then

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

    # Load project types from both lock files so added, updated AND removed
    # entries classify correctly (removed projects only exist in the old lock).
    _load_type_lookup "$TMP_OLD_LOCK" "$LOCK_FILE"

    # ── Build auto-changelog ─────────────────────────────────────────────────
    if [[ "$diff_ok" == false ]]; then
        print_warn "pakku diff produced no output — using empty template."
        CHANGELOG_BODY=$(_build_changelog "" "$NEW_VERSION")
    else
        CHANGELOG_BODY=$(_build_changelog "$raw_diff" "$NEW_VERSION")
    fi

    # ── Hotfix merge ─────────────────────────────────────────────────────────
    # Fold this run's entries into the previously approved changelog so nothing
    # from the aborted attempt is lost.
    if [[ "$BUMP_TYPE" == "hotfix" && -n "$PRIOR_CL" ]]; then
        if [[ "$diff_ok" == true ]]; then
            CHANGELOG_BODY=$(_merge_changelog "$PRIOR_CL" "$CHANGELOG_BODY")
            print_ok "Merged this run's changes into the existing v${NEW_VERSION} changelog."
        else
            CHANGELOG_BODY="$PRIOR_CL"
            print_ok "No new mod changes this run — reusing the existing v${NEW_VERSION} changelog."
        fi
    fi

    fi # end: [[ -z "$CHANGELOG_BODY" ]] (retry-with-existing-changelog skips the block above)

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

    # Prepend to main CHANGELOG.md — unless the existing top entry is already
    # for this same version (e.g. a re-run after a failed CI attempt at the
    # same version), in which case replace that entry in place instead of
    # stacking a duplicate "# Update vX" block above it.
    if [[ -f "$ROOT_CHANGELOG" ]]; then
        local existing
        existing=$(cat "$ROOT_CHANGELOG")
        local top_title
        top_title=$(head -n1 <<< "$existing")

        if [[ "$top_title" == "# 🛠 Update ${NEW_VERSION}" ]]; then
            # Each generated entry contains exactly one internal "---" (before
            # the Troubleshooting footer), so the boundary between this top
            # entry and the next one is the *second* "---" line encountered.
            local rest_after_top
            rest_after_top=$(awk '/^---$/{c++; if(c==2){found=1; next}} found{print}' <<< "$existing")
            if [[ -n "$rest_after_top" ]]; then
                printf '%s\n\n---\n\n%s\n' "$CHANGELOG_BODY" "$rest_after_top" > "$ROOT_CHANGELOG"
            else
                echo "$CHANGELOG_BODY" > "$ROOT_CHANGELOG"
            fi
            print_ok "Updated CHANGELOG.md (replaced existing v${NEW_VERSION} entry)"
        else
            printf '%s\n\n---\n\n%s\n' "$CHANGELOG_BODY" "$existing" > "$ROOT_CHANGELOG"
            print_ok "Updated CHANGELOG.md"
        fi
    else
        echo "$CHANGELOG_BODY" > "$ROOT_CHANGELOG"
        print_ok "Updated CHANGELOG.md"
    fi

    # Write versioned changelog to packcore markdown dir. Hotfixes get a
    # suffixed filename so the original attempt's file is preserved.
    local cl_suffix=""
    [[ "$HOTFIX_N" -gt 0 ]] && cl_suffix="-hotfix-${HOTFIX_N}"

    if [[ -d "$PACKCORE_MD_DIR" ]]; then
        echo "$CHANGELOG_BODY" > "$PACKCORE_MD_DIR/CHANGELOG-v${NEW_VERSION}${cl_suffix}.md"
        print_ok "Wrote changelog to packcore/markdown/"
    fi

    # ── Assemble the final release-body.md ──────────────────────────────────
    # This is what gets published to GitHub/Modrinth/CurseForge. Building it
    # here (rather than in CI) means there's a single source of truth and
    # the author can preview the exact body that will ship.
    local release_body="$CHANGELOG_BODY"

    # Append config changelog if the config version changed since last tag.
    local cfg_json="$PACK_DIR/.pakku/overrides/packcore/configs/pack.json"
    local cfg_changelog="$PACK_DIR/.pakku/overrides/packcore/configs/CONFIG_CHANGELOG.md"
    local cur_cfg="none" prev_cfg="none"
    [[ -f "$cfg_json" ]] && cur_cfg=$(jq -r '.version // "none"' "$cfg_json" 2>/dev/null || echo "none")

    # PREV_TAG was resolved once in step_pakku — reuse it instead of a second
    # `git describe` that could disagree.
    if [[ "$PREV_TAG" != "none" ]]; then
        prev_cfg=$(git show "${PREV_TAG}:${cfg_json#"$REPO_ROOT"/}" 2>/dev/null \
            | jq -r '.version // "none"' 2>/dev/null || echo "none")
    fi

    if [[ -f "$cfg_changelog" && "$cur_cfg" != "$prev_cfg" && "$prev_cfg" != "none" ]]; then
        local cfg_body
        cfg_body=$(cat "$cfg_changelog")
        release_body+=$'\n\n## ⚙ Config Changes\n\n'"$cfg_body"
        print_ok "Appended CONFIG_CHANGELOG.md (config: ${prev_cfg} → ${cur_cfg})"
    fi

    # Write release-body.md to packcore/markdown so CI can pick it up as a
    # single artifact without having to reassemble anything.
    if [[ -d "$PACKCORE_MD_DIR" ]]; then
        echo "$release_body" > "$PACKCORE_MD_DIR/release-body-v${NEW_VERSION}${cl_suffix}.md"
        print_ok "Wrote release-body.md to packcore/markdown/"
    fi
}

# ── Kick off a Jenkins build immediately after the push (Option 3) ───────────
# Uses HTTP basic auth (JENKINS_USER + API token) plus the per-job build token,
# and fetches a CSRF crumb first so the POST isn't rejected with 403.
# Non-fatal: if anything here fails, the push already succeeded, so we just
# warn and let the user trigger the build manually / via Poll SCM.
_trigger_jenkins() {
    if [[ -z "$JENKINS_URL" ]]; then
        print_warn "JENKINS_URL not set — skipping auto-trigger."
        return 0
    fi
    if [[ -z "$JENKINS_API_TOKEN" || -z "$JENKINS_BUILD_TOKEN" ]]; then
        print_warn "Jenkins tokens not set (JENKINS_API_TOKEN / JENKINS_BUILD_TOKEN)."
        print_warn "Skipping auto-trigger — export them or set them at the top of this script."
        return 0
    fi

    local auth="${JENKINS_USER}:${JENKINS_API_TOKEN}"

    print_step "Triggering Jenkins job '${JENKINS_JOB}'..."

    # 1) Fetch a CSRF crumb (Jenkins default-on protection).
    local crumb
    crumb=$(curl -fsSL --user "$auth" \
        "${JENKINS_URL}/crumbIssuer/api/json" 2>/dev/null \
        | jq -r '"\(.crumbRequestField):\(.crumb)"' 2>/dev/null || echo "")

    # 2) POST to the build endpoint with the build token.
    local http_code
    if [[ -n "$crumb" && "$crumb" != *"null"* ]]; then
        http_code=$(curl -fsS -o /dev/null -w '%{http_code}' -X POST \
            --user "$auth" \
            -H "$crumb" \
            "${JENKINS_URL}/job/${JENKINS_JOB}/build?token=${JENKINS_BUILD_TOKEN}" \
            2>/dev/null || echo "000")
    else
        # No crumb issuer (CSRF disabled) — try without it.
        http_code=$(curl -fsS -o /dev/null -w '%{http_code}' -X POST \
            --user "$auth" \
            "${JENKINS_URL}/job/${JENKINS_JOB}/build?token=${JENKINS_BUILD_TOKEN}" \
            2>/dev/null || echo "000")
    fi

    # Jenkins returns 201 (queued) on success; 200 is also fine on some setups.
    if [[ "$http_code" == "201" || "$http_code" == "200" ]]; then
        print_ok "Jenkins build queued (HTTP ${http_code})."
    else
        print_warn "Jenkins trigger returned HTTP ${http_code}."
        print_warn "The push succeeded — start the build manually if needed:"
        print_warn "  ${JENKINS_URL}/job/${JENKINS_JOB}/"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
#  STEP 4 · GIT COMMIT & PUSH BRANCH  (Jenkins tags after its test passes)
# ═══════════════════════════════════════════════════════════════════════════
#
#   Flow:  release.sh  →  push branch  →  Jenkins (launch-test + refresh
#          modlist.json + create tag)  →  GitHub Actions (publish).
#
#   This script NO LONGER creates or pushes tags. Jenkins owns tagging so
#   that a release only ever gets tagged AFTER the headless launch-test
#   passes. The tag Jenkins derives comes from pakku.json's version, so the
#   only thing this script must guarantee is that pakku.json carries the
#   intended version and lands on the branch.
#
step_git() {
    print_header "Step 4 · Commit & Push Branch"

    # The tag Jenkins will eventually create (shown for reference only —
    # this script does not create it).
    local intended_tag="$RELEASE_TAG"

    # Safety: if that tag already exists on the remote, Jenkins will refuse to
    # re-release it (its Commit/Tag stage skips existing tags). Warn early so
    # the user isn't surprised when nothing publishes.
    #
    # Hotfixes deliberately reuse an existing PACK VERSION, but their TAG is
    # freshly numbered, so this check still applies to them meaningfully.
    if git ls-remote --exit-code --tags origin "refs/tags/${intended_tag}" &>/dev/null; then
        print_warn "Tag ${intended_tag} already exists on the remote."
        print_warn "Jenkins will skip tagging/publishing unless you bump the version."
        read -rp "  Push anyway? [y/N]: " push_anyway
        push_anyway="${push_anyway:-N}"
        if [[ ! "$push_anyway" =~ ^[Yy]$ ]]; then
            print_err "Aborted — bump the version in pakku.json to cut a new release."
            exit 1
        fi
    fi

    # Jenkins reads this instead of deriving the tag from pakku.json, so a
    # hotfix can ship the same pack version under a distinct tag.
    printf '%s\n' "$intended_tag" > "$REPO_ROOT/.release-tag"
    print_ok "Wrote .release-tag → ${intended_tag}"

    print_step "Staging all changes..."
    git add -A

    print_step "Committing..."
    local commit_msg
    if [[ "$BUMP_TYPE" == "hotfix" ]]; then
        commit_msg="release: ${NEW_VERSION} (hotfix ${HOTFIX_N}, tag ${intended_tag})"
    elif [[ "$RELEASE_TYPE" == "beta" ]]; then
        commit_msg="release: ${intended_tag} (beta pre-release)"
    else
        commit_msg="release: ${intended_tag}"
    fi

    # A re-run at the same version (after a failed CI attempt) may have no
    # staged changes, since pakku.json already carries this version. Allow an
    # empty commit so there's still a distinct commit for Jenkins to build/tag.
    if ! git diff --cached --quiet; then
        git commit -m "$commit_msg"
    else
        print_warn "No file changes to commit — creating an empty commit for Jenkins to tag."
        git commit --allow-empty -m "$commit_msg"
    fi

    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)

    print_step "Pushing branch ${current_branch} (Jenkins will pick this up)..."
    if ! git push origin "$current_branch"; then
        print_err "Push failed. Your commit is local; fix the remote and re-push:"
        print_err "  git push origin ${current_branch}"
        exit 1
    fi

    # Push succeeded — the version files are now safely on the remote, so
    # there's nothing to roll back.
    ROLLBACK_NEEDED=false
    rm -f "$TMP_OLD_LOCK"

    print_ok "Pushed ${current_branch}"

    # Fire the Jenkins build now (Option 3) so there's no Poll-SCM delay.
    _trigger_jenkins

    # Derive GitHub URL for convenience.
    local remote_url slug=""
    remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    if [[ "$remote_url" =~ github\.com[:/](.+?)(\.git)?$ ]]; then
        slug="${BASH_REMATCH[1]}"
        slug="${slug%.git}"
    fi

    echo ""
    echo -e "${BOLD}${GREEN}  ✔ Branch pushed — handoff to Jenkins.${NC}"
    echo -e "  Jenkins will now: launch-test → refresh modlist.json → tag ${BOLD}${intended_tag}${NC}"
    echo -e "  The tag then triggers GitHub Actions to publish."
    echo ""
    [[ -n "$JENKINS_URL" ]] && echo -e "  Monitor Jenkins: ${CYAN}${JENKINS_URL}/job/${JENKINS_JOB}/${NC}"
    [[ -n "$slug" ]] && echo -e "  Monitor Actions: ${CYAN}https://github.com/${slug}/actions${NC}"
}

# ═══════════════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════════════
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                cat <<EOF
Usage: ./release.sh [--dry-run]

Interactive release wizard for SkyBlock Enhanced.

Flow: this script bumps the version, runs pakku, generates the changelog,
then commits and PUSHES THE BRANCH. It does NOT tag. Jenkins picks up the
push, runs the headless launch-test, refreshes modlist.json, and creates
the release tag — which triggers GitHub Actions to publish.

Retry: if a previous attempt's tag never made it to the remote (e.g. the
Jenkins build never started/failed), the version-bump menu offers [R] to
retry the SAME version instead of forcing a new bump. pakku update/fetch/
export still runs (to pick up any changes since the last attempt), but the
changelog step reuses the existing changelog for that version instead of
regenerating it. Unavailable once the tag actually exists on the remote.

Hotfix: option [H] re-releases the SAME pack version under a new tag
(v<version>-hotfix-N). Use this when you cancelled a release job partway
through — typically because a mod update landed just after you started it.
pakku update/fetch/export runs again to pick up those changes, and the
changelog for this version is reused with the new entries merged into it
(version ranges are widened, e.g. 1.0 -> 1.1 plus 1.1 -> 1.2 becomes
1.0 -> 1.2). Always available; N auto-increments past existing hotfix tags.
Jenkins reads the tag from the .release-tag file this script writes.

Options:
  --dry-run   Run steps 1–3 (version bump, pakku update, changelog) but
              skip the git commit/push in step 4. Useful for testing
              changelog generation. JSON changes are rolled back at exit.
  -h, --help  Show this help.

Environment:
  VERBOSE=1   Show pakku diff debug output in step 3.
EOF
                exit 0
                ;;
            *)
                print_err "Unknown argument: $1"
                echo "  Run './release.sh --help' for usage."
                exit 1
                ;;
        esac
    done
}

main() {
    parse_args "$@"

    clear
    echo -e "${BOLD}${GREEN}"
    echo "  ╔══════════════════════════════════════════════╗"
    echo "  ║     SkyBlock Enhanced · Release Wizard       ║"
    echo "  ╚══════════════════════════════════════════════╝"
    echo -e "${NC}"

    if [[ "$DRY_RUN" == true ]]; then
        print_warn "DRY-RUN mode — no git commit/push will happen."
        echo ""
    fi

    check_deps

    # Jenkins (not this script) creates release tags after its launch-test
    # passes. Those tags won't exist locally until we fetch them, and
    # step_pakku uses the latest tag as the changelog baseline — so pull
    # them down first or the changelog will diff against a stale baseline.
    if [[ "$DRY_RUN" != true ]]; then
        print_step "Fetching remote tags (Jenkins creates release tags)..."
        git fetch --tags --quiet origin 2>/dev/null \
            || print_warn "Could not fetch tags — changelog baseline may be stale."
    fi

    step_version
    step_pakku
    step_changelog

    if [[ "$DRY_RUN" == true ]]; then
        print_header "🧪 Dry-Run Complete"
        echo -e "  Version   : ${BOLD}${NEW_VERSION}${NC}"
        echo -e "  Type      : ${BOLD}${RELEASE_TYPE}${NC}"
        echo -e "  Tag would be : ${BOLD}${RELEASE_TAG:-v$NEW_VERSION}${NC}"
        echo ""
        print_warn "Rolling back JSON changes (dry-run)..."
        rollback_json
        [[ -n "${TMP_OLD_LOCK:-}" && -f "$TMP_OLD_LOCK" ]] && rm -f "$TMP_OLD_LOCK"
        # Suppress the EXIT trap's rollback (already done, and exit will be 0)
        ROLLBACK_NEEDED=false
        exit 0
    fi

    step_git

    local final_tag="$RELEASE_TAG"

    if [[ "$RELEASE_TYPE" == "beta" ]]; then
        print_header "🧪 Beta Pushed — Awaiting Jenkins"
    else
        print_header "🎉 Release Pushed — Awaiting Jenkins"
    fi
    echo -e "  Version     : ${BOLD}${NEW_VERSION}${NC}"
    echo -e "  Type        : ${BOLD}${RELEASE_TYPE}${NC}"
    [[ "$HOTFIX_N" -gt 0 ]] && \
        echo -e "  Hotfix      : ${BOLD}#${HOTFIX_N}${NC}  ${YELLOW}(same pack version, new tag)${NC}"
    echo -e "  Tag (pending): ${BOLD}${final_tag}${NC}  ${YELLOW}← created by Jenkins after the launch-test${NC}"
    echo -e "  Changelog   : ${BOLD}CHANGELOG.md${NC} + packcore/markdown/"
    echo ""
    print_warn "Nothing is published yet. Jenkins must pass its launch-test first."
    echo ""
}

main "$@"
