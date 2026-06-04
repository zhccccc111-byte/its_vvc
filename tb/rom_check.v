`timescale 1ns / 1ps
module rom_check;
    reg clk;
    initial clk = 0;
    always #1 clk = ~clk;

    wire [13:0] addr;
    wire [15:0] coeff;

    // Test ROM directly
    reg [13:0] test_addr;
    its_rom u_rom (.clk(clk), .addr(test_addr), .coeff(coeff));

    initial begin
        // Check DCT2-8 entries (addr 16-79)
        $display("=== ROM Check ===");
        test_addr = 14'd0;
        @(posedge clk); @(posedge clk);
        $display("addr=%0d coeff=%0d (0x%04X)", test_addr, $signed(coeff), coeff);

        test_addr = 14'd16;
        @(posedge clk); @(posedge clk);
        $display("addr=%0d coeff=%0d (0x%04X)", test_addr, $signed(coeff), coeff);

        test_addr = 14'd17;
        @(posedge clk); @(posedge clk);
        $display("addr=%0d coeff=%0d (0x%04X)", test_addr, $signed(coeff), coeff);

        test_addr = 14'd18;
        @(posedge clk); @(posedge clk);
        $display("addr=%0d coeff=%0d (0x%04X)", test_addr, $signed(coeff), coeff);

        test_addr = 14'd24;
        @(posedge clk); @(posedge clk);
        $display("addr=%0d coeff=%0d (0x%04X)", test_addr, $signed(coeff), coeff);

        test_addr = 14'd25;
        @(posedge clk); @(posedge clk);
        $display("addr=%0d coeff=%0d (0x%04X)", test_addr, $signed(coeff), coeff);

        // DCT2-8 expected:
        // T[0] = [64, 64, 64, 64, 64, 64, 64, 64] at addr 16-23
        // T[1] = [89, 75, 50, 18, -18, -50, -75, -89] at addr 24-31
        $display("Expected: addr 16=64, 17=64, 18=64, 24=89, 25=75");

        $finish;
    end
endmodule
