#!/bin/bash
# Refreshes NorseMixology/Localizable.xcstrings from a fresh build's extracted strings.
# Xcode does this itself when building in the IDE; `xcodebuild` does not write the
# catalog back, so run this after a CLI build (e.g. in CI, or before committing).
#
# Usage: ios/scripts/sync-strings.sh [DERIVED_DATA_PATH]   (defaults to Xcode's DerivedData)
set -euo pipefail
cd "$(dirname "$0")/.."
DD="${1:-$HOME/Library/Developer/Xcode/DerivedData}"
ARGS=()
while IFS= read -r f; do ARGS+=(--stringsdata "$f"); done < <(find "$DD" -name '*.stringsdata' -path '*NorseMixology.build*' 2>/dev/null)
[ ${#ARGS[@]} -gt 0 ] || { echo "No .stringsdata found under $DD — build the app first." >&2; exit 1; }
xcrun xcstringstool sync NorseMixology/Localizable.xcstrings "${ARGS[@]}"
echo "Synced NorseMixology/Localizable.xcstrings"
