#!/usr/bin/env bash
set -euo pipefail

# Records the onboarding demo scenes into README media.
#
#   ./scripts/record-demos.sh              # build, then record
#   SKIP_BUILD=1 ./scripts/record-demos.sh # record with the app already built
#
# Builds the Debug app, runs it in its recorder mode (DEBUG only), then encodes each captured loop
# into a looping GIF and a web-sized MP4 under docs/media/. Needs ffmpeg.
#
# Grant Screen Recording to build/Debug/ClipStack.app before the first run: the recorder films its
# own window through ScreenCaptureKit at 60 fps, and without the grant it falls back to rasterizing
# the presentation layer, which manages under 10 fps. Debug builds are ad-hoc signed, so every
# rebuild is a new identity to macOS and the grant has to be given again — re-record with
# SKIP_BUILD=1 to keep it.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BINARY="$ROOT_DIR/build/Debug/ClipStack.app/Contents/MacOS/ClipStack"
RAW_DIR="$ROOT_DIR/build/demos"
OUT_DIR="$ROOT_DIR/docs/media"
XCODE_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# GIF width in points. The capture itself is 2× this.
GIF_WIDTH="${GIF_WIDTH:-900}"
GIF_FPS="${GIF_FPS:-20}"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg not found. brew install ffmpeg" >&2
  exit 1
fi

if [[ ! -d "$XCODE_DIR" ]]; then
  echo "Xcode not found at $XCODE_DIR" >&2
  exit 1
fi

export DEVELOPER_DIR="$XCODE_DIR"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  xcodebuild build \
    -project "$ROOT_DIR/ClipStack.xcodeproj" \
    -scheme ClipStack \
    -configuration Debug \
    -destination 'platform=macOS,arch=arm64' \
    SYMROOT="$ROOT_DIR/build" \
    -quiet
fi

if [[ ! -x "$APP_BINARY" ]]; then
  echo "$APP_BINARY not found. Run without SKIP_BUILD=1 first." >&2
  exit 1
fi

# The recorder puts its scene windows on screen for about a minute. Keep the hands off the keyboard.
pkill -x ClipStack >/dev/null 2>&1 || true
sleep 0.5

rm -rf "$RAW_DIR"
mkdir -p "$RAW_DIR" "$OUT_DIR"

CLIPSTACK_RECORD_DEMOS="$RAW_DIR" "$APP_BINARY"

shopt -s nullglob

for movie in "$RAW_DIR"/*.mov; do
  name="$(basename "$movie" .mov)"

  ffmpeg -y -loglevel error -i "$movie" \
    -vf "fps=$GIF_FPS,scale=$GIF_WIDTH:-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" \
    -loop 0 "$OUT_DIR/$name.gif"

  ffmpeg -y -loglevel error -i "$movie" \
    -vf "scale=$((GIF_WIDTH * 3 / 2)):-2:flags=lanczos" \
    -an -c:v libx264 -pix_fmt yuv420p -crf 20 -preset slow -movflags +faststart \
    "$OUT_DIR/$name.mp4"
done

for still in "$RAW_DIR"/*.png; do
  name="$(basename "$still" .png)"
  ffmpeg -y -loglevel error -i "$still" -vf "scale=$((GIF_WIDTH * 3 / 2)):-2:flags=lanczos" "$OUT_DIR/$name.png"

  # A README screenshot is flat UI over one gradient — a palette holds it without visible banding.
  if command -v pngquant >/dev/null 2>&1; then
    pngquant --force --skip-if-larger --quality 80-98 --output "$OUT_DIR/$name.png" -- "$OUT_DIR/$name.png"
  fi
done

echo
echo "Wrote:"
ls -lh "$OUT_DIR" | tail -n +2 | awk '{printf "  %-28s %s\n", $9, $5}'
