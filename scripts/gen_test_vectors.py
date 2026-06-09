"""
Generate test vectors for ALL competition-required combinations.
Covers: DCT2 (25 sizes), DCT8 (16 sizes), DST7 (16 sizes),
        LFNST nTrs=16 (8 scenarios), LFNST nTrs=48 (8 scenarios)
Total: 73 test cases
"""

import os
import sys
import random

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ref_model import its_inverse_transform, flatten_raster, _load_lfnst_matrices


def to_hex(val, bits):
    if val < 0:
        val = val + (1 << bits)
    return format(val & ((1 << bits) - 1), f'0{bits // 4}X')


def generate_test_case(tv_dir, width, height, tr_hor, tr_ver, set_idx, lfnst, desc, input_data):
    output = its_inverse_transform(input_data, width, height, tr_hor, tr_ver, set_idx, lfnst)
    flat_out = flatten_raster(output)
    flat_in = flatten_raster(input_data)

    input_path = os.path.join(tv_dir, f"{desc}_input.hex")
    with open(input_path, 'w') as f:
        for idx, val in enumerate(flat_in):
            if val != 0:
                combined = (idx << 16) | (val & 0xFFFF)
                f.write(f"{combined:07X}\n")

    golden_path = os.path.join(tv_dir, f"{desc}_golden.hex")
    with open(golden_path, 'w') as f:
        for val in flat_out:
            f.write(f"{to_hex(val, 10)}\n")

    return len([v for v in flat_in if v != 0]), len(flat_out)


def make_sparse_input(width, height, max_nonzero=8):
    data = [[0] * width for _ in range(height)]
    num = random.randint(1, min(max_nonzero, width * height))
    for _ in range(num):
        r = random.randint(0, height - 1)
        c = random.randint(0, width - 1)
        data[r][c] = random.randint(-100, 100)
    return data


def main():
    random.seed(42)
    tv_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tb', 'test_vectors')
    os.makedirs(tv_dir, exist_ok=True)
    _load_lfnst_matrices()

    test_cases = []

    # === DCT2: 25 block sizes ===
    dct2_sizes = [
        (4,4),(4,8),(4,16),(4,32),(4,64),
        (8,4),(16,4),(32,4),(64,4),
        (8,8),(8,16),(8,32),(8,64),
        (16,8),(32,8),(64,8),
        (16,16),(16,32),(16,64),
        (32,16),(32,32),(32,64),
        (64,16),(64,32),(64,64),
    ]
    for w, h in dct2_sizes:
        desc = f"dct2_{w}x{h}"
        test_cases.append((w, h, 0, 0, 0, 0, desc))

    # === DCT8: 16 block sizes ===
    dct8_sizes = [
        (4,4),(4,8),(4,16),(4,32),
        (8,4),(16,4),(32,4),
        (8,8),(8,16),(8,32),
        (16,8),(32,8),
        (16,16),(16,32),(32,16),(32,32),
    ]
    for w, h in dct8_sizes:
        desc = f"dct8_{w}x{h}"
        test_cases.append((w, h, 1, 1, 0, 0, desc))

    # === DST7: 16 block sizes ===
    dst7_sizes = dct8_sizes  # same size set
    for w, h in dst7_sizes:
        desc = f"dst7_{w}x{h}"
        test_cases.append((w, h, 2, 2, 0, 0, desc))

    # === LFNST nTrs=16: 4 setIdx x 2 idx = 8 scenarios (use 4x4) ===
    for sidx in range(4):
        for lfnst_idx in [1, 2]:
            desc = f"lfnst16_s{sidx}_i{lfnst_idx}"
            test_cases.append((4, 4, 0, 0, sidx, lfnst_idx, desc))

    # === LFNST nTrs=48: 4 setIdx x 2 idx = 8 scenarios (use 8x8) ===
    for sidx in range(4):
        for lfnst_idx in [1, 2]:
            desc = f"lfnst48_s{sidx}_i{lfnst_idx}"
            test_cases.append((8, 8, 0, 0, sidx, lfnst_idx, desc))

    # === Additional LFNST nTrs=48 with different block sizes ===
    lfnst48_extra = [(8,16),(16,8),(16,16),(16,32),(32,16),(32,32)]
    for w, h in lfnst48_extra:
        desc = f"dct2_{w}x{h}_lfnst1"
        test_cases.append((w, h, 0, 0, 0, 1, desc))

    # === Non-square LFNST combinations ===
    lfnst_nonsquare = [(4,64),(64,4),(8,64),(64,8)]
    for w, h in lfnst_nonsquare:
        desc = f"dct2_{w}x{h}_lfnst1"
        test_cases.append((w, h, 0, 0, 0, 1, desc))

    print(f"Generating {len(test_cases)} test cases...")

    config_lines = []
    for w, h, tr_h, tr_v, sidx, lfnst, desc in test_cases:
        # Limit non-zero points for large blocks to keep simulation time reasonable
        max_nz = 8 if w * h <= 256 else 4
        data = make_sparse_input(w, h, max_nz)
        n_in, n_out = generate_test_case(tv_dir, w, h, tr_h, tr_v, sidx, lfnst, desc, data)
        print(f"  {desc}: {n_in} in -> {n_out} out")
        config_lines.append(f"{desc}")

    # === Boundary input tests ===
    # All-zero input
    zero_data = [[0]*4 for _ in range(4)]
    n_in, n_out = generate_test_case(tv_dir, 4, 4, 0, 0, 0, 0, "boundary_zero_4x4", zero_data)
    print(f"  boundary_zero_4x4: {n_in} in -> {n_out} out")

    # Single DC coefficient
    dc_data = [[0]*4 for _ in range(4)]
    dc_data[0][0] = 64
    n_in, n_out = generate_test_case(tv_dir, 4, 4, 0, 0, 0, 0, "boundary_dc_4x4", dc_data)
    print(f"  boundary_dc_4x4: {n_in} in -> {n_out} out")

    # Max positive value (32767)
    max_data = [[0]*4 for _ in range(4)]
    max_data[0][0] = 32767
    max_data[0][1] = 32767
    max_data[1][0] = 32767
    n_in, n_out = generate_test_case(tv_dir, 4, 4, 0, 0, 0, 0, "boundary_maxval_4x4", max_data)
    print(f"  boundary_maxval_4x4: {n_in} in -> {n_out} out")

    # Min negative value (-32768)
    min_data = [[0]*4 for _ in range(4)]
    min_data[0][0] = -32768
    min_data[0][1] = -32768
    min_data[1][0] = -32768
    n_in, n_out = generate_test_case(tv_dir, 4, 4, 0, 0, 0, 0, "boundary_minval_4x4", min_data)
    print(f"  boundary_minval_4x4: {n_in} in -> {n_out} out")

    # Sparse random with more non-zero points (16 out of 64 for 8x8)
    random.seed(123)
    sparse_data = [[0]*8 for _ in range(8)]
    for _ in range(16):
        r = random.randint(0, 7)
        c = random.randint(0, 7)
        sparse_data[r][c] = random.randint(-200, 200)
    n_in, n_out = generate_test_case(tv_dir, 8, 8, 0, 0, 0, 0, "boundary_sparse_8x8", sparse_data)
    print(f"  boundary_sparse_8x8: {n_in} in -> {n_out} out")

    # Write config file listing all test case names
    config_path = os.path.join(tv_dir, "test_config.txt")
    with open(config_path, 'w') as f:
        for line in config_lines:
            f.write(line + "\n")

    print(f"\nGenerated {len(test_cases)} test cases in {tv_dir}")
    print("Done!")


if __name__ == "__main__":
    main()
