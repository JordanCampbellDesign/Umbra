#!/bin/sh
# Uploads the rendered promo MP4 to the "promo" pre-release, which the README links to.
# The MP4 is kept out of git so renders don't grow the repo.
set -e
cd "$(dirname "$0")/../.."
gh release upload promo docs/promo/umbra-loop.mp4 --clobber
echo "Uploaded docs/promo/umbra-loop.mp4 to the promo release."
