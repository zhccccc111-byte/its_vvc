# ITS VVC v5.8 Submission Guide

## Recommended Top

Use `rtl/its_top_500_singleclk.v` for the final 500MHz submission.
See `doc/implementation_status_report.md` for official Q&A compliance mapping.

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

Latest verified results (v5.8):

| Target | Result |
|--------|--------|
| `its_top_500_singleclk` | ALL PASS (1537 + overlap tests) |
| `its_core_500` | 94/94 PASS |
| `its_top` | legacy baseline (1444/1444 with v5.5 RTL) |

## Timing Command

Run from `synth/` with Vivado 2024.1:

```bash
vivado -mode batch -source its_top_500_singleclk_ooc_usp.tcl
```

UltraScale+ OOC result (v5.8) on `xcku5p-ffvb676-2-e`:

| Metric | Value | Status |
|--------|-------|--------|
| WNS | +0.053 ns | MET |
| TNS | 0.000 ns | MET |
| WHS | +0.035 ns | MET |
| Failing endpoints | 0 | MET |
| DSP48E2 | 5 | — |
| RAMB36E2 | 12 | — |
| RAMB18E2 | 5 | — |

## Official Q&A Compliance (v5.6–v5.8)

| Ref | Requirement | Fix |
|-----|-------------|-----|
| P0 #4 | 2D transform: vertical first, then horizontal | v5.6: ref_model + its_core_500 |
| P0 #11 | Next TU accepted before current output fully read | v5.7: TU metadata queue; v5.8: can_accept_tu hardening |

## Notes

- `its_top.v` is frozen as legacy Artix-7 baseline; submission uses `its_top_500_singleclk`.
- `its_top_500_wrapper.v` implements the dual-clock CDC + TU queue architecture.
- v5.8 timing re-verified: WNS +0.053ns at 500MHz, 0 failing endpoints.
