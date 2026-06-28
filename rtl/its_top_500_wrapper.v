// 500MHz wrapper: competition interface ↔ async FIFO CDC ↔ its_core_500
// External interface identical to its_top.v, plus clk_core input.
// All external signals are in clk_if domain; core runs in clk_core domain.

module its_top_500_wrapper (
    // Clocks and reset
    input  wire        clk_if,           // interface clock (e.g. 100MHz)
    input  wire        clk_core,         // core clock (500MHz)
    input  wire        rst_n,            // async active-low reset
    // Competition interface (clk_if domain)
    input  wire [21:0] it_info,
    input  wire        it_info_vld,
    input  wire [15:0] it_data_in,
    input  wire [11:0] it_data_addr,
    input  wire        it_data_in_vld,
    input  wire        it_data_end,
    output wire        it_data_in_req,
    output wire [39:0] it_data_out,
    output wire        it_data_out_vld,
    input  wire        it_data_out_req,
    output wire        it_done
);

    // ================================================================
    // All wire/reg declarations (before any instantiations)
    // ================================================================
    wire rst_sync_if_n;
    wire rst_sync_core_n;

    // cmd_fifo
    wire        cmd_fifo_full;
    wire        cmd_fifo_almost_full;
    wire [2:0]  cmd_fifo_wr_count;
    wire [22:0] cmd_fifo_rdata;
    wire        cmd_fifo_empty;
    wire        cmd_fifo_rd_en;

    // input_fifo (raw combinational outputs from FIFO)
    wire        input_fifo_full;
    wire        input_fifo_almost_full;
    wire [4:0]  input_fifo_wr_count;
    wire [28:0] input_fifo_rdata;
    wire        input_fifo_empty;
    wire        input_fifo_rd_en;

    // input_fifo registered slice (feeds core_500, breaks critical path)
    wire [28:0] input_fifo_rdata_r;
    wire        input_fifo_empty_r;
    wire        input_fifo_rd_en_from_core;

    // output_fifo
    wire [39:0] output_fifo_wdata;
    wire        output_fifo_wr_en;
    wire        output_fifo_full;
    wire        output_fifo_almost_full;
    wire [39:0] output_fifo_rd_data;
    wire        output_fifo_empty;
    wire        output_fifo_rd_en;

    // done CDC (toggle-based: clk_core pulse → toggle → clk_if edge detect)
    wire        core_done;
    wire        core_ready;
    reg         done_toggle;       // clk_core domain: toggles on each core_done
    reg         done_sync1, done_sync2, done_sync3;

    // input_fifo write logic
    // end_pending: set when it_data_end coincides with data (defer marker 1 cycle)
    // Cleared ONLY after marker actually written (wr_fire), not just when space available
    reg         end_pending;
    wire        can_write_input = (input_fifo_wr_count < 5'd15) & ~input_fifo_full;
    wire        do_write_data   = it_data_in_vld & it_data_in_req & ~end_pending;
    wire        do_write_end    = end_pending;
    wire [28:0] input_fifo_wr_data = do_write_end
                                     ? {1'b1, 12'd0, 16'd0}
                                     : {1'b0, it_data_addr, it_data_in};
    wire        input_fifo_wr_en = do_write_data | do_write_end;
    // Separate end arrival: set pending (deferred to next cycle)
    wire        end_arrives     = it_data_end & ~it_data_in_vld & ~end_pending;
    // wr_fire: marker actually written to FIFO
    wire        end_wr_fire     = do_write_end & input_fifo_wr_en & ~input_fifo_full;

    // ================================================================
    // Reset synchronizers
    // ================================================================
    rst_sync u_rst_if (
        .clk        (clk_if),
        .async_rst_n(rst_n),
        .sync_rst_n (rst_sync_if_n)
    );

    rst_sync u_rst_core (
        .clk        (clk_core),
        .async_rst_n(rst_n),
        .sync_rst_n (rst_sync_core_n)
    );

    // ================================================================
    // cmd_fifo: 23-bit, depth 4, clk_if → clk_core
    // ================================================================
    async_fifo #(
        .DATA_WIDTH(23),
        .ADDR_WIDTH(2)
    ) u_cmd_fifo (
        .wr_clk     (clk_if),
        .wr_rst_n   (rst_sync_if_n),
        .wr_en      (it_info_vld & ~cmd_fifo_full),
        .wr_data    ({1'b0, it_info}),
        .full       (cmd_fifo_full),
        .almost_full(cmd_fifo_almost_full),
        .wr_count   (cmd_fifo_wr_count),
        .rd_clk     (clk_core),
        .rd_rst_n   (rst_sync_core_n),
        .rd_en      (cmd_fifo_rd_en),
        .rd_data    (cmd_fifo_rdata),
        .empty      (cmd_fifo_empty)
    );

    // ================================================================
    // input_fifo: 29-bit, depth 16, clk_if → clk_core
    // Format: {last[28], addr[27:16], coeff[15:0]}
    // ================================================================
    always @(posedge clk_if or negedge rst_sync_if_n) begin
        if (!rst_sync_if_n)
            end_pending <= 1'b0;
        else if (it_data_end & it_data_in_vld & can_write_input)
            end_pending <= 1'b1;
        else if (end_arrives)
            end_pending <= 1'b1;
        else if (end_wr_fire)
            end_pending <= 1'b0;
    end

    assign it_data_in_req = can_write_input & ~end_pending;

    async_fifo #(
        .DATA_WIDTH(29),
        .ADDR_WIDTH(4)
    ) u_input_fifo (
        .wr_clk     (clk_if),
        .wr_rst_n   (rst_sync_if_n),
        .wr_en      (input_fifo_wr_en),
        .wr_data    (input_fifo_wr_data),
        .full       (input_fifo_full),
        .almost_full(input_fifo_almost_full),
        .wr_count   (input_fifo_wr_count),
        .rd_clk     (clk_core),
        .rd_rst_n   (rst_sync_core_n),
        .rd_en      (input_fifo_rd_en),
        .rd_data    (input_fifo_rdata),
        .empty      (input_fifo_empty)
    );

    // ================================================================
    // input_fifo register slice (clk_core domain)
    // Breaks rd_ptr → FIFO RAM → core in_mem combinational critical path.
    // FIFO's FWFT combinational outputs → registered → core_500
    // ================================================================
    fifo_fwft_reg_slice #(
        .DATA_WIDTH(29)
    ) u_input_fifo_reg_slice (
        .clk        (clk_core),
        .rst_n      (rst_sync_core_n),
        .fifo_rdata (input_fifo_rdata),
        .fifo_empty (input_fifo_empty),
        .fifo_rd_en (input_fifo_rd_en),
        .core_rdata (input_fifo_rdata_r),
        .core_empty (input_fifo_empty_r),
        .core_rd_en (input_fifo_rd_en_from_core),
        .core_ready (core_ready)
    );

    // ================================================================
    // output_fifo: 40-bit, depth 16, clk_core → clk_if
    // ================================================================
    async_fifo #(
        .DATA_WIDTH(40),
        .ADDR_WIDTH(4)
    ) u_output_fifo (
        .wr_clk     (clk_core),
        .wr_rst_n   (rst_sync_core_n),
        .wr_en      (output_fifo_wr_en),
        .wr_data    (output_fifo_wdata),
        .full       (output_fifo_full),
        .almost_full(output_fifo_almost_full),
        .wr_count   (),
        .rd_clk     (clk_if),
        .rd_rst_n   (rst_sync_if_n),
        .rd_en      (output_fifo_rd_en),
        .rd_data    (output_fifo_rd_data),
        .empty      (output_fifo_empty)
    );

    // Output control (clk_if domain): FWFT
    // vld indicates data available (independent of req). Data stable until rd_en.
    // rd_en fires only when both vld and req asserted — no race condition with FWFT.
    assign output_fifo_rd_en = it_data_out_req & ~output_fifo_empty;
    assign it_data_out     = output_fifo_rd_data;
    assign it_data_out_vld = ~output_fifo_empty;

    // ================================================================
    // Output beat counter & done generation
    // ================================================================
    function [12:0] points_from_size;
        input [6:0] width;
        input [6:0] height;
        begin
            case (height)
                7'd4:    points_from_size = {4'd0, width, 2'd0};
                7'd8:    points_from_size = {3'd0, width, 3'd0};
                7'd16:   points_from_size = {2'd0, width, 4'd0};
                7'd32:   points_from_size = {1'd0, width, 5'd0};
                7'd64:   points_from_size = {width, 6'd0};
                default: points_from_size = {4'd0, width, 2'd0};
            endcase
        end
    endfunction

    // Latch total_points from it_info on new TU, clear done state.
    // it_info format: {lfnst_idx[1:0], lfnst_tr_set_idx[1:0],
    //                  tr_ver[1:0], tr_hor[1:0], height[6:0], width[6:0]}
    reg [12:0] total_points;   // max 64*64 = 4096
    reg [12:0] out_beat_count; // counts beats read (each beat = 4 values)

    wire new_tu = it_info_vld & ~cmd_fifo_full;

    always @(posedge clk_if or negedge rst_sync_if_n) begin
        if (!rst_sync_if_n) begin
            total_points   <= 13'd0;
            out_beat_count <= 13'd0;
        end else if (new_tu) begin
            total_points   <= points_from_size(it_info[6:0], it_info[13:7]);
            out_beat_count <= 13'd0;
        end else if (output_fifo_rd_en) begin
            out_beat_count <= out_beat_count + 13'd1;
        end
    end

    // ================================================================
    // core_done CDC: toggle-based synchronizer (clk_core → clk_if)
    // ================================================================
    always @(posedge clk_core or negedge rst_sync_core_n) begin
        if (!rst_sync_core_n)
            done_toggle <= 1'b0;
        else if (core_done)
            done_toggle <= ~done_toggle;
    end

    always @(posedge clk_if or negedge rst_sync_if_n) begin
        if (!rst_sync_if_n) begin
            done_sync1 <= 1'b0;
            done_sync2 <= 1'b0;
            done_sync3 <= 1'b0;
        end else begin
            done_sync1 <= done_toggle;
            done_sync2 <= done_sync1;
            done_sync3 <= done_sync2;
        end
    end

    wire core_done_pulse = done_sync2 ^ done_sync3;

    // core_finished: sticky latch, cleared on new TU or reset
    reg core_finished;

    always @(posedge clk_if or negedge rst_sync_if_n) begin
        if (!rst_sync_if_n)
            core_finished <= 1'b0;
        else if (new_tu)
            core_finished <= 1'b0;
        else if (core_done_pulse)
            core_finished <= 1'b1;
    end

    // All beats read: out_beat_count * 4 >= total_points
    // Equivalent: out_beat_count >= (total_points + 3) / 4 = (total_points + 3) >> 2
    // Use comparison: out_beat_count * 4 >= total_points → out_beat_count >= ceil(total_points/4)
    // Simplify: (out_beat_count << 2) >= total_points
    wire all_beats_read = ({out_beat_count, 2'b00} >= total_points);

    // it_done: sticky. Set when core finished + FIFO drained + all beats read.
    // Cleared on new TU or reset.
    reg it_done_r;
    always @(posedge clk_if or negedge rst_sync_if_n) begin
        if (!rst_sync_if_n)
            it_done_r <= 1'b0;
        else if (new_tu)
            it_done_r <= 1'b0;
        else if (core_finished && output_fifo_empty && all_beats_read)
            it_done_r <= 1'b1;
    end
    assign it_done = it_done_r;

    // ================================================================
    // its_core_500 instantiation
    // ================================================================
    its_core_500 u_core (
        .clk_core           (clk_core),
        .rst_n              (rst_sync_core_n),
        .cmd_fifo_rdata     (cmd_fifo_rdata),
        .cmd_fifo_empty     (cmd_fifo_empty),
        .cmd_fifo_rd_en     (cmd_fifo_rd_en),
        .input_fifo_rdata   (input_fifo_rdata_r),
        .input_fifo_empty   (input_fifo_empty_r),
        .input_fifo_rd_en   (input_fifo_rd_en_from_core),
        .output_fifo_wdata  (output_fifo_wdata),
        .output_fifo_wr_en  (output_fifo_wr_en),
        .output_fifo_full   (output_fifo_full),
        .output_fifo_almost_full(output_fifo_almost_full),
        .core_done          (core_done),
        .core_ready         (core_ready)
    );

endmodule
