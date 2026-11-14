#!/usr/bin/env bash
# Regenerate Wordwank favicons and app icons from the master logo.
#
#   assets/logo/generate.sh [--install]
#
# Writes everything to assets/logo/wordwank/. With --install it also copies
# the web-facing set into srv/frontend/public/brands/wordwank/favicon/, the
# directory brand.js points at when the Wordwank skin is active.
#
# Requires ImageMagick 6 (`convert`). pngquant is used when present.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SRC="$HERE/wordwank-logo.png"            # 1254x1254 RGBA master
OUT="$HERE/wordwank"
INSTALL_DIR="$ROOT/srv/frontend/public/brands/wordwank/favicon"
BG='#2c3e50'                              # Wordwank --panel / theme-color

# The splash turns to noise below ~64px, so small icons use just the tile.
TILE_CROP='880x880+197+165'

mkdir -p "$OUT"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

convert "$SRC" -crop "$TILE_CROP" +repage "$tmp/tile.png"

# Transparent tile favicons (browser tabs, bookmarks, the in-game brand badge).
for s in 16 32 48 96; do
  convert "$tmp/tile.png" -filter Lanczos -resize "${s}x${s}" -strip "$OUT/favicon-${s}x${s}.png"
done
convert "$OUT/favicon-16x16.png" "$OUT/favicon-32x32.png" "$OUT/favicon-48x48.png" "$OUT/favicon.ico"

# Tile shown before the wordmark in WordwankLogo.jsx (header 44px, login 68px;
# 256px keeps it sharp on 3x screens).
convert "$tmp/tile.png" -filter Lanczos -resize 256x256 -strip "$OUT/logo-tile-256x256.png"

# iOS home screen: must be opaque (iOS paints transparency black) and square;
# iOS applies its own rounded mask.
convert "$SRC" -filter Lanczos -resize 180x180 -background "$BG" -flatten -strip "$OUT/apple-touch-icon.png"

# Android / PWA "any" icons: full logo, transparent.
for s in 192 512; do
  convert "$SRC" -filter Lanczos -resize "${s}x${s}" -strip "$OUT/web-app-manifest-${s}x${s}.png"
done

# Android "maskable" icons: launchers crop to anything from a circle to a
# squircle, guaranteeing only the centre 80%, so shrink the art into that
# safe zone over an opaque background.
for s in 192 512; do
  inner=$(( s * 80 / 100 ))
  convert "$SRC" -filter Lanczos -resize "${inner}x${inner}" \
    -background "$BG" -gravity center -extent "${s}x${s}" -strip \
    "$OUT/maskable-${s}x${s}.png"
done

if command -v pngquant >/dev/null; then
  pngquant --force --skip-if-larger --quality 80-98 --ext .png "$OUT"/*.png || true
fi

# SVG favicon: a raster wrapped in SVG, so browsers that prefer the SVG link
# (and the <img> brand badge) get the real artwork instead of the old drawing.
b64="$(base64 -w0 "$OUT/favicon-96x96.png")"
cat > "$OUT/favicon.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 96 96" width="96" height="96">
  <image width="96" height="96" xlink:href="data:image/png;base64,${b64}"/>
</svg>
EOF

echo "Generated icons in $OUT"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$INSTALL_DIR"
  for f in favicon.ico favicon.svg favicon-16x16.png favicon-32x32.png favicon-96x96.png \
           apple-touch-icon.png web-app-manifest-192x192.png web-app-manifest-512x512.png \
           maskable-192x192.png maskable-512x512.png logo-tile-256x256.png; do
    cp "$OUT/$f" "$INSTALL_DIR/$f"
  done
  echo "Installed into $INSTALL_DIR"
fi
