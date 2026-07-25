#!/bin/bash
# ============================================================
#  run_sim.sh  —  Compile and simulate both ALU designs
#  Requires: iverilog, vvp, gtkwave (optional)
# ============================================================

set -e
echo "=============================================="
echo "  Clock-Gated ALU — Simulation Runner"
echo "=============================================="

SIM_DIR="$(cd "$(dirname "$0")" && pwd)"
RTL_DIR="$SIM_DIR/../rtl"

# ── Design 1: Clock-Gated ALU (correct per-op registers) ──
echo ""
echo "[1/2] Compiling clock_gated_alu.v ..."
iverilog -g2012 -o "$SIM_DIR/alu_sim" "$RTL_DIR/clock_gated_alu.v"
echo "      Running simulation ..."
vvp "$SIM_DIR/alu_sim"
echo "      VCD written: tb_clock_gated_alu.vcd"

# ── Design 2: Parallel Dispatch ALU ───────────────────────
echo ""
echo "[2/2] Compiling parallel_alu.v ..."
iverilog -g2012 -o "$SIM_DIR/parallel_sim" "$RTL_DIR/parallel_alu.v"
echo "      Running simulation ..."
vvp "$SIM_DIR/parallel_sim"
echo "      VCD written: tb_parallel_alu.vcd"

echo ""
echo "=============================================="
echo "  Done. Open .vcd files in GTKWave:"
echo "  gtkwave tb_clock_gated_alu.vcd"
echo "  gtkwave tb_parallel_alu.vcd"
echo ""
echo "  Key signal to observe in parallel ALU:"
echo "  gclk[9:0] — watch bits[1:0] both HIGH"
echo "  simultaneously during dual-ADD test"
echo "=============================================="
