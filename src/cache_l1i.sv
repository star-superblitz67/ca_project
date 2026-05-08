`timescale 1ns / 1ps

module cache_l1i (
    input  logic         clk,
    input  logic         rst,

    // CPU Interface
    input  logic         cpu_req,
    input  logic [31:0]  cpu_addr,
    output logic [31:0]  cpu_rdata,
    output logic         cpu_ready,

    // L2 Interface
    output logic         l2_req,
    output logic [31:0]  l2_addr,
    input  logic [127:0] l2_rdata,
    input  logic         l2_ready
);

    // Read-Only, Direct Mapped, 128 lines, 16 bytes per line
    localparam INDEX_BITS = 7;
    localparam OFFSET_BITS = 4;
    localparam TAG_BITS = 32 - INDEX_BITS - OFFSET_BITS;

    // 3-State FSM (No Write-Back needed for read-only I-Cache)
    typedef enum logic [1:0] {
        IDLE        = 2'b00,
        COMPARE_TAG = 2'b01,
        ALLOCATE    = 2'b10
    } state_t;

    state_t state, next_state;

    // Cache Arrays (No dirty bits)
    logic [127:0]      data_array  [0:127];
    logic [TAG_BITS-1:0] tag_array [0:127];
    logic              valid_array [0:127];

    logic [TAG_BITS-1:0] req_tag;
    logic [INDEX_BITS-1:0] req_idx;
    logic [1:0]            req_word_offset;

    assign req_tag         = cpu_addr[31 : 32-TAG_BITS];
    assign req_idx         = cpu_addr[10 : 4];
    assign req_word_offset = cpu_addr[3 : 2];

    logic hit;
    assign hit = valid_array[req_idx] && (tag_array[req_idx] == req_tag);

    logic [127:0] cur_data;
    assign cur_data = data_array[req_idx];

    // Word selection
    always_comb begin
        case(req_word_offset)
            2'b00: cpu_rdata = cur_data[31:0];
            2'b01: cpu_rdata = cur_data[63:32];
            2'b10: cpu_rdata = cur_data[95:64];
            2'b11: cpu_rdata = cur_data[127:96];
        endcase
    end

    assign l2_addr = {req_tag, req_idx, 4'b0000};

    // Sequential updates
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            for (int i = 0; i < 128; i++) valid_array[i] <= 1'b0;
        end else begin
            state <= next_state;
            if (state == ALLOCATE && l2_ready) begin
                data_array[req_idx]  <= l2_rdata;
                tag_array[req_idx]   <= req_tag;
                valid_array[req_idx] <= 1'b1;
            end
        end
    end

    // Combinational FSM logic
    always_comb begin
        next_state = state;
        cpu_ready  = 1'b0;
        l2_req     = 1'b0;

        case (state)
            IDLE: begin
                if (cpu_req) next_state = COMPARE_TAG;
            end
            COMPARE_TAG: begin
                if (hit) begin
                    cpu_ready = 1'b1;
                    next_state = IDLE;
                end else begin
                    next_state = ALLOCATE;
                end
            end
            ALLOCATE: begin
                l2_req = 1'b1;
                if (l2_ready) next_state = COMPARE_TAG;
            end
            default: next_state = IDLE;
        endcase
    end

endmodule
