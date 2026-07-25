`timescale 1ns/1ps

// ================================================================
//  Dispatch-Based Parallel Clock-Gated ALU
//  10 functional unit instances, 2 issue slots
//  Minimal config: ADD×2, SUB×1, MUL×1, AND×2,
//                  OR×1, XOR×1, INC×1, DEC×1
// ================================================================

// ── MODULE 1: ICG Cell ──────────────────────────────────────────
module clock_gate_cell (
    input  wire clk, en,
    output wire gclk
);
    wire nand_out = ~(clk & en);
    assign gclk = nand_out ? 1'b0 : clk;
endmodule

// ── MODULE 2: 10-cell ICG Array ─────────────────────────────────
module clock_gate_array_10 (
    input  wire        clk,
    input  wire [9:0]  en,
    output wire [9:0]  gclk
);
    genvar i;
    generate
        for (i=0; i<10; i=i+1) begin : CG
            clock_gate_cell cg (.clk(clk),.en(en[i]),.gclk(gclk[i]));
        end
    endgenerate
endmodule

// ── MODULE 3: Opcode Decoder (10-bit output) ────────────────────
// Routes one opcode+valid pair to a free unit instance.
// busy[9:0] tells which instances are occupied.
// Returns en[9:0] one-hot selecting exactly one free instance.
//
// Unit index map:
//   [0]=ADD0  [1]=ADD1
//   [2]=SUB0  [3]=MUL0
//   [4]=AND0  [5]=AND1
//   [6]=OR0   [7]=XOR0
//   [8]=INC0  [9]=DEC0
module opcode_decoder_10b (
    input  wire [2:0]  opcode,
    input  wire        valid,
    input  wire [9:0]  busy,
    output reg  [9:0]  en,
    output reg         stall
);
    always @(*) begin
        en    = 10'b0;
        stall = 1'b0;
        if (valid) begin
            case (opcode)
                3'b000: begin // ADD — 2 instances
                    if      (!busy[0]) en = 10'b00_0000_0001;
                    else if (!busy[1]) en = 10'b00_0000_0010;
                    else               stall = 1'b1;
                end
                3'b001: begin // SUB
                    if (!busy[2]) en = 10'b00_0000_0100;
                    else          stall = 1'b1;
                end
                3'b010: begin // MUL
                    if (!busy[3]) en = 10'b00_0000_1000;
                    else          stall = 1'b1;
                end
                3'b011: begin // AND — 2 instances
                    if      (!busy[4]) en = 10'b00_0001_0000;
                    else if (!busy[5]) en = 10'b00_0010_0000;
                    else               stall = 1'b1;
                end
                3'b100: begin // OR
                    if (!busy[6]) en = 10'b00_0100_0000;
                    else          stall = 1'b1;
                end
                3'b101: begin // XOR
                    if (!busy[7]) en = 10'b00_1000_0000;
                    else          stall = 1'b1;
                end
                3'b110: begin // INC
                    if (!busy[8]) en = 10'b01_0000_0000;
                    else          stall = 1'b1;
                end
                3'b111: begin // DEC
                    if (!busy[9]) en = 10'b10_0000_0000;
                    else          stall = 1'b1;
                end
                default: en = 10'b0;
            endcase
        end
    end
endmodule

// ── MODULE 4: Functional Units ──────────────────────────────────
// Each unit:
//   - Has its own gclk (flat-zero when not dispatched)
//   - Has its own A,B operand inputs (from its assigned bus slot)
//   - Has its own result register (only toggles on its gclk)
//   - Asserts done for one cycle when result is ready
//   - busy=0 for single-cycle units (free next cycle)

module add_unit (
    input  wire        gclk, rst,
    input  wire [7:0]  A, B,
    output reg  [7:0]  result,
    output reg         carry,
    output reg         done
);
    always @(posedge gclk or posedge rst) begin
        if (rst) begin result<=0; carry<=0; done<=0; end
        else     begin {carry,result}<={1'b0,A}+{1'b0,B}; done<=1'b1; end
    end
    // Clear done after one cycle
    // (in full design this would be handshaked; simplified here)
endmodule

module sub_unit (
    input  wire        gclk, rst,
    input  wire [7:0]  A, B,
    output reg  [7:0]  result,
    output reg         borrow,
    output reg         done
);
    always @(posedge gclk or posedge rst) begin
        if (rst) begin result<=0; borrow<=0; done<=0; end
        else     begin {borrow,result}<={1'b0,A}-{1'b0,B}; done<=1'b1; end
    end
endmodule

// MUL: 2-cycle latency
module mul_unit (
    input  wire        gclk, rst,
    input  wire [7:0]  A, B,
    output reg  [7:0]  result,
    output reg         done,
    output reg         busy
);
    reg [7:0] A_l, B_l;
    reg       stage;
    always @(posedge gclk or posedge rst) begin
        if (rst) begin result<=0; done<=0; busy<=0; stage<=0; A_l<=0; B_l<=0; end
        else begin
            if (!stage) begin
                A_l<=A; B_l<=B; busy<=1'b1; done<=1'b0; stage<=1'b1;
            end else begin
                result<=A_l*B_l; done<=1'b1; busy<=1'b0; stage<=1'b0;
            end
        end
    end
endmodule

module and_unit (
    input  wire        gclk, rst,
    input  wire [7:0]  A, B,
    output reg  [7:0]  result,
    output reg         done
);
    always @(posedge gclk or posedge rst) begin
        if (rst) begin result<=0; done<=0; end
        else     begin result<=A&B; done<=1'b1; end
    end
endmodule

module or_unit (
    input  wire        gclk, rst,
    input  wire [7:0]  A, B,
    output reg  [7:0]  result,
    output reg         done
);
    always @(posedge gclk or posedge rst) begin
        if (rst) begin result<=0; done<=0; end
        else     begin result<=A|B; done<=1'b1; end
    end
endmodule

module xor_unit (
    input  wire        gclk, rst,
    input  wire [7:0]  A, B,
    output reg  [7:0]  result,
    output reg         done
);
    always @(posedge gclk or posedge rst) begin
        if (rst) begin result<=0; done<=0; end
        else     begin result<=A^B; done<=1'b1; end
    end
endmodule

module inc_unit (
    input  wire        gclk, rst,
    input  wire [7:0]  A,
    output reg  [7:0]  result,
    output reg         done
);
    always @(posedge gclk or posedge rst) begin
        if (rst) begin result<=0; done<=0; end
        else     begin result<=A+8'h01; done<=1'b1; end
    end
endmodule

module dec_unit (
    input  wire        gclk, rst,
    input  wire [7:0]  A,
    output reg  [7:0]  result,
    output reg         done
);
    always @(posedge gclk or posedge rst) begin
        if (rst) begin result<=0; done<=0; end
        else     begin result<=A-8'h01; done<=1'b1; end
    end
endmodule

// ── MODULE 5: Result MUX ────────────────────────────────────────
// Scans all 10 done signals. First asserted wins.
// In a real design this would tag results with destination tags.
module result_mux (
    input  wire [7:0] r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,
    input  wire       d0,d1,d2,d3,d4,d5,d6,d7,d8,d9,
    input  wire       c0,c1,      // carry: add0,add1
    input  wire       br2,        // borrow: sub0
    output reg  [7:0] alu_out,
    output reg        result_valid,
    output reg        carry_out
);
    always @(*) begin
        alu_out=8'h00; result_valid=0; carry_out=0;
        if      (d0) begin alu_out=r0; carry_out=c0;  result_valid=1; end
        else if (d1) begin alu_out=r1; carry_out=c1;  result_valid=1; end
        else if (d2) begin alu_out=r2; carry_out=br2; result_valid=1; end
        else if (d3) begin alu_out=r3; result_valid=1; end
        else if (d4) begin alu_out=r4; result_valid=1; end
        else if (d5) begin alu_out=r5; result_valid=1; end
        else if (d6) begin alu_out=r6; result_valid=1; end
        else if (d7) begin alu_out=r7; result_valid=1; end
        else if (d8) begin alu_out=r8; result_valid=1; end
        else if (d9) begin alu_out=r9; result_valid=1; end
    end
endmodule

// ── MODULE 6: TOP ────────────────────────────────────────────────
module parallel_alu_top (
    input  wire        clk, rst,
    // Issue slot 0
    input  wire [7:0]  A_0, B_0,
    input  wire [2:0]  opcode_0,
    input  wire        valid_0,
    // Issue slot 1
    input  wire [7:0]  A_1, B_1,
    input  wire [2:0]  opcode_1,
    input  wire        valid_1,
    // Outputs
    output wire [7:0]  alu_out,
    output wire        result_valid,
    output wire        carry_out,
    output wire        stall_0,
    output wire        stall_1
);

    // ── Busy vector (simplified: tied low for single-cycle units)
    // In a full design busy would be registered per unit.
    // For simulation clarity MUL drives its own busy bit.
    wire mul_busy;
    wire [9:0] busy = {1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,
                       mul_busy,1'b0,1'b0,1'b0};

    // ── Decode slot 0 ────────────────────────────────────────────
    wire [9:0] en_0;
    wire       st_0;
    opcode_decoder_10b dec0 (
        .opcode(opcode_0),.valid(valid_0),
        .busy(busy),.en(en_0),.stall(st_0)
    );
    assign stall_0 = st_0;

    // ── Decode slot 1 (sees en_0 already claimed) ────────────────
    wire [9:0] en_1;
    wire       st_1;
    opcode_decoder_10b dec1 (
        .opcode(opcode_1),.valid(valid_1),
        .busy(busy | en_0),   // en_0 already taken a unit
        .en(en_1),.stall(st_1)
    );
    assign stall_1 = st_1;

    // ── Combine enables — BITWISE OR (no carry, no corruption) ───
    wire [9:0] en_final = en_0 | en_1;

    // ── 10 ICG cells ─────────────────────────────────────────────
    wire [9:0] gclk;
    clock_gate_array_10 cga (.clk(clk),.en(en_final),.gclk(gclk));

    // ── Operand routing ──────────────────────────────────────────
    // Unit gets slot-0 operands if en_0 selected it,
    // else slot-1 operands. Simple MUX per unit.
    // For replicated units: ADD0←slot0, ADD1←slot1 when both active
    wire [7:0] A_u [0:9], B_u [0:9];

    assign A_u[0]=en_0[0]?A_0:A_1; assign B_u[0]=en_0[0]?B_0:B_1; // ADD0
    assign A_u[1]=A_1;              assign B_u[1]=B_1;               // ADD1 always slot1
    assign A_u[2]=en_0[2]?A_0:A_1; assign B_u[2]=en_0[2]?B_0:B_1; // SUB0
    assign A_u[3]=en_0[3]?A_0:A_1; assign B_u[3]=en_0[3]?B_0:B_1; // MUL0
    assign A_u[4]=en_0[4]?A_0:A_1; assign B_u[4]=en_0[4]?B_0:B_1; // AND0
    assign A_u[5]=A_1;              assign B_u[5]=B_1;               // AND1 always slot1
    assign A_u[6]=en_0[6]?A_0:A_1; assign B_u[6]=en_0[6]?B_0:B_1; // OR0
    assign A_u[7]=en_0[7]?A_0:A_1; assign B_u[7]=en_0[7]?B_0:B_1; // XOR0
    assign A_u[8]=en_0[8]?A_0:A_1; assign B_u[8]=en_0[8]?B_0:B_1; // INC0
    assign A_u[9]=en_0[9]?A_0:A_1; assign B_u[9]=en_0[9]?B_0:B_1; // DEC0

    // ── Functional units ─────────────────────────────────────────
    wire [7:0] res [0:9];
    wire       done[0:9];
    wire       c0,c1,br2;

    add_unit add0(.gclk(gclk[0]),.rst(rst),.A(A_u[0]),.B(B_u[0]),
                  .result(res[0]),.carry(c0),.done(done[0]));
    add_unit add1(.gclk(gclk[1]),.rst(rst),.A(A_u[1]),.B(B_u[1]),
                  .result(res[1]),.carry(c1),.done(done[1]));
    sub_unit sub0(.gclk(gclk[2]),.rst(rst),.A(A_u[2]),.B(B_u[2]),
                  .result(res[2]),.borrow(br2),.done(done[2]));
    mul_unit mul0(.gclk(gclk[3]),.rst(rst),.A(A_u[3]),.B(B_u[3]),
                  .result(res[3]),.done(done[3]),.busy(mul_busy));
    and_unit and0(.gclk(gclk[4]),.rst(rst),.A(A_u[4]),.B(B_u[4]),
                  .result(res[4]),.done(done[4]));
    and_unit and1(.gclk(gclk[5]),.rst(rst),.A(A_u[5]),.B(B_u[5]),
                  .result(res[5]),.done(done[5]));
    or_unit  or0 (.gclk(gclk[6]),.rst(rst),.A(A_u[6]),.B(B_u[6]),
                  .result(res[6]),.done(done[6]));
    xor_unit xor0(.gclk(gclk[7]),.rst(rst),.A(A_u[7]),.B(B_u[7]),
                  .result(res[7]),.done(done[7]));
    inc_unit inc0(.gclk(gclk[8]),.rst(rst),.A(A_u[8]),
                  .result(res[8]),.done(done[8]));
    dec_unit dec_u0(.gclk(gclk[9]),.rst(rst),.A(A_u[9]),
                   .result(res[9]),.done(done[9]));

    // ── Result MUX ───────────────────────────────────────────────
    result_mux rmux (
        .r0(res[0]),.r1(res[1]),.r2(res[2]),.r3(res[3]),.r4(res[4]),
        .r5(res[5]),.r6(res[6]),.r7(res[7]),.r8(res[8]),.r9(res[9]),
        .d0(done[0]),.d1(done[1]),.d2(done[2]),.d3(done[3]),.d4(done[4]),
        .d5(done[5]),.d6(done[6]),.d7(done[7]),.d8(done[8]),.d9(done[9]),
        .c0(c0),.c1(c1),.br2(br2),
        .alu_out(alu_out),.result_valid(result_valid),.carry_out(carry_out)
    );

endmodule

// ── MODULE 7: TESTBENCH ──────────────────────────────────────────
module tb_parallel_alu;
    reg        clk,rst;
    reg  [7:0] A_0,B_0; reg [2:0] opcode_0; reg valid_0;
    reg  [7:0] A_1,B_1; reg [2:0] opcode_1; reg valid_1;
    wire [7:0] alu_out;
    wire       result_valid,carry_out,stall_0,stall_1;

    parallel_alu_top dut(
        .clk(clk),.rst(rst),
        .A_0(A_0),.B_0(B_0),.opcode_0(opcode_0),.valid_0(valid_0),
        .A_1(A_1),.B_1(B_1),.opcode_1(opcode_1),.valid_1(valid_1),
        .alu_out(alu_out),.result_valid(result_valid),
        .carry_out(carry_out),.stall_0(stall_0),.stall_1(stall_1)
    );

    initial clk=0;
    always  #5 clk=~clk;

    // Also expose internal gclk for inspection
    wire [9:0] gclk_probe = dut.gclk;

    task show;
        input [127:0] label;
        begin
            @(posedge clk); #2;
            $display("[%s] out=%0d valid=%b carry=%b | gclk=%010b | st0=%b st1=%b",
                label, alu_out, result_valid, carry_out,
                gclk_probe, stall_0, stall_1);
        end
    endtask

    initial begin
        $dumpfile("tb_parallel_alu.vcd");
        $dumpvars(0,tb_parallel_alu);

        rst=1; valid_0=0; valid_1=0;
        A_0=0; B_0=0; A_1=0; B_1=0;
        opcode_0=0; opcode_1=0;
        repeat(3) @(posedge clk); rst=0;

        $display("=================================================");
        $display("  Dispatch-Based Parallel Clock-Gated ALU       ");
        $display("  gclk bits: [9]DEC [8]INC [7]XOR [6]OR        ");
        $display("             [5]AND1 [4]AND0 [3]MUL             ");
        $display("             [2]SUB [1]ADD1 [0]ADD0             ");
        $display("=================================================");

        // ── Test 1: Single ADD ──────────────────────────────────
        $display("\n[TEST 1] Single ADD: 10+20 = 30");
        $display("         expect: gclk[0]=1 only, all others=0");
        A_0=10; B_0=20; opcode_0=3'b000; valid_0=1;
        A_1=0;  B_1=0;  opcode_1=3'b000; valid_1=0;
        show("ADD(10+20)      ");
        valid_0=0;
        $display("         RESULT: %0d (expect 30)", alu_out);

        // ── Test 2: Two different ops same cycle ────────────────
        $display("\n[TEST 2] Parallel: ADD(45+30) || AND(0xAA&0x0F)");
        $display("         expect: gclk[0]=1 AND gclk[4]=1 simultaneously");
        A_0=45;   B_0=30;   opcode_0=3'b000; valid_0=1; // ADD → gclk[0]
        A_1=8'hAA;B_1=8'h0F;opcode_1=3'b011; valid_1=1; // AND → gclk[4]
        show("ADD||AND cycle1 ");
        valid_0=0; valid_1=0;
        @(posedge clk); #2;
        $display("         cycle1 result=%0d | cycle2 result=%0d",
                 alu_out, alu_out);

        // ── Test 3: TWO SAME ops — the key test ─────────────────
        $display("\n[TEST 3] TWO ADD requests: ADD(10+20) || ADD(45+30)");
        $display("         expect: gclk[0]=1 AND gclk[1]=1 simultaneously");
        $display("         ADD0 gets (10,20), ADD1 gets (45,30)");
        $display("         NO operand collision — each unit independent");
        A_0=10; B_0=20; opcode_0=3'b000; valid_0=1; // → ADD unit 0
        A_1=45; B_1=30; opcode_1=3'b000; valid_1=1; // → ADD unit 1
        @(posedge clk); #2;
        $display("         gclk=%010b (bits[1:0] should both=1)", gclk_probe);
        $display("         ADD0 result=%0d (expect 30)", dut.res[0]);
        $display("         ADD1 result=%0d (expect 75)", dut.res[1]);
        valid_0=0; valid_1=0;

        // ── Test 4: MUL 2-cycle latency ─────────────────────────
        $display("\n[TEST 4] MUL(12*11=132) — 2 cycle latency");
        A_0=12; B_0=11; opcode_0=3'b010; valid_0=1;
        A_1=0;  B_1=0;  opcode_1=3'b000; valid_1=0;
        @(posedge clk); #2;  // cycle 1 — latch operands into MUL
        $display("         Cycle 1: gclk=%010b busy=%b done=%b",
                 gclk_probe, dut.mul_busy, dut.done[3]);
        // Keep valid_0 high so gclk[3] keeps ticking for cycle 2
        @(posedge clk); #2;  // cycle 2 — result ready
        valid_0=0;
        $display("         Cycle 2: result=%0d (expect 132)", dut.res[3]);

        // ── Test 5: SUB + XOR parallel ──────────────────────────
        $display("\n[TEST 5] Parallel: SUB(45-30) || XOR(0xFF^0xAA)");
        $display("         expect: gclk[2]=1 AND gclk[7]=1 simultaneously");
        A_0=45;   B_0=30;   opcode_0=3'b001; valid_0=1; // SUB → gclk[2]
        A_1=8'hFF;B_1=8'hAA;opcode_1=3'b101; valid_1=1; // XOR → gclk[7]
        @(posedge clk); #2;
        $display("         gclk=%010b (bits[7,2] should=1)", gclk_probe);
        $display("         SUB result=%0d (expect 15)",  dut.res[2]);
        $display("         XOR result=%h (expect 55)",   dut.res[7]);
        valid_0=0; valid_1=0;

        // ── Test 6: Stall — MUL busy, second MUL request ────────
        // Single-cycle units free immediately so ADD stall is
        // only visible within same combinational cycle.
        // MUL has busy=1 across 2 cycles — best stall demo.
        $display("\n[TEST 6] Stall: MUL busy (2-cycle), second MUL arrives");
        $display("         expect stall_0=1 on second MUL request");
        // Start MUL
        A_0=5; B_0=6; opcode_0=3'b010; valid_0=1; valid_1=0;
        @(posedge clk); #2;
        $display("         MUL started. busy=%b gclk=%010b",
                 dut.mul_busy, gclk_probe);
        // MUL now busy. Request another MUL same cycle.
        A_0=7; B_0=8; opcode_0=3'b010; valid_0=1;
        #1; // combinational check before next edge
        $display("         2nd MUL while busy: stall0=%b (expect 1)", stall_0);
        valid_0=0;

        repeat(3) @(posedge clk);
        $display("\n=================================================");
        $display("  DONE. Open tb_parallel_alu.vcd in GTKWave.");
        $display("  Key signal to watch: gclk[9:0]");
        $display("  Test 3: gclk[1:0] both HIGH same cycle = parallel ADD");
        $display("=================================================");
        $finish;
    end
endmodule
