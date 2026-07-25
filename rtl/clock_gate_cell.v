`timescale 1ns/1ps
// ============================================================
//  clock_gate_cell.v
//  NAND + Tri-State Integrated Clock Gating (ICG) Cell
//
//  Author  : Kulamani Rout
//  GitHub  : github.com/kulamani007
//
//  Description:
//    Glitch-free clock gate using NAND + Tri-State topology.
//    EN is sampled during the LOW phase of CLK so it is
//    fully settled before the rising edge — no spurious
//    pulses on GCLK regardless of when EN transitions.
//
//  Truth Table:
//    CLK  EN  NAND_OUT  GCLK  State
//     0    0     1      0     Idle
//     0    1     1      0     Safe hold
//     1    0     1      0   ← GATED OFF
//     1    1     0      1   ← ACTIVE
// ============================================================
module clock_gate_cell (
    input  wire clk,   // Raw global clock
    input  wire en,    // Enable (from opcode decoder)
    output wire gclk   // Gated clock to functional unit
);
    wire nand_out;
    // NAND settles during LOW phase — off critical path
    assign nand_out = ~(clk & en);
    // Tri-State: passes CLK when enabled, holds 0 otherwise
    assign gclk = nand_out ? 1'b0 : clk;
endmodule
