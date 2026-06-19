`timescale 1ns / 1ps
module tb_async_fifo;

    reg wr_clk, rd_clk, rst_n;
    reg        wr_en, rd_en;
    reg  [7:0] wr_data;
    wire [7:0] rd_data;
    wire       full, empty;
    wire [2:0] wr_count;

    async_fifo #(.DATA_WIDTH(8), .ADDR_WIDTH(2)) u_fifo (
        .wr_clk(wr_clk), .wr_rst_n(rst_n), .wr_en(wr_en), .wr_data(wr_data),
        .full(full), .almost_full(), .wr_count(wr_count),
        .rd_clk(rd_clk), .rd_rst_n(rst_n), .rd_en(rd_en),
        .rd_data(rd_data), .empty(empty)
    );

    initial wr_clk = 0;
    always #5 wr_clk = ~wr_clk;   // 100MHz
    initial rd_clk = 0;
    always #2.5 rd_clk = ~rd_clk; // 200MHz

    initial begin
        rst_n = 0; wr_en = 0; rd_en = 0; wr_data = 0;
        #50;
        rst_n = 1;
        #50;

        $display("Before write: empty=%b full=%b wr_count=%0d", empty, full, wr_count);
        @(posedge wr_clk); wr_en = 1; wr_data = 8'hAA;
        @(posedge wr_clk); wr_en = 0;
        #20;
        $display("After write 1: empty=%b full=%b wr_count=%0d rd_data=%h", empty, full, wr_count, rd_data);

        @(posedge wr_clk); wr_en = 1; wr_data = 8'hBB;
        @(posedge wr_clk); wr_en = 0;
        #20;
        $display("After write 2: empty=%b full=%b wr_count=%0d rd_data=%h", empty, full, wr_count, rd_data);

        @(posedge wr_clk); wr_en = 1; wr_data = 8'hCC;
        @(posedge wr_clk); wr_en = 0;
        #20;
        $display("After write 3: empty=%b full=%b wr_count=%0d rd_data=%h", empty, full, wr_count, rd_data);

        // Read
        @(posedge rd_clk); rd_en = 1;
        @(posedge rd_clk); rd_en = 0;
        #10;
        $display("After read 1: empty=%b rd_data=%h", empty, rd_data);

        @(posedge rd_clk); rd_en = 1;
        @(posedge rd_clk); rd_en = 0;
        #10;
        $display("After read 2: empty=%b rd_data=%h", empty, rd_data);

        @(posedge rd_clk); rd_en = 1;
        @(posedge rd_clk); rd_en = 0;
        #10;
        $display("After read 3: empty=%b rd_data=%h", empty, rd_data);

        $display("DONE");
        $finish;
    end

    initial begin #5000; $display("TIMEOUT"); $finish; end
endmodule
