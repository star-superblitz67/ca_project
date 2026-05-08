`timescale 1ns / 1ps

module cache_l1d (
    input  logic         clk,
    input  logic         rst,

    // CPU Interface
    input  logic         cpu_req,
    input  logic         cpu_we,
    input  logic [31:0]  cpu_addr,
    input  logic [31:0]  cpu_wdata,
    output logic [31:0]  cpu_rdata,
    output logic         cpu_ready,

    // L2 Interface
    output logic         l2_req,
    output logic         l2_we,
    output logic [31:0]  l2_addr,
    output logic [127:0] l2_wdata,
    input  logic [127:0] l2_rdata,
    input  logic         l2_ready
);

    // Cache sizing: Direct Mapped, 128 lines, 16 bytes (4 words) per line.
    localparam INDEX_BITS = 7;
    localparam OFFSET_BITS = 4;
    localparam TAG_BITS = 32 - INDEX_BITS - OFFSET_BITS;

    // 4-State Write-Back, Write-Allocate FSM
    typedef enum logic [1:0] {
        IDLE        = 2'b00, // Wait for CPU
        COMPARE_TAG = 2'b01, // Check hit/miss
        WRITE_BACK  = 2'b10, // Evict dirty line to L2
        ALLOCATE    = 2'b11  // Fetch missed line from L2
    } state_t;

    state_t state, next_state;

    // Internal Memory Arrays
    logic [127:0]      data_array  [0:127];
    logic [TAG_BITS-1:0] tag_array [0:127];
    logic              valid_array [0:127];
    logic              dirty_array [0:127];

    // Address Decoding
    logic [TAG_BITS-1:0] req_tag;
    logic [INDEX_BITS-1:0] req_idx;
    logic [1:0]            req_word_offset;

    assign req_tag         = cpu_addr[31 : 32-TAG_BITS];
    assign req_idx         = cpu_addr[10 : 4];
    assign req_word_offset = cpu_addr[3 : 2];

    // Cache Line Data Extraction
    logic [TAG_BITS-1:0] cur_tag;
    logic                cur_valid, cur_dirty;
    logic [127:0]        cur_data;

    assign cur_tag   = tag_array[req_idx];
    assign cur_valid = valid_array[req_idx];
    assign cur_dirty = dirty_array[req_idx];
    assign cur_data  = data_array[req_idx];

    logic hit;
    assign hit = cur_valid && (cur_tag == req_tag);

    // Multiplex correct word back to CPU based on address offset
    always_comb begin
        case(req_word_offset)
            2'b00: cpu_rdata = cur_data[31:0];
            2'b01: cpu_rdata = cur_data[63:32];
            2'b10: cpu_rdata = cur_data[95:64];
            2'b11: cpu_rdata = cur_data[127:96];
        endcase
    end

    // Direct L2 requests to either the old evicted tag or the new requested tag
    assign l2_addr  = { (state == WRITE_BACK) ? cur_tag : req_tag, req_idx, 4'b0000 };
    assign l2_wdata = cur_data;

    // FSM State Updates & Cache Array Writes
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            for (int i = 0; i < 128; i++) begin
                valid_array[i] <= 1'b0;
                dirty_array[i] <= 1'b0;
            end
        end else begin
            state <= next_state;
            
            // Handle write hit
            if (state == COMPARE_TAG && hit && cpu_we) begin
                dirty_array[req_idx] <= 1'b1;
                case(req_word_offset)
                    2'b00: data_array[req_idx][31:0]   <= cpu_wdata;
                    2'b01: data_array[req_idx][63:32]  <= cpu_wdata;
                    2'b10: data_array[req_idx][95:64]  <= cpu_wdata;
                    2'b11: data_array[req_idx][127:96] <= cpu_wdata;
                endcase
            end
            // Handle block fetch from L2
            else if (state == ALLOCATE && l2_ready) begin
                data_array[req_idx]  <= l2_rdata;
                tag_array[req_idx]   <= req_tag;
                valid_array[req_idx] <= 1'b1;
                dirty_array[req_idx] <= 1'b0;
            end
        end
    end

    // FSM Next-State Logic
    always_comb begin
        next_state = state;
        cpu_ready  = 1'b0;
        l2_req     = 1'b0;
        l2_we      = 1'b0;

        case (state)
            IDLE: begin
                if (cpu_req) next_state = COMPARE_TAG;
            end
            COMPARE_TAG: begin
                if (hit) begin
                    cpu_ready = 1'b1;
                    next_state = IDLE;
                end else begin
                    // Miss logic: Evict if dirty, else overwrite
                    if (cur_valid && cur_dirty) next_state = WRITE_BACK;
                    else                        next_state = ALLOCATE;
                end
            end
            WRITE_BACK: begin
                l2_req = 1'b1;
                l2_we  = 1'b1;
                if (l2_ready) next_state = ALLOCATE;
            end
            ALLOCATE: begin
                l2_req = 1'b1;
                l2_we  = 1'b0;
                if (l2_ready) next_state = COMPARE_TAG; // Retry hit
            end
            default: next_state = IDLE;
        endcase
    end

endmodule
