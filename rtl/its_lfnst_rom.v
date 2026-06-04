// ===================================================================
// ITS LFNST Transform Kernel ROM
// 8192 entries: nTrs=16 (2048) + nTrs=48 (6144)
// 16 scenarios: 4 lfnstTrSetIdx x 2 lfnst_idx x (16x16 or 48x16)
// ===================================================================

module its_lfnst_rom (
    input  wire        clk,
    input  wire [12:0] addr,      // Address (0-8191)
    output reg  [15:0] coeff      // Coefficient output (signed)
);

    // ROM storage: 8192 entries
    reg [15:0] rom [0:8191];

    // Load coefficients from hex file
    initial begin
        $readmemh("lfnst_coeffs.hex", rom);
    end

    // Synchronous read (1 cycle latency)
    always @(posedge clk) begin
        coeff <= rom[addr];
    end

endmodule
