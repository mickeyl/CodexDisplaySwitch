#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE="$ROOT/Assets/AppIcon.svg"
ICONSET="$ROOT/.build/AppIcon.iconset"
OUTPUT="$ROOT/Assets/AppIcon.icns"

command -v rsvg-convert >/dev/null || {
  echo "rsvg-convert is required (brew install librsvg)." >&2
  exit 1
}

mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  rsvg-convert -w "$SIZE" -h "$SIZE" "$SOURCE" -o "$ICONSET/icon_${SIZE}x${SIZE}.png"
  DOUBLE=$((SIZE * 2))
  rsvg-convert -w "$DOUBLE" -h "$DOUBLE" "$SOURCE" -o "$ICONSET/icon_${SIZE}x${SIZE}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$OUTPUT"
rsvg-convert -w 512 -h 512 "$SOURCE" -o "$ROOT/Assets/AppIcon.png"
echo "Created $OUTPUT"
