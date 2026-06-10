// ===================================================================
// ITS Core 500MHz - Compute core for dual-clock architecture
// Functionally equivalent to its_top with FIFO-based I/O interface.
//
// FIFO Protocol:
//   cmd_fifo:   FWFT (First Word Fall Through), 23-bit, depth 4
//               [22]=reserved(0), [21:0]=it_info
//               Core reads 1 entry per TU in S_IDLE. No end marker.
//
//   input_fifo: FWFT, 29-bit, depth 16
//               [28]=last, [27:16]=it_data_addr, [15:0]=it_data_in
//               Data available when !empty. Core reads 1 entry/cycle.
//               last=1 marks final entry of current TU (pure control signal, no data).
//
//   output_fifo: Standard write (registered), 40-bit, depth 16
//                [39:0]=4x10-bit output. wr_en pulses with valid data.
//                Full backpressures core output stage.
//
// All I/O ports registered. No OBUF/IOB paths.
// ROMs instantiated internally (synchronous read).
// ===================================================================

module its_core_500 (
    input  wire        clk_core,
    input  wire        rst_n,

    // Command FIFO interface — FWFT required
    input  wire [22:0] cmd_fifo_rdata,      // [21:0]=it_info, [22]=reserved(0)
    input  wire        cmd_fifo_empty,       // FWFT: data valid when !empty
    output wire        cmd_fifo_rd_en,       // pulse: consume 1 entry

    // Input data FIFO interface — FWFT required
    input  wire [28:0] input_fifo_rdata,     // [28]=last, [27:16]=addr, [15:0]=coeff
    input  wire        input_fifo_empty,      // FWFT: data valid when !empty
    output wire        input_fifo_rd_en,      // pulse: consume 1 entry

    // Output data FIFO interface — standard write
    output reg  [39:0] output_fifo_wdata,    // 4x10-bit output
    output reg         output_fifo_wr_en,    // pulse: write 1 entry
    input  wire        output_fifo_full,
    input  wire        output_fifo_almost_full,

    // Status
    output reg         core_done             // TU completion pulse
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

    // State machine
    localparam S_IDLE      = 4'd0;
    localparam S_LOAD      = 4'd1;
    localparam S_ROW_START = 4'd2;
    localparam S_ROW_RUN   = 4'd3;
    localparam S_COL_START = 4'd4;
    localparam S_COL_RUN   = 4'd5;
    localparam S_OUT       = 4'd6;
    localparam S_DONE      = 4'd7;
    localparam S_LFNST     = 4'd8;
    localparam S_CLEAR     = 4'd9;

    reg [3:0] state;
    reg        out_pipe_flush;
    reg        out_valid_pipe;

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
    reg [6:0]  out_row_cnt;
    reg [6:0]  out_col_cnt;

    // Output control
    reg [12:0] out_cnt;
    reg [39:0] data_out_r;

    // ========================================
    // LFNST signals
    // ========================================
    wire [15:0] lfnst_data_out;
    wire        lfnst_data_out_vld;
    wire        lfnst_data_out_wr_en;
    wire        lfnst_done;
    wire        lfnst_data_in_req;

    wire        lfnst_ntrs_is_48 = (tu_width >= 7'd8 && tu_height >= 7'd8);
    wire [5:0]  lfnst_ntrs = lfnst_ntrs_is_48 ? 6'd48 : 6'd16;

    reg [5:0]  lfnst_rd_addr;
    reg [5:0]  lfnst_wr_addr;

    wire [1:0]  lfnst_rd_row = lfnst_rd_addr[3:2];
    wire [1:0]  lfnst_rd_col = lfnst_rd_addr[1:0];
    wire [11:0] lfnst_rd_mem_addr = lfnst_ntrs_is_48 ?
                    ({6'd0, lfnst_rd_row} * {5'd0, tu_width} + {10'd0, lfnst_rd_col}) :
                    {6'd0, lfnst_rd_addr[3:0]};

    wire [1:0]  lfnst_blk = lfnst_wr_addr[5:4];
    wire [1:0]  lfnst_row_in_blk = lfnst_wr_addr[3:2];
    wire [1:0]  lfnst_col_in_blk = lfnst_wr_addr[1:0];
    wire [2:0]  lfnst_row48 = {1'b0, lfnst_row_in_blk} + (lfnst_blk == 2'd2 ? 3'd4 : 3'd0);
    wire [2:0]  lfnst_col48 = {1'b0, lfnst_col_in_blk} + (lfnst_blk == 2'd1 ? 3'd4 : 3'd0);
    wire [11:0] lfnst_wr_mem_addr = lfnst_ntrs_is_48 ?
                    ({6'd0, lfnst_row48} * {5'd0, tu_width} + {9'd0, lfnst_col48}) :
                    {6'd0, lfnst_wr_addr};

    wire [12:0] lfnst_rom_addr;
    wire [15:0] lfnst_rom_coeff;

    wire        lfnst_active = (lfnst_idx != 2'd0);
    wire [1:0]  row_tr_type = lfnst_active ? 2'd0 : tr_type_hor;
    wire [1:0]  col_tr_type = lfnst_active ? 2'd0 : tr_type_ver;

    // ========================================
    // Command FIFO read pipeline (registered)
    // Breaks combinational path: empty → rd_en → data decode
    // ========================================
    reg        cmd_fifo_rd_en_r;
    reg [22:0] cmd_fifo_data_r;

    // Assert rd_en: only in S_IDLE to read it_info (1 entry per TU)
    assign cmd_fifo_rd_en = (state == S_IDLE && !cmd_fifo_empty && !cmd_fifo_rd_en_r);

    always @(posedge clk_core or negedge rst_n) begin
        if (!rst_n) begin
            cmd_fifo_rd_en_r <= 1'b0;
            cmd_fifo_data_r  <= 23'd0;
        end else begin
            cmd_fifo_rd_en_r <= cmd_fifo_rd_en;
            if (cmd_fifo_rd_en && !cmd_fifo_empty)
                cmd_fifo_data_r <= cmd_fifo_rdata;
        end
    end

    // ========================================
    // Command FIFO decode (from registered pipeline)
    // ========================================
    always @(posedge clk_core or negedge rst_n) begin
        if (!rst_n) begin
            tu_width         <= 7'd0;
            tu_height        <= 7'd0;
            tr_type_hor      <= 2'd0;
            tr_type_ver      <= 2'd0;
            lfnst_tr_set_idx <= 2'd0;
            lfnst_idx        <= 2'd0;
            total_points     <= 13'd0;
        end else if (cmd_fifo_rd_en_r && state == S_IDLE) begin
            tu_width         <= cmd_fifo_data_r[6:0];
            tu_height        <= cmd_fifo_data_r[13:7];
            tr_type_hor      <= cmd_fifo_data_r[15:14];
            tr_type_ver      <= cmd_fifo_data_r[17:16];
            lfnst_tr_set_idx <= cmd_fifo_data_r[19:18];
            lfnst_idx        <= cmd_fifo_data_r[21:20];
            total_points     <= cmd_fifo_data_r[6:0] * cmd_fifo_data_r[13:7];
        end
    end

    // ========================================
    // Load end detection (from input_fifo last flag)
    // ========================================
    reg input_last_detected;
    always @(posedge clk_core or negedge rst_n) begin
        if (!rst_n)
            input_last_detected <= 1'b0;
        else if (state == S_IDLE)
            input_last_detected <= 1'b0;
        // last=1 in input_fifo[28]: final entry of current TU
        else if (state == S_LOAD && input_fifo_rd_en && !input_fifo_empty && input_fifo_rdata[28])
            input_last_detected <= 1'b1;
    end

    // LFNST start: same condition, using registered flag
    wire lfnst_start = (state == S_LOAD && input_last_detected && lfnst_idx != 2'd0);

    // ========================================
    // Input FIFO read (FWFT: data valid when !empty)
    // ========================================
    assign input_fifo_rd_en = (state == S_LOAD && !input_fifo_empty);

    // ========================================
    // Input buffer (async read, sync write — same as its_top)
    // ========================================
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

    // in_mem write port
    always @(posedge clk_core) begin
        if (clearing) begin
            in_mem[clr_cnt] <= 16'sd0;
        end else if (state == S_LOAD && input_fifo_rd_en && !input_fifo_empty && !input_fifo_rdata[28]) begin
            in_mem[input_fifo_rdata[27:16]] <= input_fifo_rdata[15:0];
        end else if (lfnst_data_out_wr_en) begin
            in_mem[lfnst_wr_mem_addr] <= lfnst_data_out;
        end
    end

    // Input write counter
    always @(posedge clk_core or negedge rst_n) begin
        if (!rst_n) begin
            in_wr_cnt <= 12'd0;
        end else if (cmd_fifo_rd_en_r) begin
            in_wr_cnt <= 12'd0;
        end else if (state == S_LOAD && input_fifo_rd_en && !input_fifo_empty && !input_fifo_rdata[28]) begin
            in_wr_cnt <= in_wr_cnt + 12'd1;
        end
    end

    // ========================================
    // ROM Instantiation
    // ========================================
    its_rom u_row_rom (
        .clk   (clk_core),
        .addr  (row_rom_addr),
        .coeff (row_rom_coeff)
    );

    its_rom u_col_rom (
        .clk   (clk_core),
        .addr  (col_rom_addr),
        .coeff (col_rom_coeff)
    );

    its_lfnst_rom u_lfnst_rom (
        .clk   (clk_core),
        .addr  (lfnst_rom_addr),
        .coeff (lfnst_rom_coeff)
    );

    // ========================================
    // LFNST Module
    // ========================================
    its_lfnst u_lfnst (
        .clk             (clk_core),
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
        .rom_addr        (lfnst_rom_addr),
        .rom_coeff       (lfnst_rom_coeff)
    );

    // LFNST read address
    always @(posedge clk_core or negedge rst_n) begin
        if (!rst_n)
            lfnst_rd_addr <= 6'd0;
        else if (state == S_LFNST && lfnst_data_in_req)
            lfnst_rd_addr <= lfnst_rd_addr + 6'd1;
        else if (state != S_LFNST)
            lfnst_rd_addr <= 6'd0;
    end

    // LFNST write-back address counter
    always @(posedge clk_core or negedge rst_n) begin
        if (!rst_n)
            lfnst_wr_addr <= 6'd0;
        else if (lfnst_data_out_wr_en)
            lfnst_wr_addr <= lfnst_wr_addr + 6'd1;
        else if (state != S_LFNST)
            lfnst_wr_addr <= 6'd0;
    end

    // ========================================
    // Memory clear control
    // ========================================
    wire [11:0] clr_limit = total_points[11:0] - 12'd1;

    always @(posedge clk_core or negedge rst_n) begin
        if (!rst_n) begin
            clearing <= 1'b0;
            clr_cnt  <= 12'd0;
        end else if (state == S_IDLE && cmd_fifo_rd_en_r) begin
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
    always @(posedge clk_core or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else case (state)
            S_IDLE: begin
                if (cmd_fifo_rd_en_r) state <= S_CLEAR;
            end
            S_CLEAR: begin
                if (clr_cnt == clr_limit) state <= S_LOAD;
            end
            S_LOAD: begin
                if (input_last_detected) begin
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
                else if (out_pipe_flush && !out_valid_pipe)
                    state <= S_DONE;
            end
            S_DONE: state <= S_IDLE;
            default: state <= S_IDLE;
        endcase
    end

    // ========================================
    // Row/Column loop counters
    // ========================================
    always @(posedge clk_core or negedge rst_n) begin
        if (!rst_n) begin
            row_idx       <= 7'd0;
            row_base_addr <= 12'd0;
        end else if (state == S_LFNST && lfnst_done) begin
            row_idx       <= 7'd0;
            row_base_addr <= 12'd0;
        end else if (state == S_LOAD && input_last_detected && lfnst_idx == 2'd0) begin
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

    always @(posedge clk_core or negedge rst_n) begin
        if (!rst_n) begin
            col_idx     <= 7'd0;
            tp_rd_base  <= 12'd0;
        end else if (state == S_ROW_RUN && row_done && row_idx + 7'd1 >= tu_height[6:0]) begin
            col_idx     <= 7'd0;
            tp_rd_base  <= 12'd0;
        end else if (state == S_COL_RUN && col_done && col_idx + 7'd1 < tu_width[6:0]) begin
            col_idx    <= col_idx + 7'd1;
            tp_rd_base <= 12'd0;
        end else if (state != S_COL_START && state != S_COL_RUN) begin
            col_idx     <= 7'd0;
            tp_rd_base  <= 12'd0;
        end
    end

    // ========================================
    // Row Transform Engine
    // ========================================
    its_transform_engine u_row_engine (
        .clk        (clk_core),
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

    always @(posedge clk_core or negedge rst_n) begin
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
    // ========================================
    reg [5:0] tp_col_cnt;

    always @(posedge clk_core) begin
        if (state == S_ROW_RUN && row_out_vld)
            tp_buf[tp_wr_cnt] <= row_out_data;
    end

    always @(posedge clk_core or negedge rst_n) begin
        if (!rst_n) begin
            tp_wr_cnt <= 12'd0;
            tp_col_cnt <= 6'd0;
        end else if (cmd_fifo_rd_en_r) begin
            tp_wr_cnt <= 12'd0;
            tp_col_cnt <= 6'd0;
        end else if (state == S_ROW_START) begin
            tp_col_cnt <= 6'd0;
        end else if (state == S_ROW_RUN && row_out_vld) begin
            tp_col_cnt <= tp_col_cnt + 6'd1;
            tp_wr_cnt <= tp_wr_cnt + 12'd1;
        end else if (state != S_ROW_START && state != S_ROW_RUN) begin
            tp_col_cnt <= 6'd0;
        end
    end

    // ========================================
    // Column Transform Engine
    // ========================================
    its_transform_engine u_col_engine (
        .clk        (clk_core),
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

    always @(posedge clk_core or negedge rst_n) begin
        if (!rst_n)
            col_eng_rd_addr <= 12'd0;
        else if (state == S_COL_START)
            col_eng_rd_addr <= {6'd0, col_idx[6:0]};
        else if (state == S_COL_RUN && col_data_in_req)
            col_eng_rd_addr <= col_eng_rd_addr + {5'd0, tu_width[6:0]};
        else if (state != S_COL_RUN)
            col_eng_rd_addr <= 12'd0;
    end

    // ========================================
    // Output Control — 3-stage pipeline with ready/valid hold
    // Stage 0: out_mem read (gated by backpressure)
    // Stage 1: data_out_r + out_valid_pipe (HOLDS when write can't fire)
    // Stage 2: FIFO write (write_fire = valid && !full)
    // out_cnt increments ONLY on write_fire — no data lost under backpressure.
    // ========================================
    wire [11:0] out_rd0 = out_cnt;
    wire [11:0] out_rd1 = out_cnt + 12'd1;
    wire [11:0] out_rd2 = out_cnt + 12'd2;
    wire [11:0] out_rd3 = out_cnt + 12'd3;

    // Can accept new read only when pipeline is empty (no pending write)
    wire out_pipe_ready = !out_valid_pipe;
    wire out_read_en = (state == S_OUT && out_pipe_ready && out_cnt < total_points);
    wire write_fire  = out_valid_pipe && !output_fifo_full;

    // Stage 1: capture out_mem read result (only when no pending write)
    always @(posedge clk_core or negedge rst_n) begin
        if (!rst_n)
            data_out_r <= 40'd0;
        else if (out_read_en)
            data_out_r <= {out_mem[out_rd3], out_mem[out_rd2], out_mem[out_rd1], out_mem[out_rd0]};
    end

    // Stage 1 valid: set on read, clear on write_fire, HOLD when write blocked
    always @(posedge clk_core or negedge rst_n) begin
        if (!rst_n)
            out_valid_pipe <= 1'b0;
        else if (out_read_en)
            out_valid_pipe <= 1'b1;
        else if (write_fire)
            out_valid_pipe <= 1'b0;
        // else: hold (backpressure — pending beat preserved)
    end

    // Stage 2: FIFO write — fires when valid and FIFO has space
    always @(posedge clk_core or negedge rst_n) begin
        if (!rst_n) begin
            output_fifo_wdata <= 40'd0;
            output_fifo_wr_en <= 1'b0;
        end else begin
            output_fifo_wdata <= data_out_r;
            output_fifo_wr_en <= write_fire;
        end
    end

    // out_cnt: advance only on write_fire (not on read_en)
    always @(posedge clk_core or negedge rst_n) begin
        if (!rst_n)
            out_cnt <= 12'd0;
        else if (state != S_OUT)
            out_cnt <= 12'd0;
        else if (write_fire)
            out_cnt <= out_cnt + 12'd4;
    end

    // out_pipe_flush: all data has been READ from out_mem into pipeline
    // State machine waits for pipeline drain (write_fire for last beat) before S_DONE
    always @(posedge clk_core or negedge rst_n) begin
        if (!rst_n)
            out_pipe_flush <= 1'b0;
        else if (state != S_OUT)
            out_pipe_flush <= 1'b0;
        else if (out_cnt >= total_points && total_points != 0)
            out_pipe_flush <= 1'b1;
    end

    // out_mem write port
    reg [11:0] out_mem_wr_addr;
    always @(posedge clk_core) begin
        if (state == S_COL_RUN && col_out_vld)
            out_mem[out_mem_wr_addr] <= col_out_data[9:0];
    end

    always @(posedge clk_core) begin
        if (!rst_n || cmd_fifo_rd_en_r)
            out_mem_wr_addr <= 12'd0;
        else if (state == S_COL_START)
            out_mem_wr_addr <= {5'd0, col_idx[6:0]};
        else if (state == S_COL_RUN && col_out_vld)
            out_mem_wr_addr <= out_mem_wr_addr + {5'd0, tu_width[6:0]};
    end

    // Raster scan address generation
    always @(posedge clk_core or negedge rst_n) begin
        if (!rst_n) begin
            out_row_cnt <= 7'd0;
            out_col_cnt <= 7'd0;
        end else if (write_fire) begin
            if (out_col_cnt + 7'd4 >= {1'b0, tu_width[6:0]}) begin
                out_col_cnt <= 7'd0;
                out_row_cnt <= out_row_cnt + 7'd1;
            end else begin
                out_col_cnt <= out_col_cnt + 7'd4;
            end
        end else if (state != S_OUT) begin
            out_row_cnt <= 7'd0;
            out_col_cnt <= 7'd0;
        end
    end

    // Done pulse
    always @(posedge clk_core or negedge rst_n) begin
        if (!rst_n)
            core_done <= 1'b0;
        else
            core_done <= (state == S_DONE);
    end

endmodule
