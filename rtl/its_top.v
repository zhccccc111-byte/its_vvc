// ===================================================================
// ⚠ LEGACY — 本文件已冻结，不作为最终提交顶层。                        ⚠
// ⚠ 最终提交入口为 its_top_500_singleclk.v (v5.8.1, 1539/1539 PASS)。   ⚠
// ⚠ 此模块仍使用 v5.5 水平优先变换顺序 (row_tr_type=tr_type_hor)，     ⚠
// ⚠ 与 v5.6+ 官方 Q&A 要求的垂直优先不一致。仅保留作为 Artix-7 基线。   ⚠
// ===================================================================
// ITS Top Level Module - With LFNST integration (v5.5 LEGACY)
// 22-bit it_info interface per competition spec
// ===================================================================

`include "its_pkg.v"

module its_top (
    input  wire        clk,
    input  wire        rst_n,

    // Info interface (22-bit per competition spec)
    input  wire [21:0] it_info,
    input  wire        it_info_vld,

    // Data input
    input  wire [15:0] it_data_in,
    input  wire [11:0] it_data_addr,
    input  wire        it_data_in_vld,
    input  wire        it_data_end,
    output wire        it_data_in_req,

    // Data output
    output wire [39:0] it_data_out,
    output wire        it_data_out_vld,
    input  wire        it_data_out_req,

    // Done
    output wire        it_done
);

    // ========================================
    // Control signals
    // ========================================
    reg [6:0]  tu_width;
    reg [6:0]  tu_height;
    reg [1:0]  tr_type_hor;
    reg [1:0]  tr_type_ver;
    reg [1:0]  lfnst_tr_set_idx;
    reg [1:0]  lfnst_idx;
    reg [12:0] total_points;

    // State machine (from its_pkg)
    import its_pkg::*;

    reg [3:0] state;
    reg        out_pipe_flush;  // delays S_OUT→S_DONE by 1 cycle for sync read

    // Memory clear control
    reg        clearing;
    reg [11:0] clr_cnt;

    // Input buffer
    reg signed [15:0] in_mem [0:4095];
    reg [11:0] in_wr_cnt;

    // Row/Column loop counters
    reg [6:0]  row_idx;
    reg [6:0]  col_idx;
    reg [11:0] row_base_addr;

    // Engine address signals
    reg [11:0] row_eng_rd_addr;
    reg [11:0] col_eng_rd_addr;

    // Row engine signals
    wire [15:0] row_out_data;
    wire        row_out_vld;
    wire        row_done;
    wire        row_data_in_req;
    wire [13:0] row_rom_addr;
    wire [15:0] row_rom_coeff;

    // Column engine signals
    wire [15:0] col_out_data;
    wire        col_out_vld;
    wire        col_done;
    wire        col_data_in_req;
    wire [13:0] col_rom_addr;
    wire [15:0] col_rom_coeff;

    // Transpose buffer
    reg signed [15:0] tp_buf [0:4095];
    reg [11:0] tp_wr_cnt;
    reg [11:0] tp_rd_base;

    // Output reorder buffer
    reg signed [9:0] out_mem [0:4095];
    // out_row_cnt / out_col_cnt removed — debug-only, unused by logic

    // Output control
    reg [12:0] out_cnt;
    reg [39:0] data_out_r;  // pipeline register for out_mem read

    // ========================================
    // LFNST signals
    // ========================================
    // Trigger LFNST when input times out and lfnst_idx != 0
    wire        lfnst_start = (state == S_LOAD && it_data_end && lfnst_idx != 2'd0);
    wire [15:0] lfnst_data_out;
    wire        lfnst_data_out_vld;
    wire        lfnst_data_out_wr_en;
    wire        lfnst_done;
    wire        lfnst_data_in_req;

    // LFNST sub-block parameters (official VVC definition)
    // nTrs = (tu_width >= 8 && tu_height >= 8) ? 48 : 16
    wire        lfnst_ntrs_is_48 = (tu_width >= 7'd8 && tu_height >= 7'd8);
    wire [5:0]  lfnst_ntrs = lfnst_ntrs_is_48 ? 6'd48 : 6'd16;

    // LFNST read/write addresses (6-bit for nTrs=48)
    reg [5:0]  lfnst_rd_addr;
    reg [5:0]  lfnst_wr_addr;

    // LFNST read address: top-left 4x4 of TU
    // For nTrs=16: tu_width=4, sequential read = rd_addr[3:0]
    // For nTrs=48: tu_width>=8, read 16 elements row-major from top-left 4x4
    //   row = rd_addr[3:2], col = rd_addr[1:0], addr = row * tu_width + col
    //   row * tu_width replaced with shift (tu_width is always power of 2)
    wire [1:0]  lfnst_rd_row = lfnst_rd_addr[3:2];
    wire [1:0]  lfnst_rd_col = lfnst_rd_addr[1:0];

    wire [11:0] lfnst_rd_mem_addr = lfnst_ntrs_is_48 ?
                    (row_times_width(lfnst_rd_row, tu_width) + {10'd0, lfnst_rd_col}) :
                    {6'd0, lfnst_rd_addr[3:0]};

    // LFNST write-back address computation for nTrs=48
    // 3 sub-blocks: blk0(rows 0-3, cols 0-3), blk1(rows 0-3, cols 4-7), blk2(rows 4-7, cols 0-3)
    wire [1:0]  lfnst_blk = lfnst_wr_addr[5:4];
    wire [1:0]  lfnst_row_in_blk = lfnst_wr_addr[3:2];
    wire [1:0]  lfnst_col_in_blk = lfnst_wr_addr[1:0];
    wire [2:0]  lfnst_row48 = {1'b0, lfnst_row_in_blk} + (lfnst_blk == 2'd2 ? 3'd4 : 3'd0);
    wire [2:0]  lfnst_col48 = {1'b0, lfnst_col_in_blk} + (lfnst_blk == 2'd1 ? 3'd4 : 3'd0);

    wire [11:0] lfnst_wr_mem_addr = lfnst_ntrs_is_48 ?
                    (row48_times_width(lfnst_row48, tu_width) + {9'd0, lfnst_col48}) :
                    {6'd0, lfnst_wr_addr};

    // LFNST ROM signals (13-bit for 8192 entries)
    wire [12:0] lfnst_rom_addr;
    wire [15:0] lfnst_rom_coeff;

    // VVC standard: when LFNST is active, main transform must be DCT2
    wire        lfnst_active = (lfnst_idx != 2'd0);
    // ⚠ LEGACY: v5.5 horizontal-first order.  v5.6+ uses vertical-first
    // (row_tr_type=tr_type_ver, col_tr_type=tr_type_hor).  See its_core_500.v.
    wire [1:0]  row_tr_type = lfnst_active ? 2'd0 : tr_type_hor;
    wire [1:0]  col_tr_type = lfnst_active ? 2'd0 : tr_type_ver;

    // ========================================
    // Info decode (22-bit interface)
    // ========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tu_width         <= 7'd0;
            tu_height        <= 7'd0;
            tr_type_hor      <= 2'd0;
            tr_type_ver      <= 2'd0;
            lfnst_tr_set_idx <= 2'd0;
            lfnst_idx        <= 2'd0;
            total_points     <= 13'd0;
        end else if (it_info_vld) begin
            tu_width         <= it_info[6:0];
            tu_height        <= it_info[13:7];
            tr_type_hor      <= it_info[15:14];
            tr_type_ver      <= it_info[17:16];
            lfnst_tr_set_idx <= it_info[19:18];
            lfnst_idx        <= it_info[21:20];
            total_points     <= it_info[6:0] * it_info[13:7];
        end
    end

    // ========================================
    // Input buffer
    // ========================================
    assign it_data_in_req = (state == S_LOAD);

    integer i;
    initial begin
        for (i = 0; i < 4096; i = i + 1)
            in_mem[i] = 16'sd0;
        for (i = 0; i < 4096; i = i + 1)
            tp_buf[i] = 16'sd0;
        for (i = 0; i < 4096; i = i + 1)
            out_mem[i] = 10'sd0;
        clearing = 1'b0;
        clr_cnt  = 12'd0;
    end

    // in_mem write port (no async reset for Block RAM inference)
    // Write sources: S_CLEAR (zeroing), S_LOAD (input data), S_LFNST (LFNST write-back)
    // These are mutually exclusive states.
    always @(posedge clk) begin
        if (clearing) begin
            in_mem[clr_cnt] <= 16'sd0;
        end else if (state == S_LOAD && it_data_in_vld && it_data_in_req) begin
            in_mem[it_data_addr] <= it_data_in;
        end else if (lfnst_data_out_wr_en) begin
            in_mem[lfnst_wr_mem_addr] <= lfnst_data_out;
        end
    end

    // Input write counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_wr_cnt <= 12'd0;
        end else if (it_info_vld) begin
            in_wr_cnt <= 12'd0;
        end else if (state == S_LOAD && it_data_in_vld && it_data_in_req) begin
            in_wr_cnt <= in_wr_cnt + 12'd1;
        end
    end

    // ========================================
    // ROM Instantiation (shared: row/col engines are strictly sequential)
    // ========================================
    wire        is_col_phase = (state == S_COL_START || state == S_COL_RUN);
    wire [13:0] shared_rom_addr = is_col_phase ? col_rom_addr : row_rom_addr;
    wire [15:0] shared_rom_coeff;

    its_rom u_shared_rom (
        .clk   (clk),
        .addr  (shared_rom_addr),
        .coeff (shared_rom_coeff)
    );

    // Route shared ROM output to both engines
    assign row_rom_coeff = shared_rom_coeff;
    assign col_rom_coeff = shared_rom_coeff;

    // LFNST ROM
    its_lfnst_rom u_lfnst_rom (
        .clk   (clk),
        .addr  (lfnst_rom_addr),
        .coeff (lfnst_rom_coeff)
    );

    // ========================================
    // LFNST Module
    // ========================================
    its_lfnst u_lfnst (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (lfnst_start),
        .lfnst_idx       (lfnst_idx),
        .lfnst_tr_set_idx(lfnst_tr_set_idx),
        .tu_width        (tu_width),
        .tu_height       (tu_height),
        .data_in         (in_mem[lfnst_rd_mem_addr]),
        .data_in_vld     (state == S_LFNST && lfnst_data_in_req),
        .data_in_req     (lfnst_data_in_req),
        .data_out        (lfnst_data_out),
        .data_out_vld    (lfnst_data_out_vld),
        .data_out_wr_en  (lfnst_data_out_wr_en),
        .data_out_req    (1'b1),
        .done            (lfnst_done),
        // LFNST ROM interface
        .rom_addr        (lfnst_rom_addr),
        .rom_coeff       (lfnst_rom_coeff)
    );

    // LFNST read address (6-bit for nTrs=48 support)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            lfnst_rd_addr <= 6'd0;
        else if (state == S_LFNST && lfnst_data_in_req)
            lfnst_rd_addr <= lfnst_rd_addr + 6'd1;
        else if (state != S_LFNST)
            lfnst_rd_addr <= 6'd0;
    end

    // LFNST write-back address counter
    // (in_mem write is in the merged write block above)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            lfnst_wr_addr <= 6'd0;
        else if (lfnst_data_out_wr_en)
            lfnst_wr_addr <= lfnst_wr_addr + 6'd1;
        else if (state != S_LFNST)
            lfnst_wr_addr <= 6'd0;
    end

    // ========================================
    // Memory clear control
    // Clears in_mem[0..total_points-1] at the start of each TU.
    // Uses total_points (not 4096) to minimize clearing latency.
    // For 64x64: total_points[11:0]-1 = 4095, clears all 4096 entries.
    // For 4x4: total_points[11:0]-1 = 15, clears only 16 entries.
    // ========================================
    wire [11:0] clr_limit = total_points[11:0] - 12'd1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clearing <= 1'b0;
            clr_cnt  <= 12'd0;
        end else if (state == S_IDLE && it_info_vld) begin
            clearing <= 1'b1;
            clr_cnt  <= 12'd0;
        end else if (clearing) begin
            if (clr_cnt == clr_limit)
                clearing <= 1'b0;
            else
                clr_cnt <= clr_cnt + 12'd1;
        end
    end

    // ========================================
    // Main state machine
    // ========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else case (state)
            S_IDLE: begin
                if (it_info_vld) state <= S_CLEAR;
            end
            S_CLEAR: begin
                if (clr_cnt == clr_limit) state <= S_LOAD;
            end
            S_LOAD: begin
                if (it_data_end) begin
                    if (lfnst_idx != 2'd0)
                        state <= S_LFNST;
                    else
                        state <= S_ROW_START;
                end
            end
            S_LFNST: begin
                if (lfnst_done) state <= S_ROW_START;
            end
            S_ROW_START: begin
                state <= S_ROW_RUN;
            end
            S_ROW_RUN: begin
                if (row_done) begin
                    if (row_idx + 7'd1 >= tu_height[6:0])
                        state <= S_COL_START;
                    else
                        state <= S_ROW_START;
                end
            end
            S_COL_START: begin
                state <= S_COL_RUN;
            end
            S_COL_RUN: begin
                if (col_done) begin
                    if (col_idx + 7'd1 >= tu_width[6:0]) begin
                        state <= S_OUT;
                    end else
                        state <= S_COL_START;
                end
            end
            S_OUT: begin
                if (total_points == 0)
                    state <= S_DONE;
                else if (out_pipe_flush && it_data_out_req)
                    state <= S_DONE;
            end
            S_DONE: state <= S_IDLE;
            default: state <= S_IDLE;
        endcase
    end

    // ========================================
    // Row/Column loop counters
    // ========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_idx       <= 7'd0;
            row_base_addr <= 12'd0;
        end else if (state == S_LFNST && lfnst_done) begin
            row_idx       <= 7'd0;
            row_base_addr <= 12'd0;
        end else if (state == S_LOAD && it_data_end && lfnst_idx == 2'd0) begin
            row_idx       <= 7'd0;
            row_base_addr <= 12'd0;
        end else if (state == S_ROW_RUN && row_done && row_idx + 7'd1 < tu_height[6:0]) begin
            row_idx       <= row_idx + 7'd1;
            row_base_addr <= row_base_addr + {5'd0, tu_width[6:0]};
        end else if (state != S_ROW_START && state != S_ROW_RUN && state != S_LFNST) begin
            row_idx       <= 7'd0;
            row_base_addr <= 12'd0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_idx     <= 7'd0;
            tp_rd_base  <= 12'd0;
        end else if (state == S_ROW_RUN && row_done && row_idx + 7'd1 >= tu_height[6:0]) begin
            col_idx     <= 7'd0;
            tp_rd_base  <= 12'd0;
        end else if (state == S_COL_RUN && col_done && col_idx + 7'd1 < tu_width[6:0]) begin
            col_idx    <= col_idx + 7'd1;
            tp_rd_base <= 12'd0;  // column offset handled by col_eng_rd_addr
        end else if (state != S_COL_START && state != S_COL_RUN) begin
            col_idx     <= 7'd0;
            tp_rd_base  <= 12'd0;
        end
    end

    // ========================================
    // Row Transform Engine
    // ========================================
    its_transform_engine u_row_engine (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (state == S_ROW_START),
        .tr_type    (row_tr_type),
        .size       (tu_width[6:0]),
        .data_in    (in_mem[row_base_addr + row_eng_rd_addr]),
        .data_in_vld(state == S_ROW_RUN),
        .data_in_req(row_data_in_req),
        .rom_addr   (row_rom_addr),
        .rom_coeff  (row_rom_coeff),
        .data_out   (row_out_data),
        .data_out_vld(row_out_vld),
        .data_out_req(1'b1),
        .done       (row_done)
    );

    // Row engine read address
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            row_eng_rd_addr <= 12'd0;
        else if (state == S_ROW_START)
            row_eng_rd_addr <= 12'd0;
        else if (state == S_ROW_RUN && row_data_in_req)
            row_eng_rd_addr <= row_eng_rd_addr + 12'd1;
        else if (state != S_ROW_RUN)
            row_eng_rd_addr <= 12'd0;
    end

    // ========================================
    // Transpose Buffer Write
    // Row engine outputs row-major: result[row][0..W-1]
    // Write SEQUENTIALLY to tp_buf (row-major layout):
    //   Row 0 at [0..W-1], Row 1 at [W..2W-1], etc.
    // Column engine reads with stride W to get column data.
    // ========================================
    // tp_col_cnt removed — debug-only, unused by logic

    // tp_buf write (no async reset for Block RAM inference)
    always @(posedge clk) begin
        if (state == S_ROW_RUN && row_out_vld)
            tp_buf[tp_wr_cnt] <= row_out_data;
    end

    // tp_buf write pointer (control reg, async reset OK)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tp_wr_cnt <= 12'd0;
        end else if (it_info_vld) begin
            tp_wr_cnt <= 12'd0;
        end else if (state == S_ROW_RUN && row_out_vld) begin
            tp_wr_cnt <= tp_wr_cnt + 12'd1;
        end
    end

    // ========================================
    // Column Transform Engine
    // ========================================
    its_transform_engine u_col_engine (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (state == S_COL_START),
        .tr_type    (col_tr_type),
        .size       (tu_height[6:0]),
        .data_in    (tp_buf[tp_rd_base + col_eng_rd_addr]),
        .data_in_vld(state == S_COL_RUN),
        .data_in_req(col_data_in_req),
        .rom_addr   (col_rom_addr),
        .rom_coeff  (col_rom_coeff),
        .data_out   (col_out_data),
        .data_out_vld(col_out_vld),
        .data_out_req(1'b1),
        .done       (col_done)
    );

    // Column engine read address
    // Row engine writes sequentially (row-major): result[row][col] at row*W+col
    // Column c data at tp_buf[c, c+W, c+2W, ...] (stride = tu_width)
    // tp_rd_base = col_idx * tu_height (unused with sequential layout)
    // Read with stride tu_width to get column data
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            col_eng_rd_addr <= 12'd0;
        else if (state == S_COL_START)
            col_eng_rd_addr <= {6'd0, col_idx[6:0]};  // start at column offset
        else if (state == S_COL_RUN && col_data_in_req)
            col_eng_rd_addr <= col_eng_rd_addr + {5'd0, tu_width[6:0]};
        else if (state != S_COL_RUN)
            col_eng_rd_addr <= 12'd0;
    end

    // ========================================
    // Output Control (pipelined, synchronous read)
    // out_mem written in row-major order by column engine.
    // Read port: synchronous (posedge clk) for Block RAM inference.
    // Single-stage pipeline: out_cnt -> out_mem sync read -> data_out_r (1 cycle)
    // The synchronous read breaks the BRAM→OBUF critical path into two stages.
    // ========================================

    // Read address generation (advance when not backpressured and more data to read)
    wire [11:0] out_rd0 = out_cnt;
    wire [11:0] out_rd1 = out_cnt + 12'd1;
    wire [11:0] out_rd2 = out_cnt + 12'd2;
    wire [11:0] out_rd3 = out_cnt + 12'd3;

    // Pipeline flush flag: delays S_OUT→S_DONE by 1 cycle for synchronous read.
    // When out_cnt reaches total_points, the last sync read has started.
    // We need 1 more cycle for data_out_r to capture it before leaving S_OUT.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            out_pipe_flush <= 1'b0;
        else if (state != S_OUT)
            out_pipe_flush <= 1'b0;
        else if (it_data_out_req && out_cnt >= total_points && total_points != 0)
            out_pipe_flush <= 1'b1;
    end

    // Synchronous read port — single-stage pipeline for Block RAM inference.
    // 1 cycle latency: address at cycle N, data_out_r valid at cycle N+1.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            data_out_r <= 40'd0;
        else if (state == S_OUT && it_data_out_req && out_cnt < total_points)
            data_out_r <= {out_mem[out_rd3], out_mem[out_rd2], out_mem[out_rd1], out_mem[out_rd0]};
    end

    // Output valid — tracks state == S_OUT with same 1-cycle latency as data_out_r.
    // Both data_out_valid and data_out_r are registered, so they're synchronized.
    // When leaving S_OUT, holds 1 extra cycle so TB can capture the last batch.
    reg data_out_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            data_out_valid <= 1'b0;
        else if (state == S_OUT)
            data_out_valid <= 1'b1;
        else if (state == S_DONE && data_out_valid)
            data_out_valid <= 1'b1;  // hold 1 cycle for last batch
        else
            data_out_valid <= 1'b0;
    end

    // Registered output
    assign it_data_out = data_out_r;
    assign it_data_out_vld = data_out_valid && it_data_out_req;
    assign it_done = (state == S_DONE);

    // out_mem write port — separate always block for Block RAM inference.
    // Write in row-major order: for column j, row i, addr = col_idx + row * tu_width.
    reg [11:0] out_mem_wr_addr;
    always @(posedge clk) begin
        if (state == S_COL_RUN && col_out_vld)
            out_mem[out_mem_wr_addr] <= col_out_data[9:0];
    end

    // out_mem write address (row-major: col_idx + row * tu_width)
    always @(posedge clk) begin
        if (!rst_n || it_info_vld)
            out_mem_wr_addr <= 12'd0;
        else if (state == S_COL_START)
            out_mem_wr_addr <= {5'd0, col_idx[6:0]};  // start at column offset
        else if (state == S_COL_RUN && col_out_vld)
            out_mem_wr_addr <= out_mem_wr_addr + {5'd0, tu_width[6:0]};  // stride = tu_width
    end

    // out_row_cnt / out_col_cnt always block removed — debug-only

    // Output counter (synchronous reset to avoid DRC with block RAM address)
    // Increment when in S_OUT, req is high, and more data to output.
    always @(posedge clk) begin
        if (!rst_n || state != S_OUT)
            out_cnt <= 13'd0;
        else if (it_data_out_req && out_cnt < total_points)
            out_cnt <= out_cnt + 13'd4;
    end

endmodule
