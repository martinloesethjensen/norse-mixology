#!/usr/bin/env bash
# Pulls the published catalog (manifest + content-hashed files) into the app repo's
# bundled snapshot: seed-data/ (read by the Android build), the iOS app resources,
# and the core package's test resources. Verifies the manifest signature against the
# app's trusted keys (CatalogConfig.signingKeys) and every hash before writing anything.
#
# Usage: scripts/sync-catalog.sh [BASE_URL]
#   BASE_URL defaults to https://martinloeseth.dev/norse-catalog
#   Needs OpenSSL 3 for Ed25519 (macOS: brew install openssl@3, then set OPENSSL to its path).
set -euo pipefail

BASE="${1:-https://martinloeseth.dev/norse-catalog}/v1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OPENSSL="${OPENSSL:-openssl}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$OPENSSL" version | grep -q '^OpenSSL 3' || { echo "Needs OpenSSL 3; set OPENSSL to its path." >&2; exit 1; }

curl -fsSL "$BASE/manifest.json" -o "$TMP/manifest.json"
curl -fsSL "$BASE/manifest.json.sig" -o "$TMP/manifest.json.sig"

# Each trusted key is a raw Ed25519 public key; the fixed SPKI header turns it into a DER key for openssl.
python3 - "$ROOT/ios/NorseMixology/Catalog/CatalogLaunch.swift" "$TMP" <<'PY'
import base64, re, sys
swift, tmp = sys.argv[1], sys.argv[2]
line = re.search(r"static let signingKeys = \[(.*)\]", open(swift).read()).group(1)
try:
    keys = [base64.b64decode(k, validate=True) for k in re.findall(r'"([^"]+)"', line)]
except ValueError:
    keys = []
assert keys and all(len(k) == 32 for k in keys), "CatalogConfig.signingKeys holds no valid Ed25519 key"
for i, key in enumerate(keys):
    open(f"{tmp}/key{i}.der", "wb").write(bytes.fromhex("302a300506032b6570032100") + key)
open(f"{tmp}/sig.bin", "wb").write(base64.b64decode(open(f"{tmp}/manifest.json.sig").read().strip(), validate=True))
PY
VERIFIED=0
for key in "$TMP"/key*.der; do
  if "$OPENSSL" pkeyutl -verify -pubin -keyform DER -inkey "$key" -rawin -in "$TMP/manifest.json" -sigfile "$TMP/sig.bin" >/dev/null 2>&1; then
    VERIFIED=1
  fi
done
[ "$VERIFIED" = 1 ] || { echo "manifest.json signature does not verify against CatalogConfig.signingKeys" >&2; exit 1; }

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
