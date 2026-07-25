`timescale 1ns/1ps
// ============================================================
//  opcode_decoder.v
//  3-to-8 One-Hot Opcode Decoder
//
//  Author  : Kulamani Rout
//  GitHub  : github.com/kulamani007
//
//  Description:
//    Converts 3-bit opcode into 8-bit one-hot enable vector.
//    Exactly ONE bit is HIGH per cycle. All other bits are LOW,
//    ensuring only one ICG cell passes its gated clock.
//
//  Bit mapping:
//    en[0] -> ADD   (3'b000)    en[4] -> DEC   (3'b100)
//    en[1] -> SUB   (3'b001)    en[5] -> AND   (3'b101)
//    en[2] -> MUL   (3'b010)    en[6] -> OR    (3'b110)
//    en[3] -> INC   (3'b011)    en[7] -> XOR   (3'b111)
// ============================================================
module opcode_decoder (
    input  wire [2:0] opcode,
    output reg  [7:0] en
);
    always @(*) begin
        en = 8'b0000_0000;
        case (opcode)
            3'b000: en = 8'b0000_0001;
            3'b001: en = 8'b0000_0010;
            3'b010: en = 8'b0000_0100;
            3'b011: en = 8'b0000_1000;
            3'b100: en = 8'b0001_0000;
            3'b101: en = 8'b0010_0000;
            3'b110: en = 8'b0100_0000;
            3'b111: en = 8'b1000_0000;
            default: en = 8'b0000_0000;
        endcase
    end
endmodule
