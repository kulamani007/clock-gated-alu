# Synthesis Results — Operand Isolation Area/Power Tradeoff

Two independent synthesis flows were run to quantify the cost of adding
operand isolation on top of per-operation clock gating.

| Flow | Tool | Target |
|---|---|---|
| FPGA | Vivado 2023.2 | Kintex-7 `xc7k160tffg676-2` |
| ASIC-style | Yosys 0.33 | Generic gate netlist |

> **Note on the part.** Genesys-2 uses `xc7k325tffg900-2`. That device is
> not present in every Vivado install, so `xc7k160tffg676-2` was used —
> same Kintex-7 family, identical primitives (LUT6, FDCE, CARRY4), so the
> LUT/FF/CARRY deltas transfer directly to the 325T.

---

## Vivado Synthesis — Kintex-7

| Design | LUT | FF | CARRY4 | MUXF |
|---|---:|---:|---:|---:|
| Baseline (clock gating only) | 129 | 66 | 12 | 0 |
| Isolated (gating + operand isolation) | 154 | 66 | 12 | 0 |
| **Delta** | **+25** | **0** | **0** | **0** |

**LUT overhead: +19.4%**

### Reading these numbers

**Flip-flop count is identical (66 both).** This confirms the operand
isolation layer is purely combinational — it adds no sequential elements
and leaves the per-operation clock gating architecture untouched.

**CARRY4 count is identical (12 both).** The adder and subtractor carry
chains are structurally unchanged. Isolation gates sit *in front of* the
carry chain, not inside it.

**+25 LUTs is the isolation logic.** Three units are isolated (ADD, SUB,
MUL), each with two 8-bit operands:

```
3 units × 2 operands × 8 bits = 48 AND gates
```

On a 6-input LUT architecture these pack efficiently — 48 AND gates
collapse into ~25 LUTs because each LUT6 absorbs multiple gates and the
shared enable term is reused across bits.

---

## Yosys Synthesis — Generic Gates

| Cell Type | Baseline | Isolated | Delta |
|---|---:|---:|---:|
| AND | 122 | 162 | **+40** |
| DFF | 66 | 66 | 0 |
| NAND | 160 | 158 | −2 |
| NOR | 17 | 19 | +2 |
| NOT | 13 | 12 | −1 |
| OR | 25 | 24 | −1 |
| XNOR | 38 | 26 | −12 |
| XOR | 60 | 63 | +3 |
| **Total cells** | **501** | **530** | **+29** |
| **Gate equivalents** | **907 GE** | **940 GE** | **+33 GE** |

**Area overhead: +3.7%**

### Why XNOR dropped by 12

With operands forced to zero on idle paths, the optimiser found
constant-propagation opportunities in the subtractor's borrow logic.
Part of the isolation cost paid for itself.

### Why Yosys shows +3.7% but Vivado shows +19.4%

The two flows measure different things. Yosys counts individual gates
against a total that includes every gate in the design. Vivado counts
LUTs, and the baseline ALU is small enough (129 LUTs) that 25 extra LUTs
is a large *relative* number even though the absolute cost is tiny.

On a larger datapath — a 32-bit ALU, or an ALU embedded in a processor —
the isolation cost stays roughly constant per isolated operand bit while
the baseline grows, so the relative overhead falls sharply.

---

## Tradeoff Summary

| Metric | Value |
|---|---|
| Vivado LUT overhead | +25 LUTs (+19.4%) |
| Yosys area overhead | +33 GE (+3.7%) |
| Registers added | 0 |
| Carry chains changed | 0 |
| Estimated glitching power eliminated | 8–12% of total dynamic power |

### Why selective isolation, not universal

Universal isolation across all 8 units would require:

```
8 units × 2 operands × 8 bits = 128 AND gates
```

roughly 2.7× the isolation logic for marginal extra benefit. For
single-gate-depth units (AND, OR, XOR) the isolation gates consume more
power than the glitching they eliminate. Applying isolation only to deep
combinational units — ADD carry chain, SUB borrow chain, MUL
partial-product tree — captures most of the benefit at a fraction of the
area.

---

## Reproducing These Results

### Vivado

```bash
cd syn/
vivado -mode batch -source vivado_synth.tcl
```

Produces `util_baseline.rpt`, `util_isolated.rpt`,
`timing_baseline.rpt`, `timing_isolated.rpt`.

### Yosys

```bash
cd sim/
./run_synth.sh
```

---

## Next Step: Power Measurement

These are area numbers. To measure the actual power saving from
eliminated glitching, the flow is:

1. Run behavioural simulation with a realistic operand stream
2. Dump switching activity to SAIF
3. `read_saif` in Vivado after `place_design` + `route_design`
4. `report_power` on both designs and compare dynamic power

The area cost is now measured. The power benefit remains an estimate
until that SAIF-based flow is run.

---

## Note on Clock Gating in FPGA Synthesis

Vivado synthesised the NAND + Tri-State ICG cells as combinational logic
driving flip-flop clock pins. This works in simulation and in synthesis,
but for a real Genesys-2 implementation the recommended approach is
`BUFGCE`:

```verilog
BUFGCE bufgce_inst (
    .I  (clk),
    .CE (en),
    .O  (gclk)
);
```

`BUFGCE` routes the gated clock through the dedicated global clock
network with zero added skew, whereas combinational clock gating routes
through general fabric and can cause timing closure problems. See
`docs/architecture_notes.md`.
