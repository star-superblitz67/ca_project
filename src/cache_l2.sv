`timescale 1ns/1ps
// ============================================================
//  L2 Unified Cache Arbiter
//  Simple priority arbiter: L1D > L1I (data wins on conflict).
//  Serves one request at a time. Forwards directly to DRAM.
//  (L2 is a pass-through arbiter in this educational design;
//   a real L2 would have its own tag/data arrays.)
// ============================================================
module cache_l2(
    input  logic        clk,
    input  logic        rst,
    // L1I port
    input  logic        l1i_req,
    input  logic [31:0] l1i_addr,
    output logic [127:0] l1i_rdata,
    output logic        l1i_ready,
    // L1D port
    input  logic        l1d_req,
    input  logic        l1d_we,
    input  logic [31:0] l1d_addr,
    input  logic [127:0] l1d_wdata,
    output logic [127:0] l1d_rdata,
    output logic        l1d_ready,
    // DRAM port
    output logic        mem_req,
    output logic        mem_we,
    output logic [31:0] mem_addr,
    output logic [127:0] mem_wdata,
    input  logic [127:0] mem_rdata,
    input  logic        mem_ready
);

    // Arbitration: track which L1 is currently being served
    // to prevent switching mid-transaction.
    typedef enum logic [1:0] {ARB_IDLE, ARB_SERVE_D, ARB_SERVE_I} arb_t;
    arb_t arb_state;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            arb_state <= ARB_IDLE;
        end else begin
            case (arb_state)
                ARB_IDLE: begin
                    // L1D has priority
                    if (l1d_req)
                        arb_state <= ARB_SERVE_D;
                    else if (l1i_req)
                        arb_state <= ARB_SERVE_I;
                end
                ARB_SERVE_D: begin
                    if (mem_ready)   // transaction complete
                        arb_state <= ARB_IDLE;
                end
                ARB_SERVE_I: begin
                    if (mem_ready)
                        arb_state <= ARB_IDLE;
                end
                default: arb_state <= ARB_IDLE;
            endcase
        end
    end

    // Combinational outputs based on arbiter state
    always_comb begin
        // Safe defaults
        mem_req   = 1'b0;
        mem_we    = 1'b0;
        mem_addr  = 32'd0;
        mem_wdata = 128'd0;
        l1i_ready = 1'b0;
        l1d_ready = 1'b0;
        l1i_rdata = mem_rdata;
        l1d_rdata = mem_rdata;

        case (arb_state)
            ARB_IDLE: begin
                // Propagate request combinatorially to start the first cycle
                if (l1d_req) begin
                    mem_req   = 1'b1;
                    mem_we    = l1d_we;
                    mem_addr  = l1d_addr;
                    mem_wdata = l1d_wdata;
                end else if (l1i_req) begin
                    mem_req   = 1'b1;
                    mem_we    = 1'b0;
                    mem_addr  = l1i_addr;
                end
            end

            ARB_SERVE_D: begin
                mem_req   = l1d_req;   // keep asserting until done
                mem_we    = l1d_we;
                mem_addr  = l1d_addr;
                mem_wdata = l1d_wdata;
                l1d_ready = mem_ready;
            end

            ARB_SERVE_I: begin
                mem_req   = l1i_req;
                mem_we    = 1'b0;
                mem_addr  = l1i_addr;
                l1i_ready = mem_ready;
            end

            default: ;
        endcase
    end

endmodule
