`timescale 1ns/1ps
// ============================================================
//  clock_gated_alu_isolated.v
//  Clock-Gated 8-bit ALU with SELECTIVE OPERAND ISOLATION
//
//  Author : Kulamani Rout  |  github.com/kulamani007
//
//  Two-layer power optimisation:
//    Layer 1 - Clock gating (per-operation gclk)
//              Result registers static when unit is idle
//    Layer 2 - Operand isolation (AND-gate zeroing)
//              Combinational logic sees constant 0 when idle
//              -> eliminates glitching / spurious switching
//
//  SELECTIVE application (area/power tradeoff):
//    ISOLATED   : ADD, SUB, MUL  (deep combinational trees)
//    UNISOLATED : AND, OR, XOR, INC, DEC
//                 (single-level or shallow logic - isolation
//                  gates would cost more area than the
//                  glitching power they eliminate)
//
//  Isolation uses AND gates, not MUXes:
//    A & {8{en}}   -> 8 AND gates
//    en ? A : 8'h0 -> 8 two-input MUXes (~2x area)
// ============================================================

// ---- ICG cell ----------------------------------------------
module cg_cell_iso (
    input  wire clk,
    input  wire en,
    output wire gclk
);
    wire nand_out;
    assign nand_out = ~(clk & en);
    assign gclk     = nand_out ? 1'b0 : clk;
endmodule


// ---- 3-to-8 one-hot decoder --------------------------------
module decoder_iso (
    input  wire [2:0] opcode,
    output reg  [7:0] en
);
    always @(*) begin
        en = 8'b0;
        case (opcode)
            3'b000: en = 8'b0000_0001;  // ADD
            3'b001: en = 8'b0000_0010;  // SUB
            3'b010: en = 8'b0000_0100;  // MUL
            3'b011: en = 8'b0000_1000;  // INC
            3'b100: en = 8'b0001_0000;  // DEC
            3'b101: en = 8'b0010_0000;  // AND
            3'b110: en = 8'b0100_0000;  // OR
            3'b111: en = 8'b1000_0000;  // XOR
            default: en = 8'b0;
        endcase
    end
endmodule


// ---- TOP: ALU with selective operand isolation -------------
module alu_isolated (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  A,
    input  wire [7:0]  B,
    input  wire [2:0]  opcode,
    output reg  [7:0]  alu_out,
    output reg         carry_out
);

    // ---- Decode ------------------------------------------
    wire [7:0] en;
    decoder_iso dec (.opcode(opcode), .en(en));

    // ---- Clock gate array --------------------------------
    wire [7:0] gclk;
    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : CG
            cg_cell_iso cgc (.clk(clk), .en(en[g]), .gclk(gclk[g]));
        end
    endgenerate

    // ======================================================
    //  OPERAND ISOLATION LAYER
    //  When en[i]=0 the operand becomes 8'h00, so the
    //  combinational tree sees constant inputs and stops
    //  switching entirely.
    // ======================================================

    // ADD - isolated (8-level carry chain)
    wire [7:0] A_add = A & {8{en[0]}};
    wire [7:0] B_add = B & {8{en[0]}};

    // SUB - isolated (8-level borrow chain)
    wire [7:0] A_sub = A & {8{en[1]}};
    wire [7:0] B_sub = B & {8{en[1]}};

    // MUL - isolated (partial-product tree, deepest logic;
    //       zero operands force the whole PP tree to a
    //       stable all-zero state)
    wire [7:0] A_mul = A & {8{en[2]}};
    wire [7:0] B_mul = B & {8{en[2]}};

    // INC / DEC      - NOT isolated (single +1 / -1 adder)
    // AND / OR / XOR - NOT isolated (single gate level)

    // ======================================================
    //  FUNCTIONAL UNITS - per-operation gated registers
    // ======================================================

    reg [7:0] add_r, sub_r, mul_r, inc_r, dec_r;
    reg [7:0] and_r, or_r,  xor_r;
    reg       c_add, c_sub;

    // ADD - gclk[0], isolated operands
    always @(posedge gclk[0] or posedge rst) begin
        if (rst) {c_add, add_r} <= 9'b0;
        else     {c_add, add_r} <= {1'b0, A_add} + {1'b0, B_add};
    end

    // SUB - gclk[1], isolated operands
    always @(posedge gclk[1] or posedge rst) begin
        if (rst) {c_sub, sub_r} <= 9'b0;
        else     {c_sub, sub_r} <= {1'b0, A_sub} - {1'b0, B_sub};
    end

    // MUL - gclk[2], isolated operands
    always @(posedge gclk[2] or posedge rst) begin
        if (rst) mul_r <= 8'b0;
        else     mul_r <= A_mul * B_mul;
    end

    // INC - gclk[3], raw operand
    always @(posedge gclk[3] or posedge rst) begin
        if (rst) inc_r <= 8'b0;
        else     inc_r <= A + 8'h01;
    end

    // DEC - gclk[4], raw operand
    always @(posedge gclk[4] or posedge rst) begin
        if (rst) dec_r <= 8'b0;
        else     dec_r <= A - 8'h01;
    end

    // AND - gclk[5], raw operands
    always @(posedge gclk[5] or posedge rst) begin
        if (rst) and_r <= 8'b0;
        else     and_r <= A & B;
    end

    // OR - gclk[6], raw operands
    always @(posedge gclk[6] or posedge rst) begin
        if (rst) or_r <= 8'b0;
        else     or_r <= A | B;
    end

    // XOR - gclk[7], raw operands
    always @(posedge gclk[7] or posedge rst) begin
        if (rst) xor_r <= 8'b0;
        else     xor_r <= A ^ B;
    end

    // ---- Output MUX --------------------------------------
    always @(*) begin
        carry_out = 1'b0;
        case (opcode)
            3'b000: begin alu_out = add_r; carry_out = c_add; end
            3'b001: begin alu_out = sub_r; carry_out = c_sub; end
            3'b010:       alu_out = mul_r;
            3'b011:       alu_out = inc_r;
            3'b100:       alu_out = dec_r;
            3'b101:       alu_out = and_r;
            3'b110:       alu_out = or_r;
            3'b111:       alu_out = xor_r;
            default:      alu_out = 8'h00;
        endcase
    end

endmodule
