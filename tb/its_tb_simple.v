// ===================================================================
// ITS Simple Testbench - Test transform engine directly
// ===================================================================

`timescale 1ns / 1ps

module its_tb_simple;

    // Clock and reset
    reg clk;
    reg rst_n;

    // Transform engine signals
    reg         start;
    reg  [1:0]  tr_type;
    reg  [6:0]  size;
    reg  [15:0] data_in;
    reg         data_in_vld;
    wire        data_in_req;
    wire [15:0] data_out;
    wire        data_out_vld;
    reg         data_out_req;
    wire        done;

    // Test control
    integer test_pass;
    integer test_fail;
    integer out_idx;
    reg signed [15:0] expected [0:3];

    // Clock generation (500MHz -> 2ns period)
    initial clk = 0;
    always #1 clk = ~clk;

    // DUT instantiation
    its_transform_engine u_dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .tr_type    (tr_type),
        .size       (size),
        .data_in    (data_in),
        .data_in_vld(data_in_vld),
        .data_in_req(data_in_req),
        .data_out   (data_out),
        .data_out_vld(data_out_vld),
        .data_out_req(data_out_req),
        .done       (done)
    );

    // Task: Run one transform test
    task run_test;
        input [1:0] tr;
        input [5:0] sz;
        input signed [15:0] d0, d1, d2, d3;
        input signed [15:0] e0, e1, e2, e3;
        input [8*30-1:0] name;
        begin
            $display("\n=== %0s ===", name);
            tr_type = tr;
            size = sz;

            // Start
            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;

            // Send 4 data points
            @(posedge clk);
            while (!data_in_req) @(posedge clk);
            data_in = d0; data_in_vld = 1;
            @(posedge clk); data_in_vld = 0;

            @(posedge clk);
            while (!data_in_req) @(posedge clk);
            data_in = d1; data_in_vld = 1;
            @(posedge clk); data_in_vld = 0;

            @(posedge clk);
            while (!data_in_req) @(posedge clk);
            data_in = d2; data_in_vld = 1;
            @(posedge clk); data_in_vld = 0;

            @(posedge clk);
            while (!data_in_req) @(posedge clk);
            data_in = d3; data_in_vld = 1;
            @(posedge clk); data_in_vld = 0;

            // Set expected values
            expected[0] = e0; expected[1] = e1;
            expected[2] = e2; expected[3] = e3;

            // Wait for outputs
            out_idx = 0;
            repeat(200) begin
                @(posedge clk);
                if (data_out_vld) begin
                    if ($signed(data_out) == expected[out_idx]) begin
                        $display("  Output[%0d] = %0d PASS", out_idx, $signed(data_out));
                        test_pass = test_pass + 1;
                    end else begin
                        $display("  Output[%0d] = %0d FAIL (expected %0d)", out_idx, $signed(data_out), expected[out_idx]);
                        test_fail = test_fail + 1;
                    end
                    out_idx = out_idx + 1;
                end
                if (done) disable run_test;
            end
            $display("  TIMEOUT waiting for done!");
            test_fail = test_fail + 1;
        end
    endtask

    // Test sequence
    initial begin
        // Initialize
        test_pass = 0;
        test_fail = 0;
        rst_n = 0;
        start = 0;
        tr_type = 0;
        size = 0;
        data_in = 0;
        data_in_vld = 0;
        data_out_req = 1;

        // Reset
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        // Test 1: DCT2 4x4 [64,64,64,64] -> [247,-47,47,9]
        run_test(2'd0, 6'd4,
                 16'sd64, 16'sd64, 16'sd64, 16'sd64,
                 16'sd247, -16'sd47, 16'sd47, 16'sd9,
                 "DCT2 4x4 [64,64,64,64]");
        repeat(10) @(posedge clk);

        // Test 2: DCT2 4x4 [100,50,30,20] -> [206,72,68,54]
        run_test(2'd0, 6'd4,
                 16'sd100, 16'sd50, 16'sd30, 16'sd20,
                 16'sd206, 16'sd72, 16'sd68, 16'sd54,
                 "DCT2 4x4 [100,50,30,20]");
        repeat(10) @(posedge clk);

        // Test 3: DCT8 4x4 [64,64,64,64] -> [227,-79,53,-45]
        run_test(2'd1, 6'd4,
                 16'sd64, 16'sd64, 16'sd64, 16'sd64,
                 16'sd227, -16'sd79, 16'sd53, -16'sd45,
                 "DCT8 4x4 [64,64,64,64]");
        repeat(10) @(posedge clk);

        // Test 4: DST7 4x4 [64,64,64,64] -> [-16,77,252,-38]
        run_test(2'd2, 6'd4,
                 16'sd64, 16'sd64, 16'sd64, 16'sd64,
                 -16'sd16, 16'sd77, 16'sd252, -16'sd38,
                 "DST7 4x4 [64,64,64,64]");
        repeat(10) @(posedge clk);

        // Summary
        $display("\n========================================");
        $display("Test Summary: %0d passed, %0d failed", test_pass, test_fail);
        $display("========================================");

        if (test_fail == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("SOME TESTS FAILED!");

        $finish;
    end

    // Timeout
    initial begin
        #10000;
        $display("\nGLOBAL TIMEOUT!");
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("its_tb_simple.vcd");
        $dumpvars(0, its_tb_simple);
    end

endmodule
