# Architecture Notes — Design Decisions and Tradeoff Analysis

## Why Per-Operation Registers Instead of One Shared Register

A natural first implementation uses one `result` register and a `case`
statement selecting which computation to capture:

```verilog
// Naive — one shared register
always @(posedge gclk) begin
  case (opcode)
    ADD: result <= A + B;
    SUB: result <= A - B;
    ...
  endcase
end
```

The `case` statement is purely combinational selection. The synthesiser
infers ONE flip-flop. When `gclk` is gated off, that one register is
static — power saving is real on the register side.

However, the combinational adder, subtractor, and multiplier paths all
evaluate continuously regardless of the clock. This is unavoidable in a
shared datapath. The register holds the right value but all combinational
paths are switching.

The per-operation register design separates each operation into its own
`always` block on its own `gclk[i]`:

```verilog
always @(posedge gclk[0]) add_result <= A + B;  // ADD only
always @(posedge gclk[1]) sub_result <= A - B;  // SUB only
```

Now each register is truly independent. When `gclk[0]` is flat-zero,
the ADD register never toggles. The area cost is more registers (8 vs 1
or 2), but the isolation is complete on the register side.

**The right architectural choice depends on the target:**
- Area-constrained: shared register with group-level gating
- Power-critical large design: per-operation register isolation

## Why Bitwise OR for Multi-Hot Enable Combination

See README. The short version: enable bits are boolean flags, not numeric
quantities. OR is idempotent (1|1=1). Addition is not (1+1=2, carry
corrupts adjacent bit). Always use OR when combining one-hot enables.

## Why ADD and AND Are Replicated in Design 2

Instruction frequency analysis of typical embedded workloads:
- ADD: ~40% of all instructions
- AND: ~15% (bitwise masking very common)
- MUL: ~8% (expensive but infrequent)

Replicating ADD×2 and AND×2 means two of the most common operations
can execute concurrently. MUL is not replicated because its 2-cycle
latency and large area make a second instance expensive relative to
the conflict frequency.

## Why NAND + Tri-State, Not Simple AND Gate

A plain `assign gclk = clk & en` glitches when `en` changes while
`clk=1`. The NAND + Tri-State cell samples `en` during the LOW phase,
ensuring the control is settled before the rising edge. The tri-state
propagation delay (~0.1 ns) is 3× smaller than an AND gate (~0.35 ns),
reducing effective clock insertion delay on the active path.

## FPGA vs ASIC Implementation Note

On Xilinx 7-series (Kintex-7, Genesys-2):
- Do NOT use combinational clock gating — Vivado flags DRC violation
- Use `BUFGCE` primitive: dedicated gated clock buffer in clock routing
- CE pin on BUFGCE is equivalent to `en` — zero additional clock delay
- All other architecture concepts (decoder, one-hot bus, per-op registers)
  translate directly with no changes

```verilog
// FPGA equivalent of clock_gate_cell
BUFGCE bufgce_inst (
  .I  (clk),
  .CE (en),
  .O  (gclk)
);
```
