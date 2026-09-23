#!/usr/bin/env bash
# Pulls the published catalog (manifest + content-hashed files) into the app repo's
# bundled snapshot: seed-data/ (read by the Android build), the iOS app resources,
# and the core package's test resources. Verifies every hash before writing anything.
#
# Usage: scripts/sync-catalog.sh [BASE_URL]
#   BASE_URL defaults to https://martinloeseth.dev/norse-catalog
set -euo pipefail

BASE="${1:-https://martinloeseth.dev/norse-catalog}/v1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL "$BASE/manifest.json" -o "$TMP/manifest.json"

read -r TAX_PATH TAX_SHA REC_PATH REC_SHA < <(python3 - "$TMP/manifest.json" <<'EOF'
import json, re, sys
m = json.load(open(sys.argv[1]))
assert m["schemaVersion"] == 1, "unsupported schemaVersion %r" % m["schemaVersion"]
for key in ("taxonomy", "recipes"):
    assert re.fullmatch(key + r"\.[0-9a-f]{8}\.json", m[key]["path"]), "bad path %r" % m[key]["path"]
    assert re.fullmatch(r"[0-9a-f]{64}", m[key]["sha256"]), "bad sha256"
print(m["taxonomy"]["path"], m["taxonomy"]["sha256"], m["recipes"]["path"], m["recipes"]["sha256"])
EOF
)

curl -fsSL "$BASE/$TAX_PATH" -o "$TMP/taxonomy.json"
curl -fsSL "$BASE/$REC_PATH" -o "$TMP/recipes.json"
echo "$TAX_SHA  $TMP/taxonomy.json" | shasum -a 256 -c -
echo "$REC_SHA  $TMP/recipes.json" | shasum -a 256 -c -

for dest in "$ROOT/seed-data" "$ROOT/ios/NorseMixology/Resources"; do
  cp "$TMP/manifest.json" "$TMP/taxonomy.json" "$TMP/recipes.json" "$dest/"
done
cp "$TMP/taxonomy.json" "$TMP/recipes.json" "$ROOT/ios/Packages/NorseMixologyCore/Tests/NorseMixologyCoreTests/Resources/"

python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); print("Synced catalog", m["contentVersion"], "generated", m["generatedAt"])' "$TMP/manifest.json"
