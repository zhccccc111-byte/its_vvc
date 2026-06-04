"""
Generate VVC ITS ROM coefficients for all transform types and sizes.
Outputs: rom_coeffs.hex (for $readmemh) and lfnst_coeffs.hex

Transform formulas (VVC standard, 64x scaling):
  DCT2: T(i,j) = 64 (i=0), round(89 * cos(pi*i*(2j+1)/(2N))) (i>0)
  DCT8: T(i,j) = round(64 * cos(pi*(2i+1)*(2j+1)/(4N)))
  DST7: T(i,j) = round(64 * sin(pi*(i+1)*(j+1)/(N+1)))

Address mapping:
  addr = base_addr(tr_type, size) + row * size + col

  DCT2 (tr_type=0): sizes 4,8,16,32,64
  DCT8 (tr_type=1): sizes 4,8,16,32
  DST7 (tr_type=2): sizes 4,8,16,32
"""

import math
from typing import List, Tuple, Dict

# ============================================================
# Matrix generation
# ============================================================

def gen_dct2(N: int) -> List[List[int]]:
    """Generate N-point DCT2 matrix."""
    T = [[0] * N for _ in range(N)]
    for i in range(N):
        for j in range(N):
            if i == 0:
                T[i][j] = 64
            else:
                angle = math.pi * i * (2 * j + 1) / (2 * N)
                T[i][j] = round(89 * math.cos(angle))
    return T


def gen_dct8(N: int) -> List[List[int]]:
    """Generate N-point DCT8 matrix."""
    T = [[0] * N for _ in range(N)]
    for i in range(N):
        for j in range(N):
            angle = math.pi * (2 * i + 1) * (2 * j + 1) / (4 * N)
            T[i][j] = round(64 * math.cos(angle))
    return T


def gen_dst7(N: int) -> List[List[int]]:
    """Generate N-point DST7 matrix."""
    T = [[0] * N for _ in range(N)]
    for i in range(N):
        for j in range(N):
            angle = math.pi * (i + 1) * (j + 1) / (N + 1)
            T[i][j] = round(64 * math.sin(angle))
    return T


# ============================================================
# LFNST matrices (VVC standard values)
# ============================================================

# nonZeroSize=8, lfnst_idx=1
LFNST_8_1 = [
    [29,  48,  48,  42,  33,  22,  12,   0],
    [-33, -42, -12,  22,  48,  48,  29,   0],
    [48,  12, -42, -29,  22, -33, -48,   0],
    [-22, -48,  33, -12, -29,  48, -22,   0],
    [42, -29, -48,  33,  12, -22,  48,   0],
    [-48,  33,  22, -48,  42,  12, -29,   0],
    [12, -22,  29, -33,  42, -48,  48,   0],
    [-22,  48, -48,  22, -48,  48, -22,   0],
]

# nonZeroSize=8, lfnst_idx=2
LFNST_8_2 = [
    [29,  48,  48,  42,  33,  22,  12,   0],
    [-48, -22,  33,  48,  12, -42, -29,   0],
    [42, -29, -48,  33,  12, -22,  48,   0],
    [-12,  42, -22, -33,  48, -29,  12,   0],
    [48, -48,  12, -22,  29, -33,  42,   0],
    [-33,  12,  42, -48,  22,  48, -48,   0],
    [22, -48,  48, -22,  48, -48,  22,   0],
    [-48,  48, -22,  48, -48,  22, -48,   0],
]

# nonZeroSize=16, lfnst_idx=1 (16x8 matrix)
LFNST_16_1 = [
    [29,  52,  48,  37,  33,  22,  12,   0],
    [-33, -44, -12,  20,  48,  48,  29,   0],
    [48,  12, -44, -29,  22, -33, -48,   0],
    [-22, -48,  33, -12, -29,  48, -22,   0],
    [42, -29, -48,  33,  12, -22,  48,   0],
    [-48,  33,  22, -48,  42,  12, -29,   0],
    [12, -22,  29, -33,  42, -48,  48,   0],
    [-22,  48, -48,  22, -48,  48, -22,   0],
    [36, -18, -42,  48, -12, -33,  48,   0],
    [-48,  29,  22, -48,  42, -12, -29,   0],
    [22, -42,  33,  12, -48,  48, -22,   0],
    [-12,  33, -48,  42, -22, -12,  48,   0],
    [48, -48,  12, -22,  29, -33,  42,   0],
    [-33,  12,  42, -48,  22,  48, -48,   0],
    [22, -48,  48, -22,  48, -48,  22,   0],
    [-48,  48, -22,  48, -48,  22, -48,   0],
]

