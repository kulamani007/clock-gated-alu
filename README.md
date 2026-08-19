# Clock-Gated 8-bit ALU with Parallel Dispatch Architecture

**Author:** Kulamani Rout  
**Affiliation:** IIIT Bhubaneswar — B.Tech, Electrical and Electronics Engineering  
**Research Collaboration:** University of Tsukuba, Japan

---

## Overview

This project presents a progressive architectural exploration of clock gating in digital ALU design, starting from a standard NAND + Tri-State ICG cell implementation and extending to a novel **dispatch-based parallel execution engine** with per-operation clock isolation.

The work demonstrates that fine-grained, per-operation clock gating — when combined with an operand bus and replicated functional units — enables true parallel execution of multiple operations simultaneously without duplicating the entire ALU, while preserving power savings on all idle units.

---

## Repository Structure

```
clock-gated-alu/
│
├── rtl/
│   ├── clock_gate_cell.v        # NAND + Tri-State ICG cell (standalone)
│   ├── opcode_decoder.v         # 3-to-8 one-hot opcode decoder (standalone)
│   ├── clock_gated_alu.v        # Design 1: Per-operation clock-gated ALU
│   ├── parallel_alu.v           # Design 2: Dispatch-based parallel ALU
│   └── clock_gated_alu_isolated.v  # Design 3: + selective operand isolation
│
├── sim/
│   ├── run_sim.sh               # One-command simulation runner
│   ├── tb_alu_isolated.v        # Testbench for Design 3
│   └── gtkwave_signals.tcl      # GTKWave signal configuration
│
├── syn/
│   └── vivado_synth.tcl         # Vivado synthesis comparison (Kintex-7)
│
├── docs/
│   ├── architecture_notes.md    # Design decisions and tradeoff analysis
│   └── synthesis_results.md     # Measured Vivado + Yosys area comparison
│
├── ppt/
│   └── ClockGated_ALU_Architecture.pptx  # Full architecture slide deck
│
└── README.md
```

---

## Design 1 — Clock-Gated 8-bit ALU (`clock_gated_alu.v`)

### Architecture

```
opcode[2:0]
    │
    ▼
Opcode Decoder (3→8 one-hot)
    │  en[7:0]
    ▼
Clock Gate Array (8× NAND+Tri-State cells)
    │  gclk[7:0]
    ├─ gclk[0] → ADD register   (only clocks on ADD opcode)
    ├─ gclk[1] → SUB register   (only clocks on SUB opcode)
    ├─ gclk[2] → MUL register   (only clocks on MUL opcode)
    ├─ gclk[3] → INC register   (only clocks on INC opcode)
    ├─ gclk[4] → DEC register   (only clocks on DEC opcode)
    ├─ gclk[5] → AND register   (only clocks on AND opcode)
    ├─ gclk[6] → OR  register   (only clocks on OR  opcode)
    └─ gclk[7] → XOR register   (only clocks on XOR opcode)
                      │
                 Output MUX → alu_out[7:0]
```

### Key Design Decision — Per-Operation Register Isolation

Each of the 8 operations has its own dedicated output register, clocked independently by its own `gclk[i]`. When `gclk[i]` is flat-zero:

- The `always @(posedge gclk[i])` block **never triggers**
- The output register **never toggles**
- Dynamic power on that register = **zero**

This is architecturally distinct from a shared result register under an ORed clock, where all arithmetic registers would toggle together during any arithmetic opcode.

### Power Analysis

| Configuration | Avg Power (100 MHz, 1.8V) | Saving vs Ungated |
|---|---|---|
| No clock gating | 23.0 mW | — |
| Group-level gating (arith vs logic) | ~8.5 mW | ~63% |
| **Per-operation gating (this design)** | **3.67 mW** | **~84%** |

Structural floor: minimum **79% saving** regardless of workload, since at minimum 7 out of 8 units are always gated off.

### Modules

