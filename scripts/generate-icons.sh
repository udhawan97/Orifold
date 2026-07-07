#!/bin/zsh
# ---------------------------------------------------------------------------
# generate-icons.sh — single source of truth → every platform icon asset.
#
# Canonical sources (hand-authored, versioned):
#   docs/assets/brand/orifold-crane-icon.svg        master (full detail, 128px+)
#   docs/assets/brand/orifold-crane-icon-small.svg  small variant (drawn for 16–64px)
#
# Everything else in the repo is a GENERATED artifact of this script. Never
# hand-edit the outputs; edit the two SVGs and re-run `zsh scripts/generate-icons.sh`.
#
# Requires: rsvg-convert, sips, iconutil (macOS), python3 (+Pillow for .ico/.png compose).
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRAND="$ROOT/docs/assets/brand"
MASTER="$BRAND/orifold-crane-icon.svg"
SMALL="$BRAND/orifold-crane-icon-small.svg"

APPICONSET="$ROOT/Orifold/Resources/Assets.xcassets/AppIcon.appiconset"
BOOTSTRAP_APP="$ROOT/Install or Update Orifold.app"
WEB_PUBLIC="$ROOT/docs-site/public"
WEB_ASSETS="$WEB_PUBLIC/assets"

command -v rsvg-convert >/dev/null || { echo "need rsvg-convert (brew install librsvg)"; exit 1; }
[[ -f "$MASTER" && -f "$SMALL" ]] || { echo "missing brand sources in $BRAND"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# render <src.svg> <px> <out.png>
render() { rsvg-convert -w "$2" -h "$2" "$1" -o "$3"; }

echo "==> macOS AppIcon PNGs (16/32/64 = small variant, 128+ = master)"
for sz in 16 32 64; do render "$SMALL"  "$sz" "$APPICONSET/AppIcon-$sz.png"; done
for sz in 128 256 512 1024; do render "$MASTER" "$sz" "$APPICONSET/AppIcon-$sz.png"; done

echo "==> Bootstrap installer AppIcon.icns"
ICONSET="$TMP/AppIcon.iconset"; mkdir -p "$ICONSET"
render "$SMALL"  16   "$ICONSET/icon_16x16.png"
render "$SMALL"  32   "$ICONSET/icon_16x16@2x.png"
render "$SMALL"  32   "$ICONSET/icon_32x32.png"
render "$SMALL"  64   "$ICONSET/icon_32x32@2x.png"
render "$MASTER" 128  "$ICONSET/icon_128x128.png"
render "$MASTER" 256  "$ICONSET/icon_128x128@2x.png"
render "$MASTER" 256  "$ICONSET/icon_256x256.png"
render "$MASTER" 512  "$ICONSET/icon_256x256@2x.png"
render "$MASTER" 512  "$ICONSET/icon_512x512.png"
render "$MASTER" 1024 "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$BOOTSTRAP_APP/Contents/Resources/AppIcon.icns"

echo "==> Web PNG icon variants"
mkdir -p "$WEB_ASSETS"
render "$SMALL"  32  "$WEB_ASSETS/orifold-app-icon-32.png"    # favicon PNG fallback
render "$MASTER" 128 "$WEB_ASSETS/orifold-app-icon-128.png"   # Starlight sidebar logo
render "$MASTER" 180 "$WEB_ASSETS/orifold-app-icon-180.png"   # apple-touch-icon
render "$MASTER" 192 "$WEB_ASSETS/orifold-app-icon-192.png"   # PWA manifest
render "$MASTER" 512 "$WEB_ASSETS/orifold-app-icon-512.png"   # PWA manifest

echo "==> Favicon SVG (static small variant)"
cp "$SMALL" "$WEB_PUBLIC/favicon.svg"

echo "==> favicon.ico (16/32/48 multi-resolution)"
render "$SMALL" 64 "$TMP/fico.png"
python3 - "$WEB_PUBLIC/favicon.ico" "$TMP/fico.png" <<'PY'
import sys
from PIL import Image
out, src = sys.argv[1:]
Image.open(src).convert("RGBA").save(out, format="ICO", sizes=[(48, 48), (32, 32), (16, 16)])
img = Image.open(out)
print("   wrote", out, "sizes:", sorted(img.ico.sizes()))
PY

echo "==> Open Graph / social card (1200x630)"
OG_SVG="$TMP/og.svg"
CRANE_INNER="$(python3 - "$MASTER" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
s=re.sub(r'^.*?<svg[^>]*>','',s,count=1,flags=re.S)
s=re.sub(r'</svg>\s*$','',s,flags=re.S)
print(s)
PY
)"
cat > "$OG_SVG" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 630">
<defs>
<linearGradient id="og-bg" x1="0" y1="0" x2="1" y2="1">
<stop offset="0" stop-color="#16233b"/><stop offset="0.6" stop-color="#20364f"/><stop offset="1" stop-color="#2a4a6e"/>
</linearGradient>
</defs>
<rect width="1200" height="630" fill="url(#og-bg)"/>
<svg x="96" y="107" width="416" height="416" viewBox="0 0 1024 1024">$CRANE_INNER</svg>
<g font-family="Helvetica Neue, Helvetica, Arial, sans-serif" fill="#ffffff">
<text x="560" y="300" font-size="104" font-weight="700" letter-spacing="-2">Orifold</text>
<text x="562" y="366" font-size="34" font-weight="400" fill="#aebfd4">Fold chaos into one clean PDF.</text>
<text x="562" y="418" font-size="27" font-weight="400" fill="#7f95b3">Free · open-source · 100% local · macOS</text>
</g>
</svg>
SVG
rsvg-convert -w 1200 -h 630 "$OG_SVG" -o "$WEB_ASSETS/orifold-og.png"

echo "==> done. Regenerated app, installer, and web icon assets from brand SVGs."
