"""
Parse official VVC ITS coefficient tables from competition document.
Handles Unicode minus sign (U+2212) and generates ROM hex files.
"""

import re
import os


def parse_matrix_rows(text):
    """Parse matrix rows from text like { 1 2 3 } { 4 5 6 } ..."""
    rows = []
    # Find all row patterns: { val val val ... }
    # Use a more robust pattern that handles nested content
    for match in re.finditer(r'\{([^{}]+)\}', text):
        row_str = match.group(1).strip()
        if row_str:
            # Replace Unicode minus (U+2212) with regular minus (U+002D)
            row_str = row_str.replace('−', '-')
            # Replace en-dash (U+2013) with regular minus
            row_str = row_str.replace('–', '-')
            # Replace em-dash (U+2014) with regular minus
            row_str = row_str.replace('—', '-')
            try:
                vals = [int(x) for x in row_str.split()]
                rows.append(vals)
            except ValueError as e:
                print(f"Warning: Could not parse row: {row_str[:50]}... Error: {e}")
    return rows


def parse_matrix_block(text):
    """Parse a matrix block enclosed in outer braces, containing multiple rows.
    Format: { { row1 } { row2 } ... }
    """
    # Find the outermost brace pair
    start = text.find('{')
    if start == -1:
        return []

    # Find matching closing brace
    depth = 0
    end = -1
    for i in range(start, len(text)):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                end = i
                break

    if end == -1:
        return []

    block = text[start:end + 1]
    return parse_matrix_rows(block)


def parse_document(filename):
    """Parse the competition document and extract all coefficient tables."""
    with open(filename, 'r', encoding='utf-8') as f:
        content = f.read()

    coefficients = {
        'dct2': {},
        'dst7': {},
        'dct8': {},
        'lfnst': {}
    }

    # ============================================================
    # Parse DST7 matrices
    # ============================================================
    # Find DST7 section
    dst7_start = content.find('DST-VII')
    dst7_end = content.find('DCT-VIII', dst7_start)
    dst7_section = content[dst7_start:dst7_end] if dst7_end != -1 else content[dst7_start:]

    # nTbs = 4
    match = re.search(r'nTbs\s*=\s*4\s*\n.*?transMatrix.*?=\s*\n', dst7_section)
    if match:
        matrix = parse_matrix_block(dst7_section[match.end():])
        if matrix:
            coefficients['dst7'][4] = matrix

    # nTbs = 8
    match = re.search(r'nTbs\s*=\s*8\s*\n.*?transMatrix.*?=\s*\n', dst7_section)
    if match:
        matrix = parse_matrix_block(dst7_section[match.end():])
        if matrix:
            coefficients['dst7'][8] = matrix

    # nTbs = 16
    match = re.search(r'nTbs\s*=\s*16\s*\n.*?transMatrix.*?=\s*\n', dst7_section)
    if match:
        matrix = parse_matrix_block(dst7_section[match.end():])
        if matrix:
            coefficients['dst7'][16] = matrix

    # nTbs = 32 (column decomposition)
    match = re.search(r'nTbs\s*=\s*32.*?transMatrixCol0to15\s*=\s*\n', dst7_section, re.DOTALL)
    if match:
        col0_15 = parse_matrix_block(dst7_section[match.end():])
        match2 = re.search(r'transMatrixCol16to31\s*=\s*\n', dst7_section[match.end():])
        if match2:
            col16_31 = parse_matrix_block(dst7_section[match.end() + match2.end():])
            if col0_15 and col16_31:
                coefficients['dst7'][32] = {'col0to15': col0_15, 'col16to31': col16_31}

    # ============================================================
    # Parse DCT8 matrices
    # ============================================================
    # Find DCT8 section
    dct8_start = content.find('DCT-VIII')
    dct8_end = content.find('接口', dct8_start)
    dct8_section = content[dct8_start:dct8_end] if dct8_end != -1 else content[dct8_start:]

    # nTbs = 4 (note: may have (1182) suffix)
    match = re.search(r'nTbs\s*=\s*4\s*\n.*?transMatrix.*?=\s*(?:\(\d+\))?\s*\n', dct8_section)
    if match:
        matrix = parse_matrix_block(dct8_section[match.end():])
        if matrix:
            coefficients['dct8'][4] = matrix

    # nTbs = 8 (note: may have (1183) suffix)
    match = re.search(r'nTbs\s*=\s*8\s*\n.*?transMatrix.*?=\s*(?:\(\d+\))?\s*\n', dct8_section)
    if match:
        matrix = parse_matrix_block(dct8_section[match.end():])
        if matrix:
            coefficients['dct8'][8] = matrix

    # nTbs = 16
    match = re.search(r'nTbs\s*=\s*16\s*\n.*?transMatrix.*?=\s*\n', dct8_section)
    if match:
        matrix = parse_matrix_block(dct8_section[match.end():])
        if matrix:
            coefficients['dct8'][16] = matrix

    # nTbs = 32 (column decomposition)
    match = re.search(r'nTbs\s*=\s*32.*?transMatrixCol0to15\s*=\s*\n', dct8_section, re.DOTALL)
    if match:
        col0_15 = parse_matrix_block(dct8_section[match.end():])
        match2 = re.search(r'transMatrixCol16to31\s*=\s*\n', dct8_section[match.end():])
        if match2:
            col16_31 = parse_matrix_block(dct8_section[match.end() + match2.end():])
            if col0_15 and col16_31:
                coefficients['dct8'][32] = {'col0to15': col0_15, 'col16to31': col16_31}

    # ============================================================
    # Parse DCT2 64-point matrix
    # ============================================================
    dct2_start = content.find('DCT-II')
    dct2_end = content.find('DST-VII', dct2_start)
    dct2_section = content[dct2_start:dct2_end] if dct2_end != -1 else content[dct2_start:]

    match = re.search(r'nTbs\s*=\s*64.*?transMatrixCol0to15\s*=\s*\n', dct2_section, re.DOTALL)
    if match:
        col0_15 = parse_matrix_block(dct2_section[match.end():])
        match2 = re.search(r'transMatrixCol16to31\s*=\s*\n', dct2_section[match.end():])
        if match2:
            col16_31 = parse_matrix_block(dct2_section[match.end() + match2.end():])
            if col0_15 and col16_31:
                coefficients['dct2'][64] = {'col0to15': col0_15, 'col16to31': col16_31}

    # Derive DCT2 smaller sizes from 64-point matrix
    if 64 in coefficients['dct2']:
        dct2_64 = expand_dct2_64(coefficients['dct2'][64])
        for size in [4, 8, 16, 32]:
            coefficients['dct2'][size] = extract_submatrix(dct2_64, size)

    return coefficients


