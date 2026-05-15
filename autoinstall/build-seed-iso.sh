#!/usr/bin/env bash
# 1. Generates user-data from .env
# 2. Builds seed.iso from user-data + meta-data
# Usage: bash build-seed-iso.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Step 1: Generate user-data ==="
bash generate.sh

echo "=== Step 2: Build seed.iso ==="
if command -v genisoimage &>/dev/null; then
  genisoimage -output seed.iso -volid cidata -rational-rock -joliet user-data meta-data
elif command -v mkisofs &>/dev/null; then
  mkisofs -output seed.iso -volid cidata -rational-rock -joliet user-data meta-data
elif command -v xorriso &>/dev/null; then
  xorriso -as mkisofs -output seed.iso -volid cidata -rational-rock -joliet user-data meta-data
else
  echo "ERROR: install genisoimage, mkisofs, or xorriso first."
  echo "  Ubuntu/Debian: sudo apt install genisoimage"
  echo "  macOS:         brew install xorriso"
  exit 1
fi

echo ""
echo "=== Done ==="
echo "Built: $SCRIPT_DIR/seed.iso  ($(du -sh seed.iso | cut -f1))"
