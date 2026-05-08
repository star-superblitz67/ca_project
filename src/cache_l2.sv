`timescale 1ns / 1ps

module cache_l2 (
    input  logic         clk,
    input  logic         rst,

    // L1 Instruction Cache Interface
    input  logic         l1i_req,
    input  logic [31:0]  l1i_addr,
    output logic [127:0] l1i_rdata,
    output logic         l1i_ready,

    // L1 Data Cache Interface
    input  logic         l1d_req,
    input  logic         l1d_we,
    input  logic [31:0]  l1d_addr,
    input  logic [127:0] l1d_wdata,
    output logic [127:0] l1d_rdata,
    output logic         l1d_ready,

    // Main Memory (DRAM) Interface
    output logic         mem_req,
    output logic         mem_we,
    output logic [31:0]  mem_addr,
    output logic [127:0] mem_wdata,
    input  logic [127:0] mem_rdata,
    input  logic         mem_ready
);

    // Unified, Direct Mapped, 256 Lines, 16 Bytes per line
    localparam INDEX_BITS = 8;
    localparam OFFSET_BITS = 4;
    localparam TAG_BITS = 32 - INDEX_BITS - OFFSET_BITS;

    typedef enum logic [2:0] {
        IDLE        = 3'd0,
        COMPARE_TAG = 3'd2,
        WRITE_BACK  = 3'd3,
        ALLOCATE    = 3'd4
    } state_t;

    state_t state, next_state;

    logic [127:0]      data_array  [0:255];
    logic [TAG_BITS-1:0] tag_array [0:255];
    logic              valid_array [0:255];
    logic              dirty_array [0:255];

    // Arbitration logic: L1D has priority if both request simultaneously
    logic active_req;
    logic active_we;
    logic [31:0] active_addr;
    logic [127:0] active_wdata;
    logic serving_l1d; // 1 = Data, 0 = Instruction

    always_ff @(posedge clk or posedge rst) begin
        if (rst) serving_l1d <= 1'b0;
        else if (state == IDLE) begin
            if (l1d_req) serving_l1d <= 1'b1;
            else if (l1i_req) serving_l1d <= 1'b0;
        end
    end

    assign active_req   = serving_l1d ? l1d_req : l1i_req;
    assign active_we    = serving_l1d ? l1d_we : 1'b0;
    assign active_addr  = serving_l1d ? l1d_addr : l1i_addr;
    assign active_wdata = serving_l1d ? l1d_wdata : 128'b0;

    logic [TAG_BITS-1:0] req_tag;
    logic [INDEX_BITS-1:0] req_idx;
    assign req_tag = active_addr[31 : 32-TAG_BITS];
    assign req_idx = active_addr[11 : 4];

    logic cur_valid, cur_dirty;
    logic [TAG_BITS-1:0] cur_tag;
    logic [127:0] cur_data;

    assign cur_valid = valid_array[req_idx];
    assign cur_dirty = dirty_array[req_idx];
    assign cur_tag   = tag_array[req_idx];
    assign cur_data  = data_array[req_idx];

    logic hit;
    assign hit = cur_valid && (cur_tag == req_tag);

    // Outputs to L1 caches
    assign l1d_rdata = cur_data;
    assign l1i_rdata = cur_data;

    // Interface to DRAM
    assign mem_addr  = (state == WRITE_BACK) ? {cur_tag, req_idx, 4'b0000} : {req_tag, req_idx, 4'b0000};
    assign mem_wdata = cur_data;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            for(int i=0; i<256; i++) begin
                valid_array[i] <= 1'b0;
                dirty_array[i] <= 1'b0;
            end
        end else begin
            state <= next_state;
            
            if (state == COMPARE_TAG && hit && active_we) begin
                data_array[req_idx]  <= active_wdata;
                dirty_array[req_idx] <= 1'b1;
            end else if (state == ALLOCATE && mem_ready) begin
                data_array[req_idx]  <= mem_rdata;
                tag_array[req_idx]   <= req_tag;
                valid_array[req_idx] <= 1'b1;
                dirty_array[req_idx] <= 1'b0;
            end
        end
    end

    // Unified FSM Logic
    always_comb begin
        next_state = state;
        l1i_ready  = 1'b0;
        l1d_ready  = 1'b0;
        mem_req    = 1'b0;
        mem_we     = 1'b0;

        case (state)
            IDLE: begin
                if (l1d_req || l1i_req) next_state = COMPARE_TAG;
            end
            COMPARE_TAG: begin
                if (hit) begin
                    if (serving_l1d) l1d_ready = 1'b1;
                    else             l1i_ready = 1'b1;
                    next_state = IDLE;
                end else begin
                    if (cur_valid && cur_dirty) next_state = WRITE_BACK;
                    else                        next_state = ALLOCATE;
                end
            end
            WRITE_BACK: begin
                mem_req = 1'b1;
                mem_we  = 1'b1;
                if (mem_ready) next_state = ALLOCATE;
            end
            ALLOCATE: begin
                mem_req = 1'b1;
                mem_we  = 1'b0;
                if (mem_ready) next_state = COMPARE_TAG;
            end
            default: next_state = IDLE;
        endcase
    end

endmodule
