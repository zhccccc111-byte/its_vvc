// ===================================================================
// ITS LFNST Inverse Transform Module
// Performs LFNST inverse transform before main IDCT/IDST
//
// nTrs = (tu_width >= 8 && tu_height >= 8) ? 48 : 16
// nTrs=16: 16 inputs, 16x16 matrix, 16 outputs
// nTrs=48: 16 inputs, 48x16 matrix, 48 outputs
//
// Formula: y[i] = clip3(-32768, 32767, (sum_j(T[i][j]*x[j]) + 64) >> 7)
//
// ROM layout (8192 entries, 13-bit address):
//   nTrs=16 [0..2047]:   4 setIdx x 2 idx x 16x16
//   nTrs=48 [2048..8191]: 4 setIdx x 2 idx x 48x16
// ===================================================================

module its_lfnst (
    input  wire        clk,
    input  wire        rst_n,

    // Control
    input  wire        start,
    input  wire [1:0]  lfnst_idx,        // 1 or 2 (0 means no LFNST)
    input  wire [1:0]  lfnst_tr_set_idx, // 0..3
    input  wire [6:0]  tu_width,
    input  wire [6:0]  tu_height,

    // Data input
    input  wire [15:0] data_in,
    input  wire        data_in_vld,
    output reg         data_in_req,

    // Data output
    output reg  [15:0] data_out,
    output reg         data_out_vld,
    output reg         data_out_wr_en,
    input  wire        data_out_req,

    // Status
    output reg         done,

    // LFNST ROM interface
    output reg  [12:0] rom_addr,
    input  wire [15:0] rom_coeff
);

    // ========================================
    // State machine
    // ========================================
    localparam S_IDLE     = 3'd0;
    localparam S_LOAD     = 3'd1;
    localparam S_PREFETCH = 3'd2;
    localparam S_COMPUTE  = 3'd3;
    localparam S_DRAIN    = 3'd4;
    localparam S_OUTPUT   = 3'd5;
    localparam S_DONE     = 3'd6;

    reg [2:0] state;

    // ========================================
    // nTrs calculation (official VVC definition)
    // ========================================
    wire ntrs_is_48 = (tu_width >= 7'd8 && tu_height >= 7'd8);
    wire [5:0] ntrs = ntrs_is_48 ? 6'd48 : 6'd16;

    // ========================================
    // ROM address layout
    // ========================================
    reg [12:0] rom_base;
    wire [1:0] lfnst_idx_m1 = lfnst_idx - 2'd1;
    always @(*) begin
        if (!ntrs_is_48)
            rom_base = {11'd0, lfnst_tr_set_idx} * 13'd512
                     + {12'd0, lfnst_idx_m1[0]} * 13'd256;
        else
            rom_base = 13'd2048
                     + ({11'd0, lfnst_tr_set_idx} * 13'd2 + {12'd0, lfnst_idx_m1[0]}) * 13'd768;
    end

    // ========================================
    // Buffers
    // ========================================
    reg [15:0] in_buf [0:15];
    reg [5:0]  load_cnt;
    reg [3:0]  load_idle_cnt;  // Timeout for sparse input

    // Coefficient buffer: max 48x16 = 768 entries
    reg signed [15:0] coeff_buf [0:767];

    // ========================================
    // Pre-fetch control
    // ROM has 1-cycle read latency.
    // pf_cnt tracks how many entries have been written to coeff_buf.
    // ROM address is always 1 ahead of coeff_buf write address.
    // ========================================
    reg [9:0]  pf_cnt;           // Pipeline counter: 0..pf_total
    reg        pf_active;        // Prefetch is active

    // ========================================
    // MAC unit
    // ========================================
    reg        mac_en;
    reg        mac_clr;
    reg [15:0] mac_a;
    reg [15:0] mac_b;
    wire [39:0] mac_result;
    wire        mac_valid;

    its_mac u_mac (
        .clk    (clk),
        .rst_n  (rst_n),
        .en     (mac_en),
        .clr    (mac_clr),
        .a      (mac_a),
        .b      (mac_b),
        .result (mac_result),
        .valid  (mac_valid)
    );

    // ========================================
    // Compute counters
    // ========================================
    reg [3:0]  mac_cnt;
    reg [5:0]  comp_cnt;
    reg [1:0]  drain_cnt;
    reg        first_compute;  // Flag for first compute cycle (pipeline flush)

    // ========================================
    // State machine
    // ========================================
    // Prefetch takes ntrs*16 cycles + 1 for ROM pipeline flush
    wire [9:0] pf_total = {4'd0, ntrs, 4'd0}; // ntrs * 16
    wire       pf_done = (pf_cnt >= pf_total);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else case (state)
            S_IDLE:     if (start) state <= S_LOAD;
            S_LOAD:     if (load_cnt >= 6'd15 && data_in_vld) state <= S_PREFETCH;
                        else if (load_idle_cnt >= 4'd15 && load_cnt > 6'd0) state <= S_PREFETCH;
            S_PREFETCH: if (pf_cnt >= pf_total && !pf_active)
                            state <= S_COMPUTE;
            S_COMPUTE:  if (mac_cnt == 4'd15 && mac_en)
                            state <= S_DRAIN;
            S_DRAIN:    if (drain_cnt == 2'd2)
                            state <= S_OUTPUT;
            S_OUTPUT:   begin
                            if (comp_cnt >= ntrs)
                                state <= S_DONE;
                            else
                                state <= S_COMPUTE;
                        end
            S_DONE:     state <= S_IDLE;
            default:    state <= S_IDLE;
        endcase
    end

    // ========================================
    // Input load (sparse: only non-zero points)
    // ========================================
    wire load_done = (load_cnt >= 6'd15 && data_in_vld) ||
                     (load_idle_cnt >= 4'd15 && load_cnt > 6'd0);

    // in_buf write (no async reset for Block RAM inference)
    always @(posedge clk) begin
        if (state == S_LOAD && data_in_vld)
            in_buf[load_cnt[3:0]] <= data_in;
    end

    // Load control
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_cnt     <= 6'd0;
            load_idle_cnt <= 4'd0;
        end else if (state == S_IDLE && start) begin
            load_cnt     <= 6'd0;
            load_idle_cnt <= 4'd0;
        end else if (state == S_LOAD) begin
            if (data_in_vld) begin
                load_cnt <= load_cnt + 6'd1;
                load_idle_cnt <= 4'd0;
            end else if (load_cnt > 6'd0) begin
                load_idle_cnt <= load_idle_cnt + 4'd1;
            end
        end else begin
            load_idle_cnt <= 4'd0;
        end
    end

    // ========================================
    // Pre-fetch coefficients from ROM
    //
    // ROM pipeline: NBA sets rom_addr → ROM reads on next posedge → output on posedge after.
    // Total latency from setting rom_addr to valid rom_coeff: 2 cycles.
    //
    // Pipeline timeline:
    //   load_done (cycle 0): rom_addr <= rom_base. ROM reads rom[rom_base-1] (stale).
    //   Cycle 1 (pf_cnt=0):  ROM reads rom[rom_base]. No write (data not ready yet).
    //                        rom_addr <= rom_base+1. ROM will read rom[rom_base].
    //   Cycle 2 (pf_cnt=1):  rom_coeff = rom[rom_base] (valid from cycle 0).
    //                        Write coeff_buf[0]. rom_addr <= rom_base+2.
    //   Cycle 3 (pf_cnt=2):  rom_coeff = rom[rom_base+1]. Write coeff_buf[1].
    //   ...
    //   Cycle pf_total+1:    Write coeff_buf[pf_total-1]. Done.
    //
    // pf_cnt counts 0..pf_total. Writes happen at pf_cnt = 1..pf_total.
    // coeff_buf index = pf_cnt - 1.
    // ========================================

    // coeff_buf write (no async reset for Block RAM inference)
    always @(posedge clk) begin
        if (state == S_PREFETCH && pf_active && pf_cnt >= 10'd1)
            coeff_buf[pf_cnt - 10'd1] <= rom_coeff;
    end

    // Pre-fetch control
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pf_cnt    <= 10'd0;
            pf_active <= 1'b0;
            rom_addr  <= 13'd0;
        end else if (state == S_LOAD && load_done) begin
            pf_cnt    <= 10'd0;
            pf_active <= 1'b1;
            rom_addr  <= rom_base;     // Start ROM pipeline
        end else if (state == S_PREFETCH && pf_active) begin
            pf_cnt <= pf_cnt + 10'd1;
            if (pf_cnt >= pf_total) begin
                // Last entry written this cycle
                pf_active <= 1'b0;
            end else begin
                // Advance ROM address for next read
                rom_addr <= rom_base + {3'd0, pf_cnt} + 13'd1;
            end
        end
    end

    // ========================================
    // MAC compute: y[n] = sum_j(T[n][j] * x[j])
    // coeff_buf address = comp_cnt * 16 + mac_cnt = T[comp_cnt][mac_cnt]
    // For nTrs=48, comp_cnt can be 0..47, need 6-bit row index
    // ========================================
    wire [9:0] coeff_buf_rd_addr = {comp_cnt[5:0], 4'd0} + {4'd0, mac_cnt[3:0]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mac_cnt       <= 4'd0;
            comp_cnt      <= 6'd0;
            mac_en        <= 1'b0;
            mac_clr       <= 1'b0;
            mac_a         <= 16'd0;
            mac_b         <= 16'd0;
            first_compute <= 1'b0;
        end else if (state == S_LOAD && load_done) begin
            mac_cnt  <= 4'd0;
            comp_cnt <= 6'd0;
            mac_clr  <= 1'b1;
            first_compute <= 1'b1;
        end else if (state == S_COMPUTE) begin
            // Keep clr for 1 cycle to flush pipeline (load_done added extra cycle)
            mac_a   <= in_buf[mac_cnt];
            mac_b   <= coeff_buf[coeff_buf_rd_addr];
            mac_en  <= 1'b1;
            if (first_compute) begin
                mac_clr      <= 1'b1;
                first_compute <= 1'b0;
            end else begin
                mac_clr <= 1'b0;
            end

            if (mac_cnt >= 4'd15) begin
                mac_cnt  <= 4'd0;
                comp_cnt <= comp_cnt + 6'd1;
            end else begin
                mac_cnt <= mac_cnt + 4'd1;
            end
        end else if (state == S_DRAIN) begin
            mac_en  <= 1'b0;
            mac_clr <= 1'b0;
        end else if (state == S_OUTPUT) begin
            mac_clr <= 1'b1;
            mac_en  <= 1'b0;
            mac_cnt <= 4'd0;
        end else begin
            mac_en  <= 1'b0;
            mac_clr <= 1'b0;
        end
    end

    // ========================================
    // Drain counter: wait for MAC pipeline to flush
    // ========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            drain_cnt <= 2'd0;
        else if (state == S_DRAIN)
            drain_cnt <= drain_cnt + 2'd1;
        else
            drain_cnt <= 2'd0;
    end

    // ========================================
    // Output: capture result after drain, clip and write
    // ========================================
    reg signed [39:0] captured_result;
    reg signed [39:0] shifted;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            captured_result <= 40'd0;
        else if (state == S_DRAIN && drain_cnt == 2'd2)
            captured_result <= mac_result;
    end

    always @(*) begin
        shifted = (captured_result + 40'sd64) >>> 7;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out       <= 16'd0;
            data_out_vld   <= 1'b0;
            data_out_wr_en <= 1'b0;
            done           <= 1'b0;
        end else if (state == S_IDLE && start) begin
            done <= 1'b0;
        end else if (state == S_OUTPUT) begin
            if ($signed(shifted) > 40'sd32767)
                data_out <= 16'h7FFF;
            else if ($signed(shifted) < -40'sd32768)
                data_out <= 16'h8000;
            else
                data_out <= shifted[15:0];
            data_out_vld   <= 1'b1;
            data_out_wr_en <= 1'b1;
            if (comp_cnt >= ntrs)
                done <= 1'b1;
        end else if (state == S_DONE) begin
            data_out_vld   <= 1'b0;
            data_out_wr_en <= 1'b0;
            done           <= 1'b1;
        end else begin
            data_out_vld   <= 1'b0;
            data_out_wr_en <= 1'b0;
        end
    end

    // ========================================
    // Input request
    // ========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            data_in_req <= 1'b0;
        else
            data_in_req <= (state == S_LOAD);
    end

endmodule