def expand_dct2_64(coeffs_64):
    """Expand DCT2 64-point matrix from column decomposition.

    Document notation:
      transMatrix[ m ][ n ] = transMatrixCol0to15[ m ][ n ] with m = 0..15, n = 0..63
      transMatrix[ m ][ n ] = transMatrixCol16to31[ m − 16 ][ n ] with m = 16..31, n = 0..63
      transMatrix[ m ][ n ] = ( n & 1 ? −1 : 1 ) * transMatrixCol16to31[ 47 −m ][ n ] with m = 32..47, n = 0..63
      transMatrix[ m ][ n ] = ( n & 1 ? −1 : 1 ) * transMatrixCol0to15[ 63 −m ][ n ] with m = 48..63, n = 0..63

    Each column block has 16 values per row. The full 64-column matrix is:
      cols 0-15: from col0to15
      cols 16-31: from col16to31
      cols 32-47: same as col16to31 but with alternating sign per column
      cols 48-63: same as col0to15 but with alternating sign per column
    """
    col0_15 = coeffs_64['col0to15']
    col16_31 = coeffs_64['col16to31']

    matrix = [[0] * 64 for _ in range(64)]

    # Rows 0-15
    for m in range(16):
        for n in range(16):
            matrix[m][n] = col0_15[m][n]  # cols 0-15
            matrix[m][n + 16] = col16_31[m][n]  # cols 16-31
            sign32 = -1 if ((n + 32) & 1) else 1
            matrix[m][n + 32] = sign32 * col16_31[m][n]  # cols 32-47
            sign48 = -1 if ((n + 48) & 1) else 1
            matrix[m][n + 48] = sign48 * col0_15[m][n]  # cols 48-63

    # Rows 16-31
    for m in range(16):
        for n in range(16):
            matrix[m + 16][n] = col16_31[m][n]  # cols 0-15
            matrix[m + 16][n + 16] = col16_31[m][n]  # cols 16-31
            sign32 = -1 if ((n + 32) & 1) else 1
            matrix[m + 16][n + 32] = sign32 * col16_31[m][n]  # cols 32-47
            sign48 = -1 if ((n + 48) & 1) else 1
            matrix[m + 16][n + 48] = sign48 * col0_15[m][n]  # cols 48-63

    # Rows 32-47: sign * col16to31[15-m][n % 16]
    for m in range(16):
        for n in range(64):
            sign = -1 if (n & 1) else 1
            matrix[m + 32][n] = sign * col16_31[15 - m][n % 16]

    # Rows 48-63: sign * col0to15[15-m][n % 16]
    for m in range(16):
        for n in range(64):
            sign = -1 if (n & 1) else 1
            matrix[m + 48][n] = sign * col0_15[15 - m][n % 16]

    return matrix


