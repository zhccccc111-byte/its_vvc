#!/usr/bin/env python3
"""
Generate protocol-level waveform screenshots for ITS VVC key scenarios.
Pure Python SVG output — no numpy/matplotlib dependency.
"""

from pathlib import Path

PROJECT = Path(r"D:\Workspace\its_vvc")
TV_DIR = PROJECT / "tb" / "test_vectors"
OUT_DIR = PROJECT / "doc" / "waveforms"
OUT_DIR.mkdir(exist_ok=True)

CLK_NS = 2.0
PX_PER_NS = 3.0  # pixels per nanosecond
SIG_HEIGHT = 32   # pixels per signal row
SIG_GAP = 6       # pixels between signals
MARGIN_LEFT = 180
MARGIN_TOP = 60
MARGIN_RIGHT = 40
MARGIN_BOTTOM = 40
BUS_HIGH = 12
BUS_LOW = -12
DIG_HIGH = 14
DIG_LOW = -14


def count_nonzero_entries(hex_file: Path) -> int:
    count = 0
    if not hex_file.exists():
        return 0
    with open(hex_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('//'):
                try:
                    val = int(line, 16)
                    if val != 0:
                        count += 1
                except ValueError:
                    pass
    return count


def count_golden_entries(hex_file: Path) -> int:
    count = 0
    if not hex_file.exists():
        return 0
    with open(hex_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('//'):
                try:
                    int(line, 16)
                    count += 1
                except ValueError:
                    pass
    return count


def t2x(t_ns):
    """Convert time in ns to x pixel."""
    return MARGIN_LEFT + t_ns * PX_PER_NS


def sig_y(row_idx, total_rows):
    """Convert signal row index to y pixel (top=0)."""
    return MARGIN_TOP + row_idx * (SIG_HEIGHT + SIG_GAP) + SIG_HEIGHT // 2


def svg_header(width, height, title):
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}"
     viewBox="0 0 {width} {height}" font-family="Consolas, monospace">
<rect width="{width}" height="{height}" fill="white"/>
<text x="{width//2}" y="30" text-anchor="middle" font-size="16" font-weight="bold" fill="#222">{title}</text>
'''


def svg_footer():
    return '</svg>'


def draw_clk_grid(svg, t_max, n_sigs):
    """Draw clock grid lines and time axis."""
    y_start = MARGIN_TOP - 10
    y_end = MARGIN_TOP + n_sigs * (SIG_HEIGHT + SIG_GAP) + 10
    lines = []
    # Vertical grid lines at each clock edge
    t = 0
    while t <= t_max:
        x = t2x(t)
        opacity = 0.15 if (t / CLK_NS) % 2 == 0 else 0.08
        lines.append(f'<line x1="{x}" y1="{y_start}" x2="{x}" y2="{y_end}" '
                     f'stroke="#888" stroke-width="0.5" opacity="{opacity}"/>')
        # Time label every 5 clocks
        if t % (CLK_NS * 5) == 0:
            lines.append(f'<text x="{x}" y="{y_end + 15}" text-anchor="middle" '
                         f'font-size="9" fill="#666">{int(t)}ns</text>')
        t += CLK_NS
    return '\n'.join(lines) + '\n'


def draw_signal_label(name, row_idx, n_sigs):
    y = sig_y(row_idx, n_sigs)
    return f'<text x="{MARGIN_LEFT - 10}" y="{y + 4}" text-anchor="end" font-size="11" font-weight="bold" fill="#333">{name}</text>\n'


def draw_digital_signal(transitions, row_idx, n_sigs, color='#2563eb', t_max=1000):
    """Draw a 1-bit digital signal."""
    y = sig_y(row_idx, n_sigs)
    paths = []
    fills = []

    if not transitions:
        return ''

    # Ensure signal ends at t_max
    all_pts = list(transitions)
    if all_pts[-1][0] < t_max:
        all_pts.append((t_max, all_pts[-1][1]))

    # Build path
    path_parts = []
    for i, (t, v) in enumerate(all_pts):
        x = t2x(t)
        level = y + DIG_HIGH if v else y + DIG_LOW
        if i == 0:
            path_parts.append(f'M {x} {level}')
        else:
            # Vertical transition
            prev_level = y + DIG_HIGH if all_pts[i-1][1] else y + DIG_LOW
            path_parts.append(f'L {x} {prev_level}')
            path_parts.append(f'L {x} {level}')

    paths.append(f'<path d="{" ".join(path_parts)}" fill="none" stroke="{color}" stroke-width="2"/>')

    # Fill high regions
    for i in range(len(all_pts) - 1):
        if all_pts[i][1]:
            x0 = t2x(all_pts[i][0])
            x1 = t2x(all_pts[i + 1][0])
            fills.append(f'<rect x="{x0}" y="{y + DIG_LOW}" width="{x1 - x0}" '
                         f'height="{DIG_HIGH - DIG_LOW}" fill="{color}" opacity="0.1"/>')

    return '\n'.join(fills + paths) + '\n'


def draw_bus_signal(transitions, row_idx, n_sigs, color='#059669', t_max=1000):
    """Draw a multi-bit bus signal with value labels."""
    y = sig_y(row_idx, n_sigs)
    parts = []

    if not transitions:
        return ''

    all_pts = list(transitions)
    if all_pts[-1][0] < t_max:
        all_pts.append((t_max, all_pts[-1][1]))

    for i in range(len(all_pts) - 1):
        t0 = all_pts[i][0]
        t1 = all_pts[i + 1][0]
        val = all_pts[i][1]
        x0 = t2x(t0)
        x1 = t2x(t1)
        w = x1 - x0

        # Bus rectangle with cross-hatch
        parts.append(f'<rect x="{x0}" y="{y + BUS_LOW}" width="{w}" '
                     f'height="{BUS_HIGH - BUS_LOW}" fill="{color}" opacity="0.2" rx="2"/>')
        parts.append(f'<rect x="{x0}" y="{y + BUS_LOW}" width="{w}" '
                     f'height="{BUS_HIGH - BUS_LOW}" fill="none" stroke="{color}" stroke-width="1"/>')

        # Value label
        if w > 25 and val is not None:
            mid = x0 + w / 2
            label = str(val) if isinstance(val, int) else str(val)
            parts.append(f'<text x="{mid}" y="{y + 4}" text-anchor="middle" '
                         f'font-size="9" font-weight="bold" fill="{color}">{label}</text>')

    # Transition lines
    for i in range(1, len(all_pts)):
        x = t2x(all_pts[i][0])
        prev_v = all_pts[i-1][1]
        curr_v = all_pts[i][1]
        if prev_v != curr_v:
            y0 = y + (BUS_HIGH if prev_v else BUS_LOW)
            y1 = y + (BUS_HIGH if curr_v else BUS_LOW)
            parts.append(f'<line x1="{x}" y1="{y0}" x2="{x}" y2="{y1}" '
                         f'stroke="{color}" stroke-width="1.5"/>')

    return '\n'.join(parts) + '\n'


def draw_highlight(t_start, t_end, row_idx, n_sigs, color='yellow'):
    """Draw a highlight region for a signal row."""
    y = sig_y(row_idx, n_sigs)
    x0 = t2x(t_start)
    x1 = t2x(t_end)
    return f'<rect x="{x0}" y="{y - SIG_HEIGHT//2}" width="{x1 - x0}" height="{SIG_HEIGHT}" fill="{color}" opacity="0.2"/>\n'


def draw_notes(notes, width, height):
    """Draw notes text at bottom."""
    lines = notes.split('\n')
    parts = []
    y = height - MARGIN_BOTTOM + 5
    for line in lines:
        parts.append(f'<text x="{MARGIN_LEFT}" y="{y}" font-size="10" fill="#555">{line}</text>')
        y += 14
    return '\n'.join(parts) + '\n'


def generate_waveform(title, notes, signals, t_max_ns, output_path):
    """Generate an SVG waveform file.
    signals: list of dicts with keys: name, type ('digital'|'bus'), transitions, color, highlights
    transitions: list of (time_ns, value)
    highlights: list of (t_start, t_end, color)
    """
    n_sigs = len(signals)
    width = MARGIN_LEFT + t_max_ns * PX_PER_NS + MARGIN_RIGHT
    height = MARGIN_TOP + n_sigs * (SIG_HEIGHT + SIG_GAP) + MARGIN_BOTTOM + 30

    svg = svg_header(width, height, title)
    svg += draw_clk_grid(svg, t_max_ns, n_sigs)

    for i, sig in enumerate(signals):
        name = sig['name']
        sig_type = sig.get('type', 'digital')
        transitions = sig.get('transitions', [])
        color = sig.get('color', '#2563eb')
        highlights = sig.get('highlights', [])

        svg += draw_signal_label(name, i, n_sigs)

        for hl in highlights:
            svg += draw_highlight(hl[0], hl[1], i, n_sigs, hl[2])

        if sig_type == 'bus':
            svg += draw_bus_signal(transitions, i, n_sigs, color, t_max_ns)
        else:
            svg += draw_digital_signal(transitions, i, n_sigs, color, t_max_ns)

    svg += draw_notes(notes, width, height)
    svg += svg_footer()

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(svg)
    print(f"  Saved: {output_path.name}")


# ============================================================
# Scenario generators
# ============================================================

def gen_dct2_4x4():
    input_count = count_nonzero_entries(TV_DIR / "dct2_4x4_input.hex")
    output_count = count_golden_entries(TV_DIR / "dct2_4x4_golden.hex")
    ob = (output_count + 3) // 4

    t_info, t_in_s, t_in_e = 10, 30, 30 + input_count * 4
    t_end_a = t_in_e + 10
    t_clr = t_end_a + 100
    t_row = t_clr + 50
    t_col = t_row + 200
    t_out_s = t_col + 100
    t_out_e = t_out_s + ob * 6
    t_done = t_out_e + 20
    t_max = t_done + 50

    # Input pulses
    in_pulses = [(0, 0)]
    for i in range(input_count):
        t = t_in_s + i * 4
        in_pulses.extend([(t, 1), (t + 2, 0)])

    # Output pulses
    out_pulses = [(0, 0)]
    for i in range(ob):
        t = t_out_s + i * 6
        out_pulses.extend([(t, 1), (t + 4, 1), (t + 6, 0)])

    signals = [
        {'name': 'it_info_vld', 'transitions': [(0, 0), (t_info, 1), (t_info + 2, 0)], 'color': '#16a34a'},
        {'name': 'it_data_in_vld', 'transitions': in_pulses, 'color': '#2563eb'},
        {'name': 'it_data_end', 'transitions': [(0, 0), (t_end_a, 1), (t_end_a + 2, 0)], 'color': '#dc2626'},
        {'name': 'it_data_in_req', 'transitions': [(0, 1)], 'color': '#0891b2'},
        {'name': 'it_data_out_vld', 'transitions': [(0, 0), (t_out_s, 1), (t_out_e, 1), (t_out_e + 2, 0)], 'color': '#ea580c'},
        {'name': 'it_data_out_req', 'transitions': [(0, 1)], 'color': '#7c3aed'},
        {'name': 'it_done', 'transitions': [(0, 0), (t_done, 1), (t_done + 2, 0)], 'color': '#dc2626'},
        {'name': 'state', 'type': 'bus', 'transitions': [
            (0, 'IDLE'), (t_info + 4, 'CLR'), (t_clr, 'LOAD'), (t_row, 'ROW'),
            (t_col, 'COL'), (t_out_s, 'OUT'), (t_done - 2, 'DONE'), (t_done + 10, 'IDLE')
        ], 'color': '#065f46'},
    ]

    generate_waveform(
        f'DCT2 4x4 — Basic Transform Flow ({input_count} in, {output_count} out)',
        'State: IDLE→CLEAR(9)→LOAD(1)→ROW(2)→COL(3)→OUT(4)→DONE(7) | 4 MAC parallel | Output: 4 vals/cycle',
        signals, t_max, OUT_DIR / "wave_dct2_4x4.svg")


def gen_lfnst():
    input_count = count_nonzero_entries(TV_DIR / "lfnst16_s0_i1_input.hex")
    output_count = count_golden_entries(TV_DIR / "lfnst16_s0_i1_golden.hex")

    t_info, t_in_s, t_in_e = 10, 30, 30 + input_count * 4
    t_end_a = t_in_e + 10
    t_lfnst_s = t_end_a + 80
    t_lfnst_e = t_lfnst_s + 100
    t_row = t_lfnst_e + 30
    t_col = t_row + 200
    t_out_s = t_col + 100
    t_out_e = t_out_s + ((output_count + 3) // 4) * 6
    t_done = t_out_e + 20
    t_max = t_done + 50

    signals = [
        {'name': 'it_info_vld', 'transitions': [(0, 0), (t_info, 1), (t_info + 2, 0)], 'color': '#16a34a'},
        {'name': 'it_data_in_vld', 'transitions': [(0, 0), (t_in_s, 1), (t_in_e, 1), (t_in_e + 2, 0)], 'color': '#2563eb'},
        {'name': 'it_data_end', 'transitions': [(0, 0), (t_end_a, 1), (t_end_a + 2, 0)], 'color': '#dc2626'},
        {'name': 'it_data_out_vld', 'transitions': [(0, 0), (t_out_s, 1), (t_out_e, 1), (t_out_e + 2, 0)], 'color': '#ea580c'},
        {'name': 'it_done', 'transitions': [(0, 0), (t_done, 1), (t_done + 2, 0)], 'color': '#dc2626'},
        {'name': 'state', 'type': 'bus', 'transitions': [
            (0, 'IDLE'), (t_info + 4, 'CLR'), (t_lfnst_s - 20, 'LOAD'),
            (t_lfnst_s, 'LFN_L'), (t_lfnst_e, 'LFN_P'),
            (t_row, 'ROW'), (t_col, 'COL'), (t_out_s, 'OUT'),
            (t_done - 2, 'DONE'), (t_done + 10, 'IDLE')
        ], 'color': '#065f46'},
    ]

    generate_waveform(
        'LFNST 4x4 (nTrs=16) — DCT2 + LFNST Post-Processing',
        'State: ...LOAD→LFNST_LOAD(5)→LFNST_PROC(6)→ROW→COL→OUT→DONE | LFNST: secondary 16x16 matrix on top-left 4x4',
        signals, t_max, OUT_DIR / "wave_lfnst.svg")


def gen_end_same_cycle():
    input_count = count_nonzero_entries(TV_DIR / "end_same_dct2_4x4_input.hex")
    output_count = count_golden_entries(TV_DIR / "end_same_dct2_4x4_golden.hex")

    t_info, t_in_s = 10, 30
    t_last = t_in_s + (input_count - 1) * 4
    t_out_s = t_last + 250
    t_out_e = t_out_s + ((output_count + 3) // 4) * 6
    t_done = t_out_e + 20
    t_max = t_done + 50

    in_pulses = [(0, 0)]
    for i in range(input_count):
        t = t_in_s + i * 4
        in_pulses.extend([(t, 1), (t + 2, 0)])

    signals = [
        {'name': 'it_info_vld', 'transitions': [(0, 0), (t_info, 1), (t_info + 2, 0)], 'color': '#16a34a'},
        {'name': 'it_data_in_vld', 'transitions': in_pulses, 'color': '#2563eb'},
        {'name': 'it_data_end', 'transitions': [(0, 0), (t_last, 1), (t_last + 2, 0)], 'color': '#dc2626',
         'highlights': [(t_last - 2, t_last + 4, '#dc2626')]},
        {'name': 'it_data_out_vld', 'transitions': [(0, 0), (t_out_s, 1), (t_out_e, 1), (t_out_e + 2, 0)], 'color': '#ea580c'},
        {'name': 'it_done', 'transitions': [(0, 0), (t_done, 1), (t_done + 2, 0)], 'color': '#dc2626'},
    ]

    generate_waveform(
        'it_data_end Same Cycle as Last Input (DCT2 4x4)',
        'Spec: it_data_end asserts on SAME clock edge as last it_data_in_vld (highlighted in red)',
        signals, t_max, OUT_DIR / "wave_end_same_cycle.svg")


def gen_backpressure():
    output_count = count_golden_entries(TV_DIR / "dct2_4x4_golden.hex")
    ob = (output_count + 3) // 4

    t_info = 10
    t_end_a = 100
    t_out_s = 300

    # Build req pattern: alternating high/low
    req_transitions = [(0, 1)]
    vld_transitions = [(0, 0), (t_out_s, 1)]
    bp_highlights = []
    t = t_out_s
    for i in range(ob):
        # Data available period
        t += 6
        if i % 3 == 2 and i < ob - 1:
            # Backpressure: req=0 for 10ns
            req_transitions.extend([(t, 0), (t + 10, 0)])
            bp_highlights.append((t, t + 10, '#eab308'))
            t += 10
            req_transitions.append((t, 1))

    t_out_e = t
    vld_transitions.extend([(t_out_e, 1), (t_out_e + 2, 0)])
    t_done = t_out_e + 30
    t_max = t_done + 50

    signals = [
        {'name': 'it_info_vld', 'transitions': [(0, 0), (t_info, 1), (t_info + 2, 0)], 'color': '#16a34a'},
        {'name': 'it_data_end', 'transitions': [(0, 0), (t_end_a, 1), (t_end_a + 2, 0)], 'color': '#dc2626'},
        {'name': 'it_data_out_vld', 'transitions': vld_transitions, 'color': '#ea580c'},
        {'name': 'it_data_out_req', 'transitions': req_transitions, 'color': '#7c3aed',
         'highlights': bp_highlights},
        {'name': 'it_done', 'transitions': [(0, 0), (t_done, 1), (t_done + 2, 0)], 'color': '#dc2626'},
    ]

    generate_waveform(
        'Output Backpressure — req Toggle Pattern',
        'Yellow highlights: backpressure periods (req=0). Protocol: vld=0 when req=0; data resumes after req=1',
        signals, t_max, OUT_DIR / "wave_backpressure.svg")


def gen_continuous_tu():
    input_count = count_nonzero_entries(TV_DIR / "dct2_4x4_input.hex")
    output_count = count_golden_entries(TV_DIR / "dct2_4x4_golden.hex")
    ob = (output_count + 3) // 4

    # TU1
    t_info1, t_in1_s, t_in1_e = 10, 30, 30 + input_count * 4
    t_end1 = t_in1_e + 10
    t_out1_s, t_out1_e = 300, 300 + ob * 6
    t_done1 = t_out1_e + 20

    # TU2 starts right after
    t_info2 = t_done1 + 20
    t_in2_s = t_info2 + 20
    t_in2_e = t_in2_s + input_count * 4
    t_end2 = t_in2_e + 10
    t_out2_s = t_done1 + 400
    t_out2_e = t_out2_s + ob * 6
    t_done2 = t_out2_e + 20
    t_max = t_done2 + 50

    signals = [
        {'name': 'it_info_vld', 'transitions': [(0, 0), (t_info1, 1), (t_info1 + 2, 0),
                                                  (t_info2, 1), (t_info2 + 2, 0)], 'color': '#16a34a'},
        {'name': 'it_data_end', 'transitions': [(0, 0), (t_end1, 1), (t_end1 + 2, 0),
                                                  (t_end2, 1), (t_end2 + 2, 0)], 'color': '#dc2626'},
        {'name': 'it_data_out_vld', 'transitions': [(0, 0), (t_out1_s, 1), (t_out1_e, 1), (t_out1_e + 2, 0),
                                                      (t_out2_s, 1), (t_out2_e, 1), (t_out2_e + 2, 0)], 'color': '#ea580c'},
        {'name': 'it_done', 'transitions': [(0, 0), (t_done1, 1), (t_done1 + 2, 0),
                                              (t_done2, 1), (t_done2 + 2, 0)], 'color': '#dc2626'},
    ]

    generate_waveform(
        'Continuous TU — Back-to-Back DCT2 4x4',
        'Two TUs without idle gap. Second it_info_vld arrives right after first it_done.',
        signals, t_max, OUT_DIR / "wave_continuous_tu.svg")


def gen_boundary_zero():
    output_count = count_golden_entries(TV_DIR / "boundary_zero_4x4_golden.hex")

    t_info = 10
    t_end_a = 70
    t_clr = 150
    t_out_s = 300
    t_out_e = t_out_s + ((output_count + 3) // 4) * 6
    t_done = t_out_e + 20
    t_max = t_done + 50

    signals = [
        {'name': 'it_info_vld', 'transitions': [(0, 0), (t_info, 1), (t_info + 2, 0)], 'color': '#16a34a'},
        {'name': 'it_data_in_vld', 'transitions': [(0, 0)], 'color': '#2563eb'},
        {'name': 'it_data_end', 'transitions': [(0, 0), (t_end_a, 1), (t_end_a + 2, 0)], 'color': '#dc2626'},
        {'name': 'it_data_out_vld', 'transitions': [(0, 0), (t_out_s, 1), (t_out_e, 1), (t_out_e + 2, 0)], 'color': '#ea580c'},
        {'name': 'it_done', 'transitions': [(0, 0), (t_done, 1), (t_done + 2, 0)], 'color': '#dc2626'},
        {'name': 'state', 'type': 'bus', 'transitions': [
            (0, 'IDLE'), (t_info + 4, 'CLR'), (t_clr, 'LOAD'),
            (t_out_s - 20, 'OUT'), (t_done - 2, 'DONE'), (t_done + 10, 'IDLE')
        ], 'color': '#065f46'},
    ]

    generate_waveform(
        'Boundary: All-Zero 4x4 Input',
        'No input data sent. in_mem zeroed by S_CLEAR. Output: all zeros (DC only).',
        signals, t_max, OUT_DIR / "wave_boundary_zero.svg")


def main():
    print("Generating waveform screenshots (SVG)...")
    gen_dct2_4x4()
    gen_lfnst()
    gen_end_same_cycle()
    gen_backpressure()
    gen_continuous_tu()
    gen_boundary_zero()
    print(f"\nAll waveforms saved to {OUT_DIR}")


if __name__ == "__main__":
    main()