| Module | Description |
|---|---|
| `clock_gate_cell` | NAND + Tri-State ICG cell — glitch-free gating |
| `opcode_decoder` | 3-to-8 combinational decoder, produces one-hot `en[7:0]` |
| `clock_gate_array` | 8× ICG cells via generate loop |
| `arith_unit_correct` | 5 separate `always` blocks, each on own `gclk[i]` |
| `logic_unit_correct` | 3 separate `always` blocks, each on own `gclk[i]` |
| `output_mux_correct` | Combinational MUX selecting from 8 independent registers |
| `clock_gated_alu_top` | Top-level integration |
| `tb_clock_gated_alu` | Testbench — 9 operations verified |

---

## Design 2 — Parallel Dispatch ALU (`parallel_alu.v`)

### Motivation

Design 1 is inherently single-issue — the one-hot decoder ensures only one unit receives a live clock per cycle. This is optimal for sequential workloads but leaves parallel execution potential unexplored.

Design 2 extends the architecture to support **two concurrent operations per cycle** through:

1. **Operand bus** — structured 2-slot storage for incoming (A, B, opcode) pairs
2. **Dual decoders** — one per issue slot, each generating a 10-bit enable
3. **Bitwise OR combine** — `en_final = en_0 | en_1` (not addition — carries would corrupt)
4. **Replicated units** — ADD×2, AND×2 for high-demand operations
5. **Dispatch logic** — priority encoder routes each request to a free unit instance

### Why Bitwise OR, Not Addition

```
en_1 = 10'b00_0000_0001  (ADD unit 0)
en_2 = 10'b00_0001_0000  (AND unit 0)

OR:  00_0000_0001 | 00_0001_0000 = 00_0001_0001  ✓ correct
ADD: 00_0000_0001 + 00_0001_0000 = 00_0001_0001  ✓ same here

But with same-bit requests:
en_1 = 10'b00_0000_0001  (ADD unit 0)
en_2 = 10'b00_0000_0001  (ADD unit 0 again)

OR:  0001 | 0001 = 0001  ✓ idempotent — correct
ADD: 0001 + 0001 = 0010  ✗ carry corrupts bit[1], bit[0] lost
```

OR is idempotent — the correct operation for combining independent boolean enable flags.

### Unit Instance Map (10-bit enable bus)

```
Bit   Unit       Opcode    Replicated?
[0]   ADD unit 0  3'b000      YES (×2)
[1]   ADD unit 1  3'b000      YES (×2)
[2]   SUB unit 0  3'b001      No
[3]   MUL unit 0  3'b010      No  (expensive — kept single)
[4]   AND unit 0  3'b011      YES (×2)
[5]   AND unit 1  3'b011      YES (×2)
[6]   OR  unit 0  3'b100      No
[7]   XOR unit 0  3'b101      No
[8]   INC unit 0  3'b110      No
[9]   DEC unit 0  3'b111      No
```

### Concurrent Same-Operation Handling

```
Cycle N: opcode_0 = ADD (A=10, B=20)
         opcode_1 = ADD (A=45, B=30)

Decoder 0 → en_0 = 10'b00_0000_0001  (ADD unit 0 selected)
Decoder 1 → en_1 = 10'b00_0000_0010  (ADD unit 1 selected)
           (decoder 1 sees en_0 already claimed)

en_final = en_0 | en_1 = 10'b00_0000_0011

gclk[0] ticks → ADD unit 0 computes (10+20) = 30
gclk[1] ticks → ADD unit 1 computes (45+30) = 75
gclk[2..9] flat zero → 8 other units: zero dynamic power
```

### Power Saving in Parallel Mode

| Scenario | Active units | Gated off | Power saving vs 2× ALU |
|---|---|---|---|
| Single op | 1 of 10 | 9 of 10 | ~87% |
| 2 different ops | 2 of 10 | 8 of 10 | ~80% |
| 2 same ops (ADD+ADD) | 2 of 10 | 8 of 10 | ~80% |

Conventional superscalar with 2 full ALUs: 46 mW minimum.  
This design with 2 concurrent ops: ~6 mW. **~87% power reduction.**

