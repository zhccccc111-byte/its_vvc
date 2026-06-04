// ===================================================================
// ITS Testbench - Auto-iterate all test cases from config file
// ===================================================================

`timescale 1ns / 1ps

module its_tb;

    // Clock and reset
    reg clk;
    reg rst_n;

    // DUT signals
    reg  [21:0] it_info;
    reg         it_info_vld;
    reg  [15:0] it_data_in;
    reg  [11:0] it_data_addr;
    reg         it_data_in_vld;
    wire        it_data_in_req;
    wire [39:0] it_data_out;
    wire        it_data_out_vld;
    reg         it_data_out_req;
    wire        it_done;

    // Test control
    integer test_pass;
    integer test_fail;
    integer total_tests;

    // Test vector storage
    reg [27:0] input_vec [0:4095];
    reg [9:0]  golden_vec [0:4095];

    // Clock generation (500MHz -> 2ns period)
    initial clk = 0;
    always #1 clk = ~clk;

    // DUT instantiation
    its_top u_dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .it_info       (it_info),
        .it_info_vld   (it_info_vld),
        .it_data_in    (it_data_in),
        .it_data_addr  (it_data_addr),
        .it_data_in_vld(it_data_in_vld),
        .it_data_in_req(it_data_in_req),
        .it_data_out   (it_data_out),
        .it_data_out_vld(it_data_out_vld),
        .it_data_out_req(it_data_out_req),
        .it_done       (it_done)
    );

    // Task: Send TU info
    task send_info;
        input [6:0] width;
        input [6:0] height;
        input [1:0] tr_hor;
        input [1:0] tr_ver;
        input [1:0] lfnst_tr_set_idx;
        input [1:0] lfnst_idx;
        begin
            @(posedge clk);
            it_info = {lfnst_idx, lfnst_tr_set_idx, tr_ver, tr_hor, height, width};
            it_info_vld = 1;
            @(posedge clk);
            it_info_vld = 0;
            repeat(3) @(posedge clk);
        end
    endtask

    // Task: Send one data point
    task send_data;
        input [11:0] addr;
        input [15:0] data;
        begin
            @(posedge clk);
            while (!it_data_in_req) @(posedge clk);
            it_data_in = data;
            it_data_addr = addr;
            it_data_in_vld = 1;
            @(posedge clk);
            it_data_in_vld = 0;
        end
    endtask

    // Task: Wait for output with timeout
    task wait_output;
        output [39:0] data;
        output        valid;
        integer timeout_cnt;
        begin
            timeout_cnt = 0;
            valid = 0;
            while (timeout_cnt < 5000000) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
                if (it_data_out_vld && it_data_out_req) begin
                    data = it_data_out;
                    valid = 1;
                    disable wait_output;
                end
            end
            if (!valid) $display("  TIMEOUT waiting for output!");
        end
    endtask

    // Task: Wait for done
    task wait_done;
        integer timeout_cnt;
        begin
            timeout_cnt = 0;
            while (timeout_cnt < 1000000) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
                if (it_done) disable wait_done;
            end
            $display("  TIMEOUT waiting for done!");
        end
    endtask

    // Task: Run one test case (reads hex files by name)
    task run_test;
        input [800*8:1] test_name;
        input [6:0] width;
        input [6:0] height;
        input [1:0] tr_hor;
        input [1:0] tr_ver;
        input [1:0] lfnst_tr_set_idx;
        input [1:0] lfnst_idx;
        input [800*8:1] input_hex;
        input [800*8:1] golden_hex;

        integer i, j;
        integer out_idx;
        reg [39:0] out_data;
        reg out_valid;
        reg signed [9:0] exp_val, got_val;
        integer local_mismatches;
        integer total_outputs;
        integer input_count;
        integer timeout_cnt;
        begin
            $display("\n=== %0s (w=%0d h=%0d tr_h=%0d tr_v=%0d sidx=%0d lfnst=%0d) ===",
                     test_name, width, height, tr_hor, tr_ver, lfnst_tr_set_idx, lfnst_idx);
            local_mismatches = 0;

            // Reset DUT and clear internal memories
            rst_n = 0;
            repeat(5) @(posedge clk);
            for (i = 0; i < 4096; i = i + 1) begin
                u_dut.in_mem[i] = 16'sd0;
                u_dut.tp_buf[i] = 16'sd0;
                u_dut.out_mem[i] = 10'sd0;
            end
            rst_n = 1;
            repeat(5) @(posedge clk);

            // Clear test vector arrays
            for (i = 0; i < 4096; i = i + 1) begin
                input_vec[i] = 28'd0;
                golden_vec[i] = 10'd0;
            end

            // Load test vectors
            $readmemh(input_hex, input_vec);
            $readmemh(golden_hex, golden_vec);

            total_outputs = width * height;
            input_count = 0;
            for (i = 0; i < 4096; i = i + 1) begin
                if (input_vec[i] != 28'd0)
                    input_count = input_count + 1;
            end

            // Send info
            send_info(width, height, tr_hor, tr_ver, lfnst_tr_set_idx, lfnst_idx);

            // Send input data
            for (i = 0; i < input_count; i = i + 1) begin
                send_data(input_vec[i][27:16], input_vec[i][15:0]);
            end

            // Collect and compare outputs
            out_idx = 0;
            while (out_idx < total_outputs) begin
                wait_output(out_data, out_valid);
                if (out_valid) begin
                    for (j = 0; j < 4 && out_idx + j < total_outputs; j = j + 1) begin
                        case (j)
                            0: got_val = out_data[9:0];
                            1: got_val = out_data[19:10];
                            2: got_val = out_data[29:20];
                            3: got_val = out_data[39:30];
                        endcase
                        exp_val = golden_vec[out_idx + j];
                        if (got_val !== exp_val) begin
                            if (local_mismatches < 5)
                                $display("  MISMATCH at out[%0d]: exp=%0d got=%0d",
                                         out_idx + j, $signed(exp_val), $signed(got_val));
                            local_mismatches = local_mismatches + 1;
                        end
                    end
                    out_idx = out_idx + 4;
                end else begin
                    $display("  ERROR: No valid output at index %0d", out_idx);
                    out_idx = total_outputs;
                end
            end

            wait_done;

            if (local_mismatches == 0) begin
                $display("  PASS (%0d outputs)", total_outputs);
                test_pass = test_pass + 1;
            end else begin
                $display("  FAIL: %0d/%0d mismatches", local_mismatches, total_outputs);
                test_fail = test_fail + 1;
            end

            total_tests = total_tests + 1;
            repeat(5) @(posedge clk);
        end
    endtask


    // ================================================================
    // Main test sequence
    // ================================================================
    initial begin
        test_pass = 0;
        test_fail = 0;
        total_tests = 0;
        rst_n = 0;
        it_info = 0;
        it_info_vld = 0;
        it_data_in = 0;
        it_data_addr = 0;
        it_data_in_vld = 0;
        it_data_out_req = 1;

        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        // ============================
        // DCT2 (25 block sizes)
        // ============================
        run_test("dct2_4x4",    7'd4,  7'd4,  2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_4x4_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_4x4_golden.hex");
        run_test("dct2_4x8",    7'd4,  7'd8,  2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_4x8_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_4x8_golden.hex");
        run_test("dct2_4x16",   7'd4,  7'd16, 2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_4x16_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_4x16_golden.hex");
        run_test("dct2_4x32",   7'd4,  7'd32, 2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_4x32_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_4x32_golden.hex");
        run_test("dct2_4x64",   7'd4,  7'd64, 2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_4x64_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_4x64_golden.hex");
        run_test("dct2_8x4",    7'd8,  7'd4,  2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_8x4_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_8x4_golden.hex");
        run_test("dct2_16x4",   7'd16, 7'd4,  2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_16x4_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_16x4_golden.hex");
        run_test("dct2_32x4",   7'd32, 7'd4,  2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_32x4_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_32x4_golden.hex");
        run_test("dct2_64x4",   7'd64, 7'd4,  2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_64x4_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_64x4_golden.hex");
        run_test("dct2_8x8",    7'd8,  7'd8,  2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_8x8_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_8x8_golden.hex");
        run_test("dct2_8x16",   7'd8,  7'd16, 2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_8x16_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_8x16_golden.hex");
        run_test("dct2_8x32",   7'd8,  7'd32, 2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_8x32_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_8x32_golden.hex");
        run_test("dct2_8x64",   7'd8,  7'd64, 2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_8x64_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_8x64_golden.hex");
        run_test("dct2_16x8",   7'd16, 7'd8,  2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_16x8_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_16x8_golden.hex");
        run_test("dct2_32x8",   7'd32, 7'd8,  2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_32x8_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_32x8_golden.hex");
        run_test("dct2_64x8",   7'd64, 7'd8,  2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_64x8_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_64x8_golden.hex");
        run_test("dct2_16x16",  7'd16, 7'd16, 2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_16x16_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_16x16_golden.hex");
        run_test("dct2_16x32",  7'd16, 7'd32, 2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_16x32_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_16x32_golden.hex");
        run_test("dct2_16x64",  7'd16, 7'd64, 2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_16x64_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_16x64_golden.hex");
        run_test("dct2_32x16",  7'd32, 7'd16, 2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_32x16_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_32x16_golden.hex");
        run_test("dct2_32x32",  7'd32, 7'd32, 2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_32x32_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_32x32_golden.hex");
        run_test("dct2_32x64",  7'd32, 7'd64, 2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_32x64_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_32x64_golden.hex");
        run_test("dct2_64x16",  7'd64, 7'd16, 2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_64x16_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_64x16_golden.hex");
        run_test("dct2_64x32",  7'd64, 7'd32, 2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_64x32_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_64x32_golden.hex");
        run_test("dct2_64x64",  7'd64, 7'd64, 2'd0, 2'd0, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_64x64_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_64x64_golden.hex");

        // ============================
        // DCT8 (16 block sizes)
        // ============================
        run_test("dct8_4x4",    7'd4,  7'd4,  2'd1, 2'd1, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_4x4_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_4x4_golden.hex");
        run_test("dct8_4x8",    7'd4,  7'd8,  2'd1, 2'd1, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_4x8_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_4x8_golden.hex");
        run_test("dct8_4x16",   7'd4,  7'd16, 2'd1, 2'd1, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_4x16_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_4x16_golden.hex");
        run_test("dct8_4x32",   7'd4,  7'd32, 2'd1, 2'd1, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_4x32_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_4x32_golden.hex");
        run_test("dct8_8x4",    7'd8,  7'd4,  2'd1, 2'd1, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_8x4_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_8x4_golden.hex");
        run_test("dct8_16x4",   7'd16, 7'd4,  2'd1, 2'd1, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_16x4_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_16x4_golden.hex");
        run_test("dct8_32x4",   7'd32, 7'd4,  2'd1, 2'd1, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_32x4_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_32x4_golden.hex");
        run_test("dct8_8x8",    7'd8,  7'd8,  2'd1, 2'd1, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_8x8_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_8x8_golden.hex");
        run_test("dct8_8x16",   7'd8,  7'd16, 2'd1, 2'd1, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_8x16_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_8x16_golden.hex");
        run_test("dct8_8x32",   7'd8,  7'd32, 2'd1, 2'd1, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_8x32_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_8x32_golden.hex");
        run_test("dct8_16x8",   7'd16, 7'd8,  2'd1, 2'd1, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_16x8_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_16x8_golden.hex");
        run_test("dct8_32x8",   7'd32, 7'd8,  2'd1, 2'd1, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_32x8_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_32x8_golden.hex");
        run_test("dct8_16x16",  7'd16, 7'd16, 2'd1, 2'd1, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_16x16_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_16x16_golden.hex");
        run_test("dct8_16x32",  7'd16, 7'd32, 2'd1, 2'd1, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_16x32_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_16x32_golden.hex");
        run_test("dct8_32x16",  7'd32, 7'd16, 2'd1, 2'd1, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_32x16_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_32x16_golden.hex");
        run_test("dct8_32x32",  7'd32, 7'd32, 2'd1, 2'd1, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_32x32_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct8_32x32_golden.hex");

        // ============================
        // DST7 (16 block sizes)
        // ============================
        run_test("dst7_4x4",    7'd4,  7'd4,  2'd2, 2'd2, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_4x4_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_4x4_golden.hex");
        run_test("dst7_4x8",    7'd4,  7'd8,  2'd2, 2'd2, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_4x8_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_4x8_golden.hex");
        run_test("dst7_4x16",   7'd4,  7'd16, 2'd2, 2'd2, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_4x16_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_4x16_golden.hex");
        run_test("dst7_4x32",   7'd4,  7'd32, 2'd2, 2'd2, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_4x32_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_4x32_golden.hex");
        run_test("dst7_8x4",    7'd8,  7'd4,  2'd2, 2'd2, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_8x4_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_8x4_golden.hex");
        run_test("dst7_16x4",   7'd16, 7'd4,  2'd2, 2'd2, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_16x4_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_16x4_golden.hex");
        run_test("dst7_32x4",   7'd32, 7'd4,  2'd2, 2'd2, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_32x4_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_32x4_golden.hex");
        run_test("dst7_8x8",    7'd8,  7'd8,  2'd2, 2'd2, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_8x8_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_8x8_golden.hex");
        run_test("dst7_8x16",   7'd8,  7'd16, 2'd2, 2'd2, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_8x16_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_8x16_golden.hex");
        run_test("dst7_8x32",   7'd8,  7'd32, 2'd2, 2'd2, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_8x32_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_8x32_golden.hex");
        run_test("dst7_16x8",   7'd16, 7'd8,  2'd2, 2'd2, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_16x8_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_16x8_golden.hex");
        run_test("dst7_32x8",   7'd32, 7'd8,  2'd2, 2'd2, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_32x8_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_32x8_golden.hex");
        run_test("dst7_16x16",  7'd16, 7'd16, 2'd2, 2'd2, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_16x16_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_16x16_golden.hex");
        run_test("dst7_16x32",  7'd16, 7'd32, 2'd2, 2'd2, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_16x32_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_16x32_golden.hex");
        run_test("dst7_32x16",  7'd32, 7'd16, 2'd2, 2'd2, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_32x16_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_32x16_golden.hex");
        run_test("dst7_32x32",  7'd32, 7'd32, 2'd2, 2'd2, 2'd0, 2'd0,
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_32x32_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dst7_32x32_golden.hex");

        // ============================
        // LFNST nTrs=16 (4 setIdx x 2 idx, using 4x4)
        // ============================
        run_test("lfnst16_s0_i1", 7'd4, 7'd4, 2'd0, 2'd0, 2'd0, 2'd1,
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst16_s0_i1_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst16_s0_i1_golden.hex");
        run_test("lfnst16_s0_i2", 7'd4, 7'd4, 2'd0, 2'd0, 2'd0, 2'd2,
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst16_s0_i2_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst16_s0_i2_golden.hex");
        run_test("lfnst16_s1_i1", 7'd4, 7'd4, 2'd0, 2'd0, 2'd1, 2'd1,
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst16_s1_i1_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst16_s1_i1_golden.hex");
        run_test("lfnst16_s1_i2", 7'd4, 7'd4, 2'd0, 2'd0, 2'd1, 2'd2,
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst16_s1_i2_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst16_s1_i2_golden.hex");
        run_test("lfnst16_s2_i1", 7'd4, 7'd4, 2'd0, 2'd0, 2'd2, 2'd1,
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst16_s2_i1_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst16_s2_i1_golden.hex");
        run_test("lfnst16_s2_i2", 7'd4, 7'd4, 2'd0, 2'd0, 2'd2, 2'd2,
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst16_s2_i2_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst16_s2_i2_golden.hex");
        run_test("lfnst16_s3_i1", 7'd4, 7'd4, 2'd0, 2'd0, 2'd3, 2'd1,
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst16_s3_i1_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst16_s3_i1_golden.hex");
        run_test("lfnst16_s3_i2", 7'd4, 7'd4, 2'd0, 2'd0, 2'd3, 2'd2,
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst16_s3_i2_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst16_s3_i2_golden.hex");

        // ============================
        // LFNST nTrs=48 (4 setIdx x 2 idx, using 8x8)
        // ============================
        run_test("lfnst48_s0_i1", 7'd8, 7'd8, 2'd0, 2'd0, 2'd0, 2'd1,
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst48_s0_i1_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst48_s0_i1_golden.hex");
        run_test("lfnst48_s0_i2", 7'd8, 7'd8, 2'd0, 2'd0, 2'd0, 2'd2,
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst48_s0_i2_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst48_s0_i2_golden.hex");
        run_test("lfnst48_s1_i1", 7'd8, 7'd8, 2'd0, 2'd0, 2'd1, 2'd1,
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst48_s1_i1_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst48_s1_i1_golden.hex");
        run_test("lfnst48_s1_i2", 7'd8, 7'd8, 2'd0, 2'd0, 2'd1, 2'd2,
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst48_s1_i2_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst48_s1_i2_golden.hex");
        run_test("lfnst48_s2_i1", 7'd8, 7'd8, 2'd0, 2'd0, 2'd2, 2'd1,
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst48_s2_i1_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst48_s2_i1_golden.hex");
        run_test("lfnst48_s2_i2", 7'd8, 7'd8, 2'd0, 2'd0, 2'd2, 2'd2,
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst48_s2_i2_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst48_s2_i2_golden.hex");
        run_test("lfnst48_s3_i1", 7'd8, 7'd8, 2'd0, 2'd0, 2'd3, 2'd1,
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst48_s3_i1_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst48_s3_i1_golden.hex");
        run_test("lfnst48_s3_i2", 7'd8, 7'd8, 2'd0, 2'd0, 2'd3, 2'd2,
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst48_s3_i2_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/lfnst48_s3_i2_golden.hex");

        // ============================
        // LFNST nTrs=48 with different block sizes
        // ============================
        run_test("dct2_8x16_lfnst1",  7'd8,  7'd16, 2'd0, 2'd0, 2'd0, 2'd1,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_8x16_lfnst1_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_8x16_lfnst1_golden.hex");
        run_test("dct2_16x8_lfnst1",  7'd16, 7'd8,  2'd0, 2'd0, 2'd0, 2'd1,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_16x8_lfnst1_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_16x8_lfnst1_golden.hex");
        run_test("dct2_16x16_lfnst1", 7'd16, 7'd16, 2'd0, 2'd0, 2'd0, 2'd1,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_16x16_lfnst1_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_16x16_lfnst1_golden.hex");
        run_test("dct2_16x32_lfnst1", 7'd16, 7'd32, 2'd0, 2'd0, 2'd0, 2'd1,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_16x32_lfnst1_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_16x32_lfnst1_golden.hex");
        run_test("dct2_32x16_lfnst1", 7'd32, 7'd16, 2'd0, 2'd0, 2'd0, 2'd1,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_32x16_lfnst1_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_32x16_lfnst1_golden.hex");
        run_test("dct2_32x32_lfnst1", 7'd32, 7'd32, 2'd0, 2'd0, 2'd0, 2'd1,
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_32x32_lfnst1_input.hex",
                 "D:/Workspace/its_vvc/tb/test_vectors/dct2_32x32_lfnst1_golden.hex");

        // ============================
        // Summary
        // ============================
        $display("\n========================================");
        $display("Test Summary: %0d passed, %0d failed (total %0d)", test_pass, test_fail, total_tests);
        $display("========================================");

        if (test_fail == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("SOME TESTS FAILED!");

        $finish;
    end

    // Global timeout watchdog
    initial begin
        #2000000000;
        $display("\nGLOBAL TIMEOUT!");
        $finish;
    end

endmodule
