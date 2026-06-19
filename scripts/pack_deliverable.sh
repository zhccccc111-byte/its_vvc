#!/bin/bash
# Pack a clean deliverable directory for competition submission.
# Usage: bash scripts/pack_deliverable.sh [output_dir]
# Default output: its_vvc/deliver/

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="${1:-$ROOT_DIR/deliver}"

echo "=== ITS VVC Deliverable Pack ==="
echo "Source: $ROOT_DIR"
echo "Output: $OUT_DIR"
echo ""

# Clean previous deliverable
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# ---- RTL ----
echo "[1/5] Copying RTL..."
mkdir -p "$OUT_DIR/rtl"
cp "$ROOT_DIR"/rtl/*.v "$OUT_DIR/rtl/"
cp "$ROOT_DIR"/rtl/*.hex "$OUT_DIR/rtl/" 2>/dev/null || true

# ---- Testbench ----
echo "[2/5] Copying testbench..."
mkdir -p "$OUT_DIR/tb"
cp "$ROOT_DIR"/tb/its_tb.v "$OUT_DIR/tb/"
cp "$ROOT_DIR"/tb/its_tb_500.v "$OUT_DIR/tb/"

# Test vectors (hex + vh)
mkdir -p "$OUT_DIR/tb/test_vectors"
cp "$ROOT_DIR"/tb/test_vectors/*.hex "$OUT_DIR/tb/test_vectors/"
cp "$ROOT_DIR"/tb/test_vectors/*.vh "$OUT_DIR/tb/test_vectors/"

# ---- Simulation scripts ----
echo "[3/5] Copying simulation scripts..."
mkdir -p "$OUT_DIR/sim"
cp "$ROOT_DIR"/sim/run.do "$OUT_DIR/sim/"
cp "$ROOT_DIR"/sim/run_500.do "$OUT_DIR/sim/"
# Symlink targets (hex files for sim)
cp "$ROOT_DIR"/rtl/rom_coeffs.hex "$OUT_DIR/sim/" 2>/dev/null || true
cp "$ROOT_DIR"/rtl/lfnst_coeffs.hex "$OUT_DIR/sim/" 2>/dev/null || true

# ---- Documentation ----
echo "[4/5] Copying documentation..."
mkdir -p "$OUT_DIR/doc"
cp "$ROOT_DIR"/doc/*.md "$OUT_DIR/doc/"
cp "$ROOT_DIR"/doc/*.docx "$OUT_DIR/doc/" 2>/dev/null || true

# ---- Scripts ----
echo "[5/5] Copying scripts..."
mkdir -p "$OUT_DIR/scripts"
cp "$ROOT_DIR"/scripts/ref_model.py "$OUT_DIR/scripts/"
cp "$ROOT_DIR"/scripts/gen_test_vectors.py "$OUT_DIR/scripts/"
cp "$ROOT_DIR"/scripts/gen_rom_coeffs.py "$OUT_DIR/scripts/"
cp "$ROOT_DIR"/scripts/parse_lfnst_matrices.py "$OUT_DIR/scripts/"

# ---- Synth (OOC scripts only, no logs) ----
echo "[+] Copying synthesis scripts..."
mkdir -p "$OUT_DIR/synth"
cp "$ROOT_DIR"/synth/*.tcl "$OUT_DIR/synth/"
cp "$ROOT_DIR"/synth/*.xdc "$OUT_DIR/synth/" 2>/dev/null || true

# ---- Summary ----
FILE_COUNT=$(find "$OUT_DIR" -type f | wc -l)
DIR_SIZE=$(du -sh "$OUT_DIR" | cut -f1)
echo ""
echo "=== Done ==="
echo "Files: $FILE_COUNT"
echo "Size:  $DIR_SIZE"
echo "Location: $OUT_DIR"
echo ""
echo "Contents:"
find "$OUT_DIR" -type f | sed "s|$OUT_DIR/||" | sort
