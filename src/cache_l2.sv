`timescale 1ns / 1ps

module cache_l2 (
    input  logic         clk,
    input  logic         rst,

    // Interface with the L1 Instruction Cache
    input  logic         l1i_req,
    input  logic [31:0]  l1i_addr,
    output logic [127:0] l1i_rdata,
    output logic         l1i_ready,

    // Interface with the L1 Data Cache
    input  logic         l1d_req,
    input  logic         l1d_we,
    input  logic [31:0]  l1d_addr,
    input  logic [127:0] l1d_wdata,
    output logic [127:0] l1d_rdata,
    output logic         l1d_ready,

    // Interface with the main memory (DRAM simulator)
    output logic         mem_req,
    output logic         mem_we,
    output logic [31:0]  mem_addr,
    output logic [127:0] mem_wdata,
    input  logic [127:0] mem_rdata,
    input  logic         mem_ready
);

    // ==========================================
    // DECLARATIONS (Must be at the top for Icarus Verilog compatibility)
    // ==========================================
    localparam INDEX_BITS = 8;
    localparam OFFSET_BITS = 4;
    localparam TAG_BITS = 20;

    localparam IDLE        = 3'd0;
    localparam COMPARE_TAG = 3'd2;
    localparam WRITE_BACK  = 3'd3;
    localparam ALLOCATE    = 3'd4;

    logic [2:0] state, next_state;

    logic [127:0]      data_array  [0:255];
    logic [TAG_BITS-1:0] tag_array [0:255];
    logic              valid_array [0:255];
    logic              dirty_array [0:255];

    logic active_req;
    logic active_we;
    logic [31:0] active_addr;
    logic [127:0] active_wdata;
    logic serving_l1d; // This tracks if we are currently helping L1 Data or L1 Instruction

    logic [TAG_BITS-1:0] req_tag;
    logic [INDEX_BITS-1:0] req_idx;
    
    logic cur_valid, cur_dirty;
    logic [TAG_BITS-1:0] cur_tag;
    logic [127:0] cur_data;
    logic hit;
    integer i;

    // ==========================================
    // ASSIGNMENTS & LOGIC
    // ==========================================
    
    // Multiplex the signals based on who we are serving right now
    assign active_req   = serving_l1d ? l1d_req : l1i_req;
    assign active_we    = serving_l1d ? l1d_we : 1'b0;
    assign active_addr  = serving_l1d ? l1d_addr : l1i_addr;
    assign active_wdata = serving_l1d ? l1d_wdata : 128'b0;

    assign req_tag = active_addr[31:12];
    assign req_idx = active_addr[11:4];

    assign cur_valid = valid_array[req_idx];
    assign cur_dirty = dirty_array[req_idx];
    assign cur_tag   = tag_array[req_idx];
    assign cur_data  = data_array[req_idx];

    assign hit = cur_valid && (cur_tag == req_tag);

    // Both L1 caches get the same data out, but we only assert 'ready' for the one we're serving
    assign l1d_rdata = cur_data;
    assign l1i_rdata = cur_data;

    // Give DRAM the old tag if evicting, otherwise the new tag
    assign mem_addr  = (state == WRITE_BACK) ? {cur_tag, req_idx, 4'b0000} : {req_tag, req_idx, 4'b0000};
    assign mem_wdata = cur_data;

    // Arbitration: decide who gets to use the L2 cache next
    // We give priority to the Data Cache if both ask at the same time
    always_ff @(posedge clk or posedge rst) begin
        if (rst) serving_l1d <= 1'b0;
        else if (state == IDLE) begin
            if (l1d_req) serving_l1d <= 1'b1;
            else if (l1i_req) serving_l1d <= 1'b0;
        end
    end

    // Handle updating the cache arrays
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            for(i=0; i<256; i=i+1) begin
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

    // Main L2 state machine logic
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
                    // Let the correct L1 cache know we're done
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
