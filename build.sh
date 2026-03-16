#!/bin/bash
# build.sh - Package the workflow into a .alfredworkflow file.
#
# An .alfredworkflow file is just a zip archive containing the workflow files.
# Double-clicking the output file in Finder will install it in Alfred.

set -euo pipefail

OUTPUT="alfred-pgp.alfredworkflow"

# Validate plist before doing anything else
plutil -lint src/info.plist

# Resize icon from assets into src (build artifact, not committed)
sips -z 256 256 assets/icon-original.png --out src/icon.png > /dev/null

# Make scripts executable
chmod +x src/encrypt.sh src/decrypt.sh src/list_keys.js

# Remove old build if present
rm -f "$OUTPUT"

# -j strips the src/ path prefix so all files land at the root of the zip,
# which is what Alfred expects.
zip -j "$OUTPUT" src/*

echo ""
echo "Built: $OUTPUT"
echo "Double-click to install in Alfred, or run:"
echo "  open \"$OUTPUT\""