### Stall Behavior

When all instances of a requested operation are busy, the decoder asserts `stall`. The stall is visible combinationally — no pipeline bubble is inserted in this implementation, making it suitable as a base for integration with a scoreboard or reservation station.

---

## Design 3 — Operand Isolation (`clock_gated_alu_isolated.v`)

### The problem clock gating alone does not solve

Clock gating freezes the **result register** of an idle unit. But the
**combinational logic feeding that register** is still wired directly to
the operand bus:

```
A ──┬──────────────► Adder      (evaluates on every A change)
    ├──────────────► Subtractor (evaluates on every A change)
    ├──────────────► Multiplier (evaluates on every A change)  ← expensive
    └──────────────► AND gate   (evaluates on every A change)
```

Every transition on A or B propagates through **all** combinational trees
regardless of which unit is selected. This is **glitching power** — in a
multiplier's partial-product tree it can be 20–30% of that unit's dynamic
power.

### The fix — AND-gate operand isolation

```verilog
wire [7:0] A_mul = A & {8{en[2]}};   // 8 AND gates
wire [7:0] B_mul = B & {8{en[2]}};
```

When `en[2] = 0` the multiplier sees constant `0 × 0`. The entire
partial-product tree settles to a stable all-zero state — **zero
switching activity** regardless of how fast A and B change.

AND gates rather than MUXes: `A & {8{en}}` gives 8 AND gates versus 8
two-input MUXes for `en ? A : 0` — about half the area, identical
behaviour.

### Selective application

| Unit | Isolated? | Reason |
|---|---|---|
| MUL | Yes | Partial-product tree — deepest logic, biggest win |
| ADD | Yes | 8-level carry chain |
| SUB | Yes | 8-level borrow chain |
| INC / DEC | No | Single ±1 adder, shallow |
| AND / OR / XOR | No | Single gate level — isolation costs more than it saves |

### Measured synthesis results

**Vivado 2023.2, Kintex-7 `xc7k160tffg676-2`:**

| Design | LUT | FF | CARRY4 |
|---|---:|---:|---:|
| Baseline | 129 | 66 | 12 |
| Isolated | 154 | 66 | 12 |
| **Delta** | **+25** | **0** | **0** |

**Yosys 0.33, generic gates:**

| Design | Cells | Gate equivalents |
|---|---:|---:|
| Baseline | 501 | 907 GE |
| Isolated | 530 | 940 GE |
| **Delta** | **+29** | **+33 GE (+3.7%)** |

Flip-flop and carry-chain counts are **identical** in both flows,
confirming isolation is purely combinational and leaves the clock gating
architecture untouched.

Full analysis including the SAIF-based power measurement flow:
[`docs/synthesis_results.md`](docs/synthesis_results.md)

### Verification

```
[Functional Verification]        9/9 operations PASS
[Operand Isolation Verification]
  opcode=ADD, A=FF B=FF
    A_add = ff  (ADD active — operands pass through)
    A_mul = 00  (MUL isolated — tree sees zero)
  opcode=MUL, A=FF B=FF
    A_mul = ff  (MUL active)
    A_add = 00  (ADD carry chain isolated)
[Glitch Suppression Test]
  A toggled AA → FF → 0F while MUL idle
    A_mul stayed 00 throughout — ZERO switching  PASS

RESULTS: 12 passed, 0 failed
```

---

## ICG Cell — Why NAND + Tri-State

A naive `assign gclk = clk & en` fails because if `en` changes while `clk=1`, a spurious short pulse appears on `gclk` — a glitch that causes the downstream register to capture garbage.

The NAND + Tri-State topology prevents this:

```
Timeline:
clk    _____|‾‾‾‾‾|_____|‾‾‾‾‾|_____
en     ______________|‾‾‾‾‾‾‾‾‾‾‾‾‾‾
             ↑ en changes during LOW phase
NAND         settles here — BEFORE rising edge
gclk   _______________|‾‾‾‾‾|________
                        ↑ clean rising edge
                          no glitch
```

