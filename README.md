# INT8 Matrix-Multiplication Accelerator

An output-stationary INT8 MAC-array accelerator implemented in SystemVerilog,
computing `C[N x M] = A[N x K] x B[K x M]` — the core operation behind
convolution and fully-connected layers in neural-network inference. Built as
groundwork for NPU/edge-AI accelerator design (weight/output-stationary
array structure, wide-accumulator MAC, INT8 requantization stage).

**Status:** RTL design, fully self-checking simulation (353/353 checks
passing). Not yet synthesized/deployed on an FPGA — see [Roadmap](#roadmap).

## Architecture

```
        B_mem[k][0..3]  (broadcast down columns)
              |   |   |   |
              v   v   v   v
   A_mem[0][k]-> PE  PE  PE  PE   -> C[0][0..3]
   A_mem[1][k]-> PE  PE  PE  PE   -> C[1][0..3]
   A_mem[2][k]-> PE  PE  PE  PE   -> C[2][0..3]
   A_mem[3][k]-> PE  PE  PE  PE   -> C[3][0..3]
        (broadcast across rows)
```

The array is **output-stationary**: each of the N x M Processing Elements
(PEs) is responsible for exactly one output element `C[i][j]` and holds its
own local accumulator for the entire K-cycle reduction. On reduction step
`k`, row `i` is fed `A[i][k]` and column `j` is fed `B[k][j]`; every PE
computes and accumulates `A[i][k] * B[k][j]` in parallel. After K cycles,
every PE holds its final `sum_k A[i][k]*B[k][j]`.

This is the same category of structure used in real systolic/spatial NPU
accelerators (e.g. TPU-style arrays), scaled down (4x4x4 by default,
fully parameterizable) to be easy to simulate, understand, and eventually
map onto FPGA fabric.

### Modules

| File                          | Purpose                                                            |
|--------------------------------|---------------------------------------------------------------------|
| `rtl/mac_unit.sv`              | Single INT8 multiply-accumulate primitive (one per PE)              |
| `rtl/control_fsm.sv`           | Sequences the K-cycle reduction (IDLE / RUN / DONE)                 |
| `rtl/requantize_unit.sv`       | Wide accumulator -> INT8, round-half-up + saturate (NPU output stage)|
| `rtl/int8_matmul_accelerator.sv` | Top level: memories, PE array instantiation, load/read ports      |

### Interface (top level)

- **Load port:** `wr_en`, `wr_target` (0=A, 1=B), `wr_addr` (flat row-major),
  `wr_data` (signed INT8) — write A and B into the accelerator before compute.
- **Control:** `start` (pulse to begin/restart compute), `done` (result valid).
- **Read port:** `rd_en`, `rd_addr` (flat row-major into C) ->
  `rd_data_raw` (full 32-bit accumulator) and `rd_data_q` (INT8, requantized
  using the runtime-programmable `rd_shift`).

Default parameters: `N=K=M=4`, `DATA_WIDTH=8`, `ACC_WIDTH=32`. All are
generic — instantiate with different values for a larger array.

## Design notes / things I'd explain in an interview

- **Why 32-bit accumulator for INT8 inputs?** Worst-case product is
  `127 * 127 ≈ 16129` (~15 bits); summed over any realistic K this stays
  far inside 32 bits, so there's no overflow risk without needing per-layer
  overflow analysis.
- **Why output-stationary, not weight-stationary?** Output-stationary keeps
  the control logic simple for a first design (no operand skewing/staging
  across the array) and each PE's accumulator maps directly and obviously to
  one output element, which made this the right complexity trade-off to
  actually finish and verify. Weight-stationary (loading weights once and
  streaming many activation sets through) is the natural next iteration and
  is the more power-efficient choice for real deployment, since it avoids
  re-reading weights from memory every pass — that's the dataflow-comparison
  extension noted in [Roadmap](#roadmap).
- **Requantization stage:** real INT8 NPU pipelines don't keep 32-bit
  accumulators between layers — they round/shift/saturate back to INT8
  using a scale derived from the input/weight/output quantization
  parameters. `requantize_unit.sv` implements that with a programmable
  shift amount as a stand-in for a real scale factor, including correct
  round-half-up behavior and saturation at the INT8 boundary.

## Verification

`tb/tb_int8_matmul_accelerator.sv` is fully self-checking: it computes an
independent software golden model (plain SystemVerilog integer arithmetic,
also cross-checked against `scripts/golden_model.py` in numpy) and compares
every output element against the DUT.

Coverage:
- 1 directed test (small hand-verifiable values)
- 1 edge-value test (`+127` / `-128` / `0` mixed in every position, to stress
  sign-extension and accumulation correctness)
- 20 randomized trials (uniform random INT8 operands)
- 1 saturation test for the requantization stage

**Result: 353/353 checks passing, 0 errors.**

A note on debugging this: the first version of this testbench drove its
write-port stimulus immediately *after* `@(posedge clk)`, which raced
against the DUT's own `always_ff` sampling on that identical edge (their
relative execution order at the same simulation instant is not guaranteed).
About half of every write was silently dropped as a result. The fix was to
adopt the standard discipline of driving stimulus on `@(negedge clk)` and
letting the DUT sample on the rising edge, guaranteeing a full half-period
of setup margin. Leaving this note here because it's a genuinely easy trap
to fall into and a good thing to be able to explain if asked.

### Running the simulation

With [Icarus Verilog](http://iverilog.icarus.com/) (open source):
```bash
make sim          # compile + run, prints PASS/FAIL summary
make wave         # same, plus dumps wave.vcd for GTKWave
make clean
```

With ModelSim / QuestaSim:
```tcl
vlib work
vlog -sv rtl/mac_unit.sv rtl/requantize_unit.sv rtl/control_fsm.sv rtl/int8_matmul_accelerator.sv tb/tb_int8_matmul_accelerator.sv
vsim -c tb_int8_matmul_accelerator -do "run -all; quit"
```

### Python cross-check
```bash
pip install numpy
python3 scripts/golden_model.py
```

## Roadmap

- [ ] Synthesize and deploy on an FPGA target (Basys3 / DE10-Lite or
      similar) and report real resource utilization (LUTs, FFs, DSP slices)
      and achievable clock frequency.
- [ ] Weight-stationary variant for a direct dataflow comparison
      (latency/throughput/power trade-offs vs. this output-stationary design).
- [ ] Scale up array size and reduction dimension, and benchmark against a
      software INT8 matmul on the same platform.

## Repository structure

```
int8_matmul_accelerator/
├── rtl/
│   ├── mac_unit.sv
│   ├── control_fsm.sv
│   ├── requantize_unit.sv
│   └── int8_matmul_accelerator.sv
├── tb/
│   └── tb_int8_matmul_accelerator.sv
├── scripts/
│   └── golden_model.py
├── Makefile
├── .gitignore
└── README.md
```