def extract_submatrix(matrix, size):
    """Extract size x size submatrix from 64x64 matrix."""
    return [row[:size] for row in matrix[:size]]


def generate_rom_hex(coefficients, output_dir):
    """Generate ROM hex files for all transform types and sizes."""
    os.makedirs(output_dir, exist_ok=True)

    # ROM address layout
    base_addr = {
        'dct2': {4: 0, 8: 16, 16: 80, 32: 336, 64: 1360},
        'dct8': {4: 5456, 8: 5472, 16: 5536, 32: 5792},
        'dst7': {4: 6816, 8: 6832, 16: 6896, 32: 7152}
    }

    # Generate main ROM
    rom_data = [0] * 8192  # Max address

    for tr_type, sizes in coefficients.items():
        if tr_type == 'lfnst':
            continue

        for size, matrix in sizes.items():
            if isinstance(matrix, dict):
                # Column decomposition (size >= 32)
                if size == 32:
                    # Expand 32-point from column decomposition
                    # Each column block has 16 values per row
                    col0_15 = matrix['col0to15']
                    col16_31 = matrix['col16to31']
                    full_matrix = [[0] * 32 for _ in range(32)]
                    for m in range(16):
                        for n in range(16):
                            full_matrix[m][n] = col0_15[m][n]
                            full_matrix[m][n + 16] = col16_31[m][n]
                    for m in range(16):
                        for n in range(16):
                            full_matrix[m + 16][n] = col16_31[m][n]
                            full_matrix[m + 16][n + 16] = col0_15[m][n]
                    matrix = full_matrix
                elif size == 64:
                    matrix = expand_dct2_64(matrix)

            if tr_type not in base_addr:
                continue
            if size not in base_addr[tr_type]:
                continue

            base = base_addr[tr_type][size]
            for row in range(size):
                for col in range(size):
                    addr = base + row * size + col
                    val = matrix[row][col]
                    # Convert to 16-bit signed hex
                    if val < 0:
                        val = val + 65536
                    rom_data[addr] = val & 0xFFFF

    # Write ROM hex file
    with open(os.path.join(output_dir, 'rom_coeffs.hex'), 'w') as f:
        for i in range(8192):
            f.write(f'{rom_data[i]:04X}\n')

    print(f"Generated rom_coeffs.hex with {8192} entries")


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.dirname(script_dir)
    doc_file = os.path.join(project_dir, 'output', 'lfnst_doc.txt')

    print("Parsing official coefficients from document...")
    coefficients = parse_document(doc_file)

    # Print summary
    print("\nExtracted coefficients:")
    for tr_type, sizes in coefficients.items():
        print(f"  {tr_type}:")
        for size, matrix in sizes.items():
            if isinstance(matrix, dict):
                print(f"    nTbS={size}: column decomposition")
            else:
                print(f"    nTbS={size}: {len(matrix)}x{len(matrix[0])} matrix")

    # Generate ROM hex files
    output_dir = os.path.join(project_dir, 'sim')
    generate_rom_hex(coefficients, output_dir)

    # Also copy to tb directory
    tb_dir = os.path.join(project_dir, 'tb')
    import shutil
    shutil.copy2(os.path.join(output_dir, 'rom_coeffs.hex'),
                 os.path.join(tb_dir, 'rom_coeffs.hex'))
    print(f"Copied to {tb_dir}")


if __name__ == '__main__':
    main()