# nonZeroSize=16, lfnst_idx=2 (16x8 matrix)
LFNST_16_2 = [
    [29,  52,  48,  37,  33,  22,  12,   0],
    [-48, -22,  33,  48,  12, -42, -29,   0],
    [42, -29, -48,  33,  12, -22,  48,   0],
    [-12,  42, -22, -33,  48, -29,  12,   0],
    [48, -48,  12, -22,  29, -33,  42,   0],
    [-33,  12,  42, -48,  22,  48, -48,   0],
    [22, -48,  48, -22,  48, -48,  22,   0],
    [-48,  48, -22,  48, -48,  22, -48,   0],
    [36, -18, -42,  48, -12, -33,  48,   0],
    [-48,  42,  12, -29,  33, -22, -48,   0],
    [12, -33,  48, -42,  22,  12, -48,   0],
    [-22,  42, -33, -12,  48, -48,  22,   0],
    [48, -48,  12, -22,  29, -33,  42,   0],
    [-33,  12,  42, -48,  22,  48, -48,   0],
    [22, -48,  48, -22,  48, -48,  22,   0],
    [-48,  48, -22,  48, -48,  22, -48,   0],
]


# ============================================================
# Address mapping
# ============================================================

TRANSFORM_SIZES = {
    0: [4, 8, 16, 32, 64],   # DCT2
    1: [4, 8, 16, 32],        # DCT8
    2: [4, 8, 16, 32],        # DST7
}

TRANSFORM_NAMES = {0: "DCT2", 1: "DCT8", 2: "DST7"}


def compute_base_addrs() -> Dict[Tuple[int, int], int]:
    """Compute base addresses for each (tr_type, size) pair."""
    base = 0
    addrs = {}
    for tr_type in range(3):
        for size in TRANSFORM_SIZES[tr_type]:
            addrs[(tr_type, size)] = base
            base += size * size
    return addrs, base


def to_signed_16bit(val: int) -> int:
    """Convert to 16-bit signed representation for hex output."""
    if val < 0:
        val = val + 65536
    return val & 0xFFFF


# ============================================================
# Generate ROM hex file
# ============================================================

def generate_rom_hex(filename: str):
    """Generate rom_coeffs.hex for all transform kernels."""
    base_addrs, total_size = compute_base_addrs()

    # Initialize all entries to 0
    coeffs = [0] * total_size

    # Fill in coefficients
    for tr_type in range(3):
        for size in TRANSFORM_SIZES[tr_type]:
            base = base_addrs[(tr_type, size)]

            if tr_type == 0:
                matrix = gen_dct2(size)
            elif tr_type == 1:
                matrix = gen_dct8(size)
            else:
                matrix = gen_dst7(size)

            for i in range(size):
                for j in range(size):
                    coeffs[base + i * size + j] = matrix[i][j]

    # Write hex file (16-bit values, one per line)
    with open(filename, 'w') as f:
        f.write(f"// VVC ITS ROM coefficients\n")
        f.write(f"// Total entries: {total_size}\n")
        f.write(f"// Format: one 16-bit hex value per line\n\n")

        # Address map comment
        f.write(f"// Address map:\n")
        for tr_type in range(3):
            for size in TRANSFORM_SIZES[tr_type]:
                base = base_addrs[(tr_type, size)]
                f.write(f"//   {TRANSFORM_NAMES[tr_type]}-{size}: addr {base}..{base + size*size - 1}\n")
        f.write(f"\n")

        for i, val in enumerate(coeffs):
            f.write(f"{to_signed_16bit(val):04X}\n")

    print(f"Generated {filename}: {total_size} entries ({total_size * 2} bytes)")

    # Print address map
    print("\nAddress map:")
    for tr_type in range(3):
        for size in TRANSFORM_SIZES[tr_type]:
            base = base_addrs[(tr_type, size)]
            print(f"  {TRANSFORM_NAMES[tr_type]}-{size:2d}: {base:5d} .. {base + size*size - 1:5d}")

    return base_addrs, total_size


# ============================================================
# Generate LFNST hex file
# ============================================================

