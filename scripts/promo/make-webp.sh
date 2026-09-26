#!/bin/sh
# Makes the README loop: docs/promo/umbra-loop.webp (720px, 30 fps, loops forever) from the rendered MP4.
# Needs ffmpeg and img2webp (brew install webp).
set -e
cd "$(dirname "$0")/../.."
TMP=$(mktemp -d)
ffmpeg -hide_banner -loglevel error -i docs/promo/umbra-loop.mp4 -vf "fps=30,scale=720:720:flags=lanczos" "$TMP/f%04d.png"
# -d 33 keeps 30 fps; lossy at q 72 keeps text crisp while holding the size down.
img2webp -loop 0 -lossy -q 72 -m 6 -d 33 "$TMP"/f*.png -o docs/promo/umbra-loop.webp >/dev/null
rm -rf "$TMP"
ls -lh docs/promo/umbra-loop.webp | awk '{print "Wrote docs/promo/umbra-loop.webp", $5}'