The NAND gate output is never on the timing-critical clock path. Only the Tri-State propagation delay (~0.1 ns) sits between the raw clock and `gclk` — significantly less than an AND gate (~0.35–0.45 ns).

---

## Running Simulations

### Requirements

```bash
# Ubuntu / Debian
sudo apt install iverilog gtkwave

# macOS
brew install icarus-verilog gtkwave
```

### Simulate

```bash
cd sim/
chmod +x run_sim.sh
./run_sim.sh
```

### View Waveforms

```bash
# Clock-gated ALU
gtkwave tb_clock_gated_alu.vcd

# Parallel ALU with signal presets
gtkwave tb_parallel_alu.vcd gtkwave_signals.tcl
```

**What to observe in the parallel ALU waveform:**
- `gclk[9:0]` during Test 3 (dual ADD): bits [1:0] both HIGH simultaneously
- All other `gclk` bits flat-zero during each test — zero dynamic power
- `stall_0` goes HIGH when MUL unit is busy and a second MUL arrives

---

## Simulation Results

```
Design 1 — Clock-Gated ALU
  PASS | ADD | A=45  B=30  | got=75   carry=0
  PASS | ADD | A=200 B=100 | got=44   carry=1
  PASS | SUB | A=45  B=30  | got=15   carry=0
  PASS | MUL | A=12  B=11  | got=132  carry=0
  PASS | INC | A=99        | got=100  carry=0
  PASS | DEC | A=100       | got=99   carry=0
  PASS | AND | A=AA  B=0F  | got=0A   carry=0
  PASS | OR  | A=AA  B=55  | got=FF   carry=0
  PASS | XOR | A=FF  B=AA  | got=55   carry=0

Design 2 — Parallel Dispatch ALU
  [TEST 1] ADD(10+20)=30          ✓  gclk=0000000001
  [TEST 2] ADD(45+30)||AND(AA&0F) ✓  gclk=0000010001
  [TEST 3] ADD(10+20)||ADD(45+30) ✓  gclk=0000000011
           ADD0=30, ADD1=75 — no collision
  [TEST 5] SUB(45-30)||XOR(FF^AA) ✓  gclk=0010000100
  [TEST 6] Stall on busy MUL      ✓  stall_0=1
```

---

## Architectural Tradeoffs

| Property | Design 1 (per-op gating) | Design 2 (parallel dispatch) |
|---|---|---|
| Issue width | 1 op/cycle | 2 ops/cycle |
| Result registers | 8 (one per op) | 10 (one per unit instance) |
| Enable bus width | 8-bit | 10-bit |
| Parallel execution | No | Yes |
| Same-op conflict | N/A | Dispatched to separate instances |
| Power saving (single op) | 84% | 84% |
| Power saving (2 parallel) | N/A | ~80% vs 2× full ALU |
| Area vs single ALU | ~1.1× | ~1.4× |
| Area vs 2× full ALU | — | ~60% less |

---

## Scalability

The architecture extends naturally to:

- **CNN layer controller** — CONV, BN, ReLU, POOL, FC each as separately gated units; fused layers use multi-hot enables
- **FPU** — FADD, FMUL, FDIV each with own gclk; FDIV gated off during 98% of typical workloads
- **SPI/UART controllers** — per-state clock gating using FSM state as one-hot enable
- **AXI4-Lite slave** — per-channel gating using handshake signals as enables

---

## References

1. Iraqi Journal of Industrial Research, Vol. 11, No. 1 (2024) — Clock Gating Techniques Using NAND + Tri-State Buffer for 8-bit ALU
2. Rabaey, J., Chandrakasan, A., Nikolic, B. — *Digital Integrated Circuits*, 2nd ed.
3. Xilinx UG949 — *UltraFast Design Methodology Guide* (BUFGCE clock gating on 7-series)

---

## License

MIT License — see [LICENSE](LICENSE)
