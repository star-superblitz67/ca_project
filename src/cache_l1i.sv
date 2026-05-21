`timescale 1ns/1ps
// L1 Instruction Cache – direct-mapped, 4 lines, 16B/line, read-only.
// On miss: enters REFILL and requests the 128-bit block from L2.
module cache_l1i(
    input  logic        clk,
    input  logic        rst,
    // CPU (processor) side
    input  logic        cpu_req,
    input  logic [31:0] cpu_addr,
    output logic [31:0] cpu_rdata,
    output logic        cpu_ready,
    // L2 side
    output logic        l2_req,
    output logic [31:0] l2_addr,
    input  logic [127:0] l2_rdata,
    input  logic        l2_ready
);

    // Cache storage: 4 lines, each 128 bits wide
    logic         valid [0:3];
    logic [25:0]  tags  [0:3];
    logic [127:0] data  [0:3];

    // Address breakdown: [31:6]=tag, [5:4]=index, [3:0]=block-offset
    logic [1:0]  idx;
    logic [25:0] tag;
    assign idx = cpu_addr[5:4];
    assign tag = cpu_addr[31:6];

    // Hit detection
    logic hit;
    assign hit = valid[idx] && (tags[idx] == tag);

    typedef enum logic [0:0] {IDLE, REFILL} state_t;
    state_t state;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            valid[0] <= 1'b0; valid[1] <= 1'b0;
            valid[2] <= 1'b0; valid[3] <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (cpu_req && !hit)
                        state <= REFILL;
                end
                REFILL: begin
                    if (l2_ready) begin
                        data[idx]  <= l2_rdata;
                        tags[idx]  <= tag;
                        valid[idx] <= 1'b1;
                        state      <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

    // Serve from refill data immediately on l2_ready to avoid an extra stall cycle
    logic [127:0] serve_block;
    always_comb begin
        if (state == REFILL && l2_ready)
            serve_block = l2_rdata;
        else
            serve_block = data[idx];
    end

    // Word extraction: word offset = cpu_addr[3:2]; explicit mux for Icarus compatibility
    assign cpu_rdata = (cpu_addr[3:2] == 2'd0) ? serve_block[31:0]   :
                       (cpu_addr[3:2] == 2'd1) ? serve_block[63:32]  :
                       (cpu_addr[3:2] == 2'd2) ? serve_block[95:64]  :
                                                 serve_block[127:96];

    assign cpu_ready = (state == IDLE   && cpu_req && hit) ||
                       (state == REFILL && l2_ready);

    assign l2_req  = (state == REFILL) ||
                     (state == IDLE && cpu_req && !hit);

    // Always request the full aligned 16-byte block
    assign l2_addr = {tag, idx, 4'b0000};

endmodule