def generate_lfnst_hex(filename: str):
    """Generate lfnst_coeffs.hex for LFNST matrices."""
    # Layout: 8x8 idx1 (64) + 8x8 idx2 (64) + 16x8 idx1 (128) + 16x8 idx2 (128) = 384 entries
    coeffs = []

    # nonZeroSize=8, lfnst_idx=1: 8x8 = 64 entries
    for row in LFNST_8_1:
        coeffs.extend(row)

    # nonZeroSize=8, lfnst_idx=2: 8x8 = 64 entries
    for row in LFNST_8_2:
        coeffs.extend(row)

    # nonZeroSize=16, lfnst_idx=1: 16x8 = 128 entries
    for row in LFNST_16_1:
        coeffs.extend(row)

    # nonZeroSize=16, lfnst_idx=2: 16x8 = 128 entries
    for row in LFNST_16_2:
        coeffs.extend(row)

    with open(filename, 'w') as f:
        f.write(f"// VVC LFNST ROM coefficients\n")
        f.write(f"// Total entries: {len(coeffs)}\n\n")
        f.write(f"// nonZeroSize=8, lfnst_idx=1: addr 0..63\n")
        f.write(f"// nonZeroSize=8, lfnst_idx=2: addr 64..127\n")
        f.write(f"// nonZeroSize=16, lfnst_idx=1: addr 128..255\n")
        f.write(f"// nonZeroSize=16, lfnst_idx=2: addr 256..383\n\n")

        for val in coeffs:
            f.write(f"{to_signed_16bit(val):04X}\n")

    print(f"Generated {filename}: {len(coeffs)} entries ({len(coeffs) * 2} bytes)")


# ============================================================
# Generate Verilog ROM module (alternative to hex file)
# ============================================================

def generate_rom_verilog(filename: str, base_addrs: Dict, total_size: int):
    """Generate Verilog ROM module with $readmemh."""
    code = """\
// ===================================================================
// ITS Transform Kernel ROM
// Auto-generated by gen_rom_coeffs.py
// Supports DCT2(4/8/16/32/64), DCT8(4/8/16/32), DST7(4/8/16/32)
// ===================================================================

module its_rom (
    input  wire        clk,
    input  wire [13:0] addr,      // Flat address
    output reg  [15:0] coeff      // Coefficient output (signed)
);

    // ROM storage
    reg [15:0] rom [0:{max_addr}];

    // Load coefficients from hex file
    initial begin
        $readmemh("rom_coeffs.hex", rom);
    end

    // Synchronous read (1 cycle latency)
    always @(posedge clk) begin
        coeff <= rom[addr];
    end

endmodule
""".format(max_addr=total_size - 1)

    with open(filename, 'w') as f:
        f.write(code)

    print(f"Generated {filename}")


def generate_lfnst_rom_verilog(filename: str):
    """Generate LFNST ROM module with $readmemh."""
    code = """\
// ===================================================================
// ITS LFNST Transform Kernel ROM
// Auto-generated by gen_rom_coeffs.py
// Supports nonZeroSize=8 and 16, lfnst_idx=1 and 2
// ===================================================================

module its_lfnst_rom (
    input  wire        clk,
    input  wire [8:0]  addr,      // Address (0-383)
    output reg  [15:0] coeff      // Coefficient output (signed)
);

    // ROM storage: 8x8x2 + 16x8x2 = 384 entries
    reg [15:0] rom [0:383];

    // Load coefficients from hex file
    initial begin
        $readmemh("lfnst_coeffs.hex", rom);
    end

    // Synchronous read (1 cycle latency)
    always @(posedge clk) begin
        coeff <= rom[addr];
    end

endmodule
"""

    with open(filename, 'w') as f:
        f.write(code)

    print(f"Generated {filename}")


# ============================================================
# Main
# ============================================================

if __name__ == "__main__":
    import os

    # Output directory (same as script directory, or rtl/)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    rtl_dir = os.path.join(os.path.dirname(script_dir), 'rtl')

    print("=" * 60)
    print("VVC ITS ROM Coefficient Generator")
    print("=" * 60)

    # Generate transform kernel ROM
    print("\n--- Transform Kernel ROM ---")
    hex_path = os.path.join(rtl_dir, 'rom_coeffs.hex')
    base_addrs, total_size = generate_rom_hex(hex_path)

    # Generate LFNST ROM
    print("\n--- LFNST ROM ---")
    lfnst_hex_path = os.path.join(rtl_dir, 'lfnst_coeffs.hex')
    generate_lfnst_hex(lfnst_hex_path)

    # Generate Verilog modules
    print("\n--- Verilog Modules ---")
    rom_v_path = os.path.join(rtl_dir, 'its_rom.v')
    generate_rom_verilog(rom_v_path, base_addrs, total_size)

    lfnst_rom_v_path = os.path.join(rtl_dir, 'its_lfnst_rom.v')
    generate_lfnst_rom_verilog(lfnst_rom_v_path)

    # Print some sample matrices for verification
    print("\n" + "=" * 60)
    print("Verification: Sample matrices")
    print("=" * 60)

    for name, gen_fn in [("DCT2-4", lambda: gen_dct2(4)),
                          ("DCT8-4", lambda: gen_dct8(4)),
                          ("DST7-4", lambda: gen_dst7(4))]:
        print(f"\n{name}:")
        for row in gen_fn():
            print(f"  {[f'{v:4d}' for v in row]}")

    print("\nDone!")
