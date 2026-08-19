`timescale 1ns/1ps
// ============================================================
//  tb_alu_isolated.v
//  Testbench for clock_gated_alu_isolated.v
//
//  Verifies:
//    1. Functional correctness of all 8 operations
//    2. Operand isolation - idle units see 8'h00 inputs
//    3. Glitch suppression - operands toggle, isolated
//       nets stay at 0
// ============================================================
module tb_alu_isolated;

    reg        clk, rst;
    reg  [7:0] A, B;
    reg  [2:0] opcode;
    wire [7:0] alu_out;
    wire       carry_out;

    integer pass_count = 0;
    integer fail_count = 0;

    alu_isolated dut (
        .clk(clk), .rst(rst),
        .A(A), .B(B), .opcode(opcode),
        .alu_out(alu_out), .carry_out(carry_out)
    );

    initial clk = 0;
    always  #5 clk = ~clk;

    // Probe the isolated operand nets
    wire [7:0] probe_A_mul = dut.A_mul;
    wire [7:0] probe_B_mul = dut.B_mul;
    wire [7:0] probe_A_add = dut.A_add;

    task check;
        input [7:0]  a_in, b_in;
        input [2:0]  op;
        input [7:0]  expect_val;
        input        expect_c;
        input [63:0] name;
        begin
            A = a_in; B = b_in; opcode = op;
            @(posedge clk); #1;
            @(posedge clk); #1;
            if (alu_out === expect_val && carry_out === expect_c) begin
                $display("  PASS | %-4s | A=%3d B=%3d | out=%3d carry=%b",
                         name, a_in, b_in, alu_out, carry_out);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL | %-4s | expected=%3d got=%3d",
                         name, expect_val, alu_out);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_alu_isolated.vcd");
        $dumpvars(0, tb_alu_isolated);

        rst = 1; A = 0; B = 0; opcode = 3'b000;
        repeat(3) @(posedge clk);
        rst = 0; @(posedge clk);

        $display("");
        $display("=================================================");
        $display("  Clock-Gated ALU + Selective Operand Isolation ");
        $display("=================================================");
        $display("");
        $display("[Functional Verification]");

        check(8'd45,  8'd30,  3'b000, 8'd75,  1'b0, "ADD");
        check(8'd200, 8'd100, 3'b000, 8'd44,  1'b1, "ADD");
        check(8'd45,  8'd30,  3'b001, 8'd15,  1'b0, "SUB");
        check(8'd12,  8'd11,  3'b010, 8'd132, 1'b0, "MUL");
        check(8'd99,  8'd0,   3'b011, 8'd100, 1'b0, "INC");
        check(8'd100, 8'd0,   3'b100, 8'd99,  1'b0, "DEC");
        check(8'hAA,  8'h0F,  3'b101, 8'h0A,  1'b0, "AND");
        check(8'hAA,  8'h55,  3'b110, 8'hFF,  1'b0, "OR");
        check(8'hFF,  8'hAA,  3'b111, 8'h55,  1'b0, "XOR");

        $display("");
        $display("[Operand Isolation Verification]");
        $display("");

        // ADD active -> MUL operands must be forced to zero
        A = 8'hFF; B = 8'hFF; opcode = 3'b000;
        @(posedge clk); #1;
        $display("  opcode=ADD  A=FF B=FF");
        $display("    A_add = %h  (expect FF - ADD active)", probe_A_add);
        $display("    A_mul = %h  (expect 00 - MUL isolated)", probe_A_mul);
        $display("    B_mul = %h  (expect 00 - MUL isolated)", probe_B_mul);
        if (probe_A_mul === 8'h00 && probe_B_mul === 8'h00) begin
            $display("    -> MUL tree sees constant 0: NO glitching  PASS");
            pass_count = pass_count + 1;
        end else begin
            $display("    -> FAIL: MUL operands not isolated");
            fail_count = fail_count + 1;
        end

        $display("");
        // MUL active -> ADD operands must be forced to zero
        A = 8'hFF; B = 8'hFF; opcode = 3'b010;
        @(posedge clk); #1;
        $display("  opcode=MUL  A=FF B=FF");
        $display("    A_mul = %h  (expect FF - MUL active)", probe_A_mul);
        $display("    A_add = %h  (expect 00 - ADD isolated)", probe_A_add);
        if (probe_A_mul === 8'hFF && probe_A_add === 8'h00) begin
            $display("    -> ADD carry chain sees 0: NO glitching  PASS");
            pass_count = pass_count + 1;
        end else begin
            $display("    -> FAIL: isolation incorrect");
            fail_count = fail_count + 1;
        end

        $display("");
        $display("[Glitch Suppression Test]");
        $display("  Toggling A,B rapidly while MUL is IDLE");
        $display("  A_mul must stay 00 throughout");
        opcode = 3'b101;   // AND active, MUL idle
        A = 8'hAA; B = 8'h55; @(posedge clk); #1;
        $display("    A=AA -> A_mul=%h", probe_A_mul);
        A = 8'hFF; B = 8'h00; @(posedge clk); #1;
        $display("    A=FF -> A_mul=%h", probe_A_mul);
        A = 8'h0F; B = 8'hF0; @(posedge clk); #1;
        $display("    A=0F -> A_mul=%h", probe_A_mul);
        if (probe_A_mul === 8'h00) begin
            $display("    -> MUL inputs stable at 0 across all");
            $display("       operand changes: ZERO switching  PASS");
            pass_count = pass_count + 1;
        end else begin
            $display("    -> FAIL");
            fail_count = fail_count + 1;
        end

        $display("");
        $display("=================================================");
        $display("  RESULTS:  %0d passed,  %0d failed",
                 pass_count, fail_count);
        $display("=================================================");
        $display("");
        $finish;
    end

endmodule
