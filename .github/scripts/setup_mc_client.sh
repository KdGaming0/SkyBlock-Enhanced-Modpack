#!/usr/bin/env bash
# .github/scripts/setup_mc_client.sh
# ─────────────────────────────────────────────────────────────────────────────
# Tier 1 only: Validates the mrpack zip structure, checks that
# modrinth.index.json is well-formed, and HEAD-checks every download URL.
#
# Tier 2 (headless client launch) is handled by the mc-runtime-test GitHub
# Action in release.yml — this script no longer manages game launching.
#
# Usage:  .github/scripts/setup_mc_client.sh
#   (no flags; it always runs the full Tier 1 validation)
#
# NOTE: This script expects the mrpack under build/modrinth/ (no PACK_DIR
# prefix). This works because the test-client job in release.yml downloads
# the build artifact into a flat "build/" directory. If the artifact download
# path changes in the workflow, update the search path below to match.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

info() { echo "  [INFO]  $*"; }
ok()   { echo "  [OK]    $*"; }
fail() { echo "  [FAIL]  $*" >&2; exit 1; }

echo "  ── Tier 1 · mrpack validation ──────────────────────────"

# ── Locate the built mrpack ───────────────────────────────────────────────────
mrpack=$(find build/modrinth -name '*.mrpack' 2>/dev/null | head -n1 || true)
[[ -z "$mrpack" ]] && fail "No .mrpack found under build/modrinth/"
info "Validating: $mrpack"

# ── Zip integrity ─────────────────────────────────────────────────────────────
if ! python3 -c "import zipfile; zipfile.ZipFile('${mrpack}').testzip()" 2>/dev/null; then
    fail "mrpack is not a valid zip archive"
fi
ok "Valid zip archive"

# ── Index schema + URL reachability ──────────────────────────────────────────
python3 - "${mrpack}" << 'PYEOF'
import zipfile, json, sys, urllib.request, urllib.error, concurrent.futures

mrpack_path = sys.argv[1]

with zipfile.ZipFile(mrpack_path) as z:
    if 'modrinth.index.json' not in z.namelist():
        print("  [FAIL]  Missing modrinth.index.json", file=sys.stderr)
        sys.exit(1)
    index = json.loads(z.read('modrinth.index.json'))

for field in ('formatVersion', 'game', 'versionId', 'name', 'files'):
    if field not in index:
        print(f"  [FAIL]  modrinth.index.json missing field: {field}", file=sys.stderr)
        sys.exit(1)

files = index.get('files', [])
print(f"  [INFO]  {len(files)} files declared — checking download URLs...")

def check(f):
    path = f.get('path', '?')
    urls = f.get('downloads', [])
    if not urls:
        return path, False, "no download URL"
    try:
        req = urllib.request.Request(urls[0], method='HEAD')
        with urllib.request.urlopen(req, timeout=10) as r:
            return path, r.status == 200, f"HTTP {r.status}"
    except urllib.error.HTTPError as e:
        return path, False, f"HTTP {e.code}"
    except Exception as e:
        return path, False, str(e)

errors = []
ok_count = 0
with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
    for path, success, detail in pool.map(check, files):
        if success:
            ok_count += 1
        else:
            errors.append(f"{path}: {detail}")

if errors:
    print(f"\n  URL check failures ({len(errors)}):", file=sys.stderr)
    for e in errors:
        print(f"  [FAIL]  {e}", file=sys.stderr)
    sys.exit(1)

print(f"  [OK]    All {ok_count} download URLs reachable")
PYEOF

ok "Tier 1 passed"
echo "  ────────────────────────────────────────────────────────"
