#!/usr/bin/env bash
# .github/scripts/crash_assistant_modlist.sh
# ─────────────────────────────────────────────────────────────────────────────
# Automates what "/crash_assistant modlist save" does manually in-game.
#
# Crash Assistant's modpack_modlist.auto_update *would* regenerate
# config/crash_assistant/modlist.json on every game launch — but only "on
# the first tick of TitleScreen". mc-runtime-test's headless client joins a
# singleplayer world directly and never renders a TitleScreen, so that hook
# never fires here. `prepare` still enables auto_update as a harmless
# fallback (config that ships to players keeps auto_update disabled either
# way), but the actual save is triggered by the CI-only
# ca-modlist-ci-trigger Fabric mod (.github/testmods/ca-modlist-ci-trigger/),
# which fires the manual "/crash_assistant modlist save" command itself a
# few ticks after world join. See that mod's README for the full story.
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

# Entries added by CI tooling itself, never part of the real pack:
#   - the mc-runtime-test harness mod: "mc-runtime-test", "mc_runtime_test",
#     "MC Runtime Test", "mcrt", etc.
#   - our own ca-modlist-ci-trigger mod (modid ca_modlist_ci_trigger, name
#     "Crash Assistant Modlist CI Trigger") — see
#     .github/testmods/ca-modlist-ci-trigger/README.md
HARNESS_REGEX='mc[-_ ]?runtime[-_ ]?test|^mcrt$|ca[-_ ]?modlist[-_ ]?ci[-_ ]?trigger'

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
        echo "          • ca-modlist-ci-trigger mod didn't fire (this is the most" >&2
        echo "            common cause — Crash Assistant's own auto_update never" >&2
        echo "            fires under mc-runtime-test in the first place, since it" >&2
        echo "            only triggers on the TitleScreen tick and mc-runtime-test" >&2
        echo "            skips straight into a world). Check:" >&2
        echo "              - Did 'Build modlist CI trigger mod' / 'Stage modlist CI" >&2
        echo "                trigger mod into run/mods' succeed earlier in this job?" >&2
        echo "              - Does run/logs/latest.log contain" >&2
        echo "                '[ca-modlist-ci-trigger]' lines? If absent, the jar" >&2
        echo "                likely never made it into run/mods/ before launch." >&2
        echo "              - If present but no 'Sending ...' line followed, the" >&2
        echo "                DELAY_TICKS window in ModlistCiTrigger.java may be" >&2
        echo "                longer than mc-runtime-test's own quit timer — the" >&2
        echo "                world only reached 'Preparing spawn area: 16%' in one" >&2
        echo "                observed run before the harness quit at ~20s." >&2
        echo "          • Crash Assistant renamed/moved the manual-save command or" >&2
        echo "            the auto-save option — check the modpack_modlist section" >&2
        echo "            of the config for your installed version and update the" >&2
        echo "            'prepare' step of this script / the trigger mod's COMMAND." >&2
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
