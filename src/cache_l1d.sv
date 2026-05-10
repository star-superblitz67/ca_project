`timescale 1ns/1ps
// ============================================================
//  L1 Data Cache  –  Direct-mapped, 4 lines, 16B/line
//  Write-through (no write-allocate):
//    HIT  + WRITE → write word straight to L2 (WRITE_THROUGH)
//    MISS + READ  → fetch block from L2 (REFILL)
//    HIT  + READ  → serve from cache immediately
// ============================================================
module cache_l1d(
    input  logic        clk,
    input  logic        rst,
    // CPU (processor) side
    input  logic        cpu_req,
    input  logic        cpu_we,
    input  logic [31:0] cpu_addr,
    input  logic [31:0] cpu_wdata,
    output logic [31:0] cpu_rdata,
    output logic        cpu_ready,
    // L2 side
    output logic        l2_req,
    output logic        l2_we,
    output logic [31:0] l2_addr,
    output logic [127:0] l2_wdata,
    input  logic [127:0] l2_rdata,
    input  logic        l2_ready
);

    // Cache storage: 4 lines, each 128 bits
    logic         valid [0:3];
    logic [25:0]  tags  [0:3];
    logic [127:0] data  [0:3];

    // Address breakdown
    logic [1:0]  idx;
    logic [25:0] tag;
    assign idx = cpu_addr[5:4];
    assign tag = cpu_addr[31:6];

    logic hit;
    assign hit = valid[idx] && (tags[idx] == tag);

    // State machine
    typedef enum logic [1:0] {IDLE, REFILL, WRITE_THROUGH} state_t;
    state_t state;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            valid[0] <= 1'b0; valid[1] <= 1'b0;
            valid[2] <= 1'b0; valid[3] <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (cpu_req) begin
                        if (cpu_we)
                            state <= WRITE_THROUGH;
                        else if (!hit)
                            state <= REFILL;
                        // hit+read → stay IDLE, cpu_ready asserted combinatorially
                    end
                end

                REFILL: begin
                    if (l2_ready) begin
                        data[idx]  <= l2_rdata;
                        tags[idx]  <= tag;
                        valid[idx] <= 1'b1;
                        state      <= IDLE;
                    end
                end

                WRITE_THROUGH: begin
                    if (l2_ready) begin
                        // Update cache line if we have it (keep coherent)
                        if (hit) begin
                            case (cpu_addr[3:2])
                                2'd0: data[idx][31:0]   <= cpu_wdata;
                                2'd1: data[idx][63:32]  <= cpu_wdata;
                                2'd2: data[idx][95:64]  <= cpu_wdata;
                                2'd3: data[idx][127:96] <= cpu_wdata;
                            endcase
                        end
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    // Read data output: serve from L2 immediately on refill completion
    logic [127:0] serve_block;
    always_comb begin
        if (state == REFILL && l2_ready)
            serve_block = l2_rdata;
        else
            serve_block = data[idx];
    end

    // Word extraction mux (Icarus-compatible)
    assign cpu_rdata = (cpu_addr[3:2] == 2'd0) ? serve_block[31:0]   :
                       (cpu_addr[3:2] == 2'd1) ? serve_block[63:32]  :
                       (cpu_addr[3:2] == 2'd2) ? serve_block[95:64]  :
                                                 serve_block[127:96];

    // cpu_ready: asserted when access completes
    assign cpu_ready = (state == IDLE         && cpu_req && !cpu_we && hit) ||
                       (state == REFILL        && l2_ready) ||
                       (state == WRITE_THROUGH && l2_ready);

    // L2 interface
    // l2_req: active whenever we need L2
    assign l2_req   = (state == REFILL) ||
                      (state == WRITE_THROUGH) ||
                      (state == IDLE && cpu_req && !cpu_we && !hit);

    assign l2_we    = (state == WRITE_THROUGH);

    // For writes: send word address; for reads: send block-aligned address
    assign l2_addr  = (state == WRITE_THROUGH) ? cpu_addr : {tag, idx, 4'b0000};

    // Write data: replicate word into 128-bit bus (DRAM picks the right word)
    assign l2_wdata = {cpu_wdata, cpu_wdata, cpu_wdata, cpu_wdata};

endmodule
