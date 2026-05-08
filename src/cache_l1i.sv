`timescale 1ns / 1ps

module cache_l1i(

    input logic clk,
    input logic rst,

    input logic cpu_req,
    input logic [31:0] cpu_addr,

    output logic [31:0] cpu_rdata,
    output logic cpu_ready,

    output logic l2_req,
    output logic [31:0] l2_addr,

    input logic [127:0] l2_rdata,
    input logic l2_ready

);

localparam INDEX_BITS = 7;
localparam TAG_BITS   = 21;

localparam IDLE        = 2'b00;
localparam COMPARE_TAG = 2'b01;
localparam ALLOCATE    = 2'b10;

logic [1:0] state;
logic [1:0] next_state;

logic [127:0] data_array [0:127];
logic [TAG_BITS-1:0] tag_array [0:127];
logic valid_array [0:127];

logic [TAG_BITS-1:0] req_tag;
logic [INDEX_BITS-1:0] req_idx;
logic [1:0] req_word_offset;

logic [127:0] cur_data;

logic hit;

integer i;

initial begin

    for(i=0;i<128;i=i+1) begin

        valid_array[i] = 0;
        tag_array[i] = 0;
        data_array[i] = 0;

    end

end

assign req_tag         = cpu_addr[31:11];
assign req_idx         = cpu_addr[10:4];
assign req_word_offset = cpu_addr[3:2];

assign hit =
    valid_array[req_idx] &&
    (tag_array[req_idx] == req_tag);

assign cur_data = data_array[req_idx];

assign l2_addr = {req_tag, req_idx, 4'b0000};

always @(*) begin

    cpu_rdata = 0;

    case(req_word_offset)

        2'b00:
            cpu_rdata = cur_data[31:0];

        2'b01:
            cpu_rdata = cur_data[63:32];

        2'b10:
            cpu_rdata = cur_data[95:64];

        2'b11:
            cpu_rdata = cur_data[127:96];

    endcase

end

always @(posedge clk or posedge rst) begin

    if(rst) begin

        state <= IDLE;

    end
    else begin

        state <= next_state;

        if(state == ALLOCATE && l2_ready) begin

            data_array[req_idx] <= l2_rdata;
            tag_array[req_idx] <= req_tag;
            valid_array[req_idx] <= 1'b1;

        end

    end

end

always @(*) begin

    next_state = state;

    cpu_ready = 0;
    l2_req = 0;

    case(state)

        IDLE: begin

            if(cpu_req)
                next_state = COMPARE_TAG;

        end

        COMPARE_TAG: begin

            if(hit) begin

                cpu_ready = 1;
                next_state = IDLE;

            end
            else begin

                next_state = ALLOCATE;

            end

        end

        ALLOCATE: begin

            l2_req = 1;

            if(l2_ready) begin

                cpu_ready = 1;
                next_state = IDLE;

            end

        end

        default:
            next_state = IDLE;

    endcase

end

endmodule