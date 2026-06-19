// FWFT FIFO register slice
// Breaks combinational path from FIFO rd_ptr → FIFO RAM → consumer.
// Inserts 1 cycle of latency but maintains FWFT semantics:
//   - Data is always available (registered) when not empty
//   - Consumer reads registered data; FIFO advances in background
//   - No data loss: every FIFO entry consumed exactly once
//
// core_ready: must be HIGH when consumer can accept data.
//   Used to gate proactive fill — prevents consuming FIFO data
//   when consumer is busy (e.g. during memory clearing).
//   Tie to 1'b1 if not needed.

module fifo_fwft_reg_slice #(
    parameter DATA_WIDTH = 16
) (
    input  wire                   clk,
    input  wire                   rst_n,
    // FIFO side (combinational FWFT outputs)
    input  wire [DATA_WIDTH-1:0]  fifo_rdata,
    input  wire                   fifo_empty,
    output wire                   fifo_rd_en,
    // Consumer side (registered outputs)
    output reg  [DATA_WIDTH-1:0]  core_rdata,
    output reg                    core_empty,
    input  wire                   core_rd_en,
    // Consumer ready: gate for proactive fill
    input  wire                   core_ready
);

    // Load from FIFO when:
    //   - consumer is reading and FIFO has data (prefetch next)
    //   - slice is empty, consumer ready, and FIFO has data (fill the pipe)
    wire slice_load = (core_rd_en | (core_empty & core_ready)) & ~fifo_empty;
    assign fifo_rd_en = slice_load;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            core_rdata <= {DATA_WIDTH{1'b0}};
            core_empty <= 1'b1;
        end else begin
            if (slice_load)
                core_rdata <= fifo_rdata;
            core_empty <= ~slice_load;
        end
    end

endmodule
