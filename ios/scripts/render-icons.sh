#!/usr/bin/env bash
# Renders the app icon and launch-mark PNGs from the SVG masters in ios/design/.
# Run after editing any master; commit the SVGs and the PNGs together.
set -euo pipefail

if ! command -v rsvg-convert >/dev/null; then
    echo "rsvg-convert not found — install it with: brew install librsvg" >&2
    exit 1
fi

ios="$(cd "$(dirname "$0")/.." && pwd)"
design="$ios/design"
assets="$ios/NorseMixology/Assets.xcassets"

# render <master.svg> <width> <height> <output.png>
render() {
    rsvg-convert -w "$2" -h "$3" "$design/$1" -o "$4"
    echo "rendered $(basename "$4")"
}

for variant in light dark tinted; do
    render "icon-$variant.svg" 1024 1024 "$assets/AppIcon.appiconset/icon-$variant.png"
done

mkdir -p "$assets/LaunchMark.imageset"
for variant in light dark; do
    render "launch-mark-$variant.svg" 360 300 "$assets/LaunchMark.imageset/launch-mark-$variant@2x.png"
    render "launch-mark-$variant.svg" 540 450 "$assets/LaunchMark.imageset/launch-mark-$variant@3x.png"
done
