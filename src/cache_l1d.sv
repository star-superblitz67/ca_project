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

    // ==========================================
    // DECLARATIONS (MUST BE AT THE TOP FOR ICARUS)
    // ==========================================
    localparam INDEX_BITS = 7;
    localparam OFFSET_BITS = 4;
    localparam TAG_BITS = 21; // 32 - 7 - 4

    // Replaced enum with localparams to prevent syntax errors in Icarus
    localparam IDLE        = 2'b00;
    localparam COMPARE_TAG = 2'b01;
    localparam WRITE_BACK  = 2'b10;
    localparam ALLOCATE    = 2'b11;

    logic [1:0] state, next_state;

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
    // Hardcoded bit-selects to avoid evaluation ambiguity
    assign req_tag         = cpu_addr[31:11];
    assign req_idx         = cpu_addr[10:4];
    assign req_word_offset = cpu_addr[3:2];

    assign cur_tag   = tag_array[req_idx];
    assign cur_valid = valid_array[req_idx];
    assign cur_dirty = dirty_array[req_idx];
    assign cur_data  = data_array[req_idx];

    assign hit = cur_valid && (cur_tag == req_tag);

    // Word-select mux using a part-select driven by req_word_offset.
    // Avoids constant-select-in-always_comb issues in Icarus Verilog.
    assign cpu_rdata = cur_data[32*req_word_offset +: 32];

    assign l2_addr  = { (state == WRITE_BACK) ? cur_tag : req_tag, req_idx, 4'b0000 };
    assign l2_wdata = cur_data;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            for (i = 0; i < 128; i = i + 1) begin
                valid_array[i] <= 1'b0;
                dirty_array[i] <= 1'b0;
            end
        end else begin
            state <= next_state;
            
            if (state == COMPARE_TAG && hit && cpu_we) begin
                dirty_array[req_idx] <= 1'b1;
                // Use a variable part-select to write the correct 32-bit word.
                // Read-modify-write the full 128-bit line to avoid constant-select
                // limitation in Icarus Verilog.
                data_array[req_idx] <= (data_array[req_idx] & ~(128'hFFFFFFFF << (32*req_word_offset)))
                                     | ({{96{1'b0}}, cpu_wdata} << (32*req_word_offset));
            end
            else if (state == ALLOCATE && l2_ready) begin
                data_array[req_idx]  <= l2_rdata;
                tag_array[req_idx]   <= req_tag;
                valid_array[req_idx] <= 1'b1;
                dirty_array[req_idx] <= 1'b0;
            end
        end
    end

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
                if (l2_ready) next_state = COMPARE_TAG;
            end
            default: next_state = IDLE;
        endcase
    end

endmodule