`timescale 1ns / 1ps

module cache_l1d (
    input  logic         clk,
    input  logic         rst,

    // CPU side interface
    input  logic         cpu_req,
    input  logic         cpu_we,
    input  logic [31:0]  cpu_addr,
    input  logic [31:0]  cpu_wdata,
    output logic [31:0]  cpu_rdata,
    output logic         cpu_ready,

    // L2 cache side interface
    output logic         l2_req,
    output logic         l2_we,
    output logic [31:0]  l2_addr,
    output logic [127:0] l2_wdata,
    input  logic [127:0] l2_rdata,
    input  logic         l2_ready
);

    // ==========================================
    // DECLARATIONS (Must be at the top for Icarus Verilog compatibility)
    // ==========================================
    localparam INDEX_BITS = 7;
    localparam OFFSET_BITS = 4;
    localparam TAG_BITS = 21; // 32 - 7 - 4 = 21

    // Defining the 4 states for our Write-Back, Write-Allocate FSM
    localparam IDLE        = 2'b00;
    localparam COMPARE_TAG = 2'b01;
    localparam WRITE_BACK  = 2'b10;
    localparam ALLOCATE    = 2'b11;

    logic [1:0] state, next_state;

    // The actual cache storage arrays
    logic [127:0]      data_array  [0:127];
    logic [TAG_BITS-1:0] tag_array [0:127];
    logic              valid_array [0:127];
    logic              dirty_array [0:127];

    logic [TAG_BITS-1:0] req_tag;
    logic [INDEX_BITS-1:0] req_idx;
    logic [1:0]            req_word_offset;

    logic [TAG_BITS-1:0] cur_tag;
    logic                cur_valid, cur_dirty;
    logic [127:0]        cur_data;

    logic hit;
    integer i;

    // ==========================================
    // ASSIGNMENTS & LOGIC
    // ==========================================
    
    // Break down the CPU address into tag, index, and offset
    assign req_tag         = cpu_addr[31:11];
    assign req_idx         = cpu_addr[10:4];
    assign req_word_offset = cpu_addr[3:2];

    // Grab the current data from the cache arrays based on the index
    assign cur_tag   = tag_array[req_idx];
    assign cur_valid = valid_array[req_idx];
    assign cur_dirty = dirty_array[req_idx];
    assign cur_data  = data_array[req_idx];

    // Check if we have a cache hit
    assign hit = cur_valid && (cur_tag == req_tag);

    // Figure out which word from the 128-bit cache line the CPU actually wants
    always_comb begin
        case(req_word_offset)
            2'b00: cpu_rdata = cur_data[31:0];
            2'b01: cpu_rdata = cur_data[63:32];
            2'b10: cpu_rdata = cur_data[95:64];
            2'b11: cpu_rdata = cur_data[127:96];
        endcase
    end

    // If we're evicting a dirty block, we send the *current* tag to L2. Otherwise, we send the *requested* tag.
    assign l2_addr  = { (state == WRITE_BACK) ? cur_tag : req_tag, req_idx, 4'b0000 };
    assign l2_wdata = cur_data;

    // State machine updates and handling cache writes
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            // Clear out the valid and dirty bits on reset
            for (i = 0; i < 128; i = i + 1) begin
                valid_array[i] <= 1'b0;
                dirty_array[i] <= 1'b0;
            end
        end else begin
            state <= next_state;
            
            // If it's a write hit, update the cache line and mark it dirty
            if (state == COMPARE_TAG && hit && cpu_we) begin
                dirty_array[req_idx] <= 1'b1;
                case(req_word_offset)
                    2'b00: data_array[req_idx][31:0]   <= cpu_wdata;
                    2'b01: data_array[req_idx][63:32]  <= cpu_wdata;
                    2'b10: data_array[req_idx][95:64]  <= cpu_wdata;
                    2'b11: data_array[req_idx][127:96] <= cpu_wdata;
                endcase
            end
            // When L2 gives us the new block, store it in the cache
            else if (state == ALLOCATE && l2_ready) begin
                data_array[req_idx]  <= l2_rdata;
                tag_array[req_idx]   <= req_tag;
                valid_array[req_idx] <= 1'b1;
                dirty_array[req_idx] <= 1'b0; // Freshly loaded blocks are clean
            end
        end
    end

    // Combinational logic to decide the next state of the FSM
    always_comb begin
        next_state = state;
        cpu_ready  = 1'b0;
        l2_req     = 1'b0;
        l2_we      = 1'b0;

        case (state)
            IDLE: begin
                // Wait here until the CPU asks for something
                if (cpu_req) next_state = COMPARE_TAG;
            end
            COMPARE_TAG: begin
                if (hit) begin
                    cpu_ready = 1'b1; // Tell the CPU we got the data
                    next_state = IDLE;
                end else begin
                    // Cache miss. We either need to evict a dirty block or just fetch a new one
                    if (cur_valid && cur_dirty) next_state = WRITE_BACK;
                    else                        next_state = ALLOCATE;
                end
            end
            WRITE_BACK: begin
                // Tell L2 to take this dirty data
                l2_req = 1'b1;
                l2_we  = 1'b1;
                if (l2_ready) next_state = ALLOCATE; // Once L2 has it, we can fetch the new stuff
            end
            ALLOCATE: begin
                // Ask L2 for the new block of data
                l2_req = 1'b1;
                l2_we  = 1'b0;
                if (l2_ready) next_state = COMPARE_TAG; // Once we have it, check again (it'll be a hit now)
            end
            default: next_state = IDLE;
        endcase
    end

endmodule
