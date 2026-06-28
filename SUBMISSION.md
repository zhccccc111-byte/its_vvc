# ITS VVC v5.5 Submission Guide

## Recommended Top

Use `rtl/its_top_500_singleclk.v` for the final 500MHz submission.

This module has the same single-clock competition interface as `its_top.v`:

```verilog
module its_top_500_singleclk (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [21:0] it_info,
    input  wire        it_info_vld,
    input  wire [15:0] it_data_in,
    input  wire [11:0] it_data_addr,
    input  wire        it_data_in_vld,
    input  wire        it_data_end,
    output wire        it_data_in_req,
    output wire [39:0] it_data_out,
    output wire        it_data_out_vld,
    input  wire        it_data_out_req,
    output wire        it_done
);
```

Internally it reuses the verified 500MHz wrapper/core architecture and ties `clk_if` and `clk_core` to the same 500MHz `clk`.

## Verification Commands

Run from `sim/`:

```bash
# Original single-clock baseline top
vsim -c -do "do run.do"

# Final 500MHz single-clock submission top
vsim -c -do "do run_500_singleclk.do"

# Dual-clock CDC wrapper
vsim -c -do "do run_500.do"

# FIFO-interface 500MHz compute core
vsim -c -do "do run_core_500.do"
```

Latest verified results:

| Target | Result |
|--------|--------|
| `its_top` | 1444/1444 PASS |
| `its_top_500_singleclk` | 1537/1537 PASS |
| `its_top_500_wrapper` | 1537/1537 PASS |
| `its_core_500` | 94/94 PASS |

## Timing Command

Run from `synth/` with Vivado 2024.1:

```bash
vivado -mode batch -source its_top_500_singleclk_ooc_usp.tcl
```

UltraScale+ OOC result on `xcku5p-ffvb676-2-e`:

| Metric | Value | Status |
|--------|-------|--------|
| WNS | +0.057 ns | MET |
| TNS | 0.000 ns | MET |
| WHS | +0.038 ns | MET |
| Failing endpoints | 0 | MET |
| DSP48E2 | 5 | — |
| RAMB36E2 | 12 | — |
| RAMB18E2 | 5 | — |

## Notes

- `its_top.v` remains as the original Artix-7/single-clock functional baseline.
- `its_top_500_wrapper.v` remains useful for explicit dual-clock CDC integration.
- `its_top_500_singleclk.v` is the recommended final submission top when the evaluator requires a single `clk` port.
- Artix-7 500MHz remains infeasible for this architecture because the DSP48E1/BRAM primitive timing is the limiting factor; UltraScale+ meets the 500MHz requirement.
