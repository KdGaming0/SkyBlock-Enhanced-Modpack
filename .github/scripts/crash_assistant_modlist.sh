#!/usr/bin/env bash
# .github/scripts/crash_assistant_modlist.sh
# ─────────────────────────────────────────────────────────────────────────────
# Automates what "/crash_assistant modlist save" does manually in-game.
#
# Crash Assistant regenerates config/crash_assistant/modlist.json on every
# game launch when modpack_modlist.auto_update is enabled (this is the
# "modpack creator" mode described on the mod page). We enable that flag ONLY
# inside the CI test run directory (run/), so the config that ships to players
# keeps auto_update disabled and their modlist.json stays the official one.
#
# Two subcommands:
#
#   prepare   Run AFTER extract_mrpack.py and BEFORE the mc-runtime-test
#             launch. Patches run/config/crash_assistant/config.json so the
#             mod saves modlist.json during the headless launch.
#
#   harvest   Run AFTER a successful mc-runtime-test launch. Validates the
#             generated modlist.json, removes the mc-runtime-test mod entry
#             (the test harness injects its own mod into run/mods, which would
#             otherwise show up as "removed" in every player's crash report),
#             and copies the result into the pack's client-overrides so the
#             follow-up `pakku export` ships it.
#
# Environment:
#   PACK_DIR   Pack directory (default: SkyBlock_Enhanced_Modern_Edition_26.1)
#   RUN_DIR    Game directory used by the test (default: run)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PACK_DIR="${PACK_DIR:-SkyBlock_Enhanced_Modern_Edition_26.1}"
RUN_DIR="${RUN_DIR:-run}"

CI_CFG_TEMPLATE=".github/scripts/crash_assistant_ci_config.toml"
CFG="$RUN_DIR/config/crash_assistant/config.toml"
SRC="$RUN_DIR/config/crash_assistant/modlist.json"
DEST="$PACK_DIR/.pakku/client-overrides/config/crash_assistant/modlist.json"

# Entries added by the test harness itself, never part of the real pack.
# Matches "mc-runtime-test", "mc_runtime_test", "MC Runtime Test", "mcrt", etc.
HARNESS_REGEX='mc[-_ ]?runtime[-_ ]?test|^mcrt$'

info() { echo "  [INFO]  $*"; }
ok()   { echo "  [OK]    $*"; }
fail() { echo "  [FAIL]  $*" >&2; exit 1; }

prepare() {
    echo "  ── Crash Assistant · enable modlist auto-save (CI only) ──"
    mkdir -p "$(dirname "$CFG")"
    cp "$CI_CFG_TEMPLATE" "$CFG"
    ok "Installed CI-only $CFG from $CI_CFG_TEMPLATE"
}

harvest() {
    echo "  ── Crash Assistant · harvest generated modlist.json ──"

    if [[ ! -f "$SRC" ]]; then
        echo "  [FAIL]  $SRC was not generated during the client launch." >&2
        echo "          Likely causes:" >&2
        echo "          • Crash Assistant renamed/moved the auto-save option — check" >&2
        echo "            the modpack_modlist section of the config for your installed" >&2
        echo "            version and update the 'prepare' step of this script." >&2
        echo "          • The game exited before Crash Assistant initialised." >&2
        exit 1
    fi

    jq empty "$SRC" || fail "$SRC is not valid JSON"

    # Strip test-harness entries. modlist.json shape has varied between mod
    # versions (object keyed by mod name vs. array of entries), so handle both.
    tmp=$(mktemp)
    jq --arg re "$HARNESS_REGEX" '
        if type == "object" then
            with_entries(
                select(
                    ((.key | test($re; "i")) or (.value | tostring | test($re; "i"))) | not
                )
            )
        elif type == "array" then
            map(select((tostring | test($re; "i")) | not))
        else
            .
        end
    ' "$SRC" > "$tmp" || fail "Failed to filter harness entries from $SRC"

    before=$(jq 'if type=="object" then (keys|length) elif type=="array" then length else 1 end' "$SRC")
    after=$(jq  'if type=="object" then (keys|length) elif type=="array" then length else 1 end' "$tmp")
    info "Entries: $before generated, $((before - after)) harness entr(ies) removed, $after kept"

    (( after > 0 )) || fail "Filtered modlist is empty — refusing to ship it"

    mkdir -p "$(dirname "$DEST")"

    changed=true
    if [[ -f "$DEST" ]] && cmp -s "$tmp" "$DEST"; then
        changed=false
        info "modlist.json is identical to the committed copy"
    fi

    mv "$tmp" "$DEST"
    ok "Wrote $DEST"

    # Expose whether the file actually changed (used by the commit-back step).
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "changed=$changed" >> "$GITHUB_OUTPUT"
    fi
}

case "${1:-}" in
    prepare) prepare ;;
    harvest) harvest ;;
    *)
        echo "Usage: $0 {prepare|harvest}" >&2
        exit 2
        ;;
esac
