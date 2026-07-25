# ============================================================
#  gtkwave_signals.tcl
#  GTKWave signal configuration for parallel ALU simulation
#
#  Usage: gtkwave tb_parallel_alu.vcd gtkwave_signals.tcl
# ============================================================

# Add clock and control signals
gtkwave::addSignalsFromList {
    tb_parallel_alu.clk
    tb_parallel_alu.rst
    tb_parallel_alu.opcode_0[2:0]
    tb_parallel_alu.valid_0
    tb_parallel_alu.opcode_1[2:0]
    tb_parallel_alu.valid_1
}

# Add the key signal — gclk bus showing which units are active
gtkwave::addSignalsFromList {
    tb_parallel_alu.dut.gclk[9:0]
}

# Expand individual gclk bits for clarity
gtkwave::addSignalsFromList {
    tb_parallel_alu.dut.gclk[0]
    tb_parallel_alu.dut.gclk[1]
    tb_parallel_alu.dut.gclk[2]
    tb_parallel_alu.dut.gclk[3]
    tb_parallel_alu.dut.gclk[4]
    tb_parallel_alu.dut.gclk[5]
    tb_parallel_alu.dut.gclk[6]
    tb_parallel_alu.dut.gclk[7]
    tb_parallel_alu.dut.gclk[8]
    tb_parallel_alu.dut.gclk[9]
}

# Add results and stall signals
gtkwave::addSignalsFromList {
    tb_parallel_alu.alu_out[7:0]
    tb_parallel_alu.result_valid
    tb_parallel_alu.carry_out
    tb_parallel_alu.stall_0
    tb_parallel_alu.stall_1
}

gtkwave::/Time/Zoom/Zoom_Full
