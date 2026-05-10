`timescale 1ns/1ps
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

logic [1:0] state;
logic cache_hit;
logic dbg_cache_miss;
logic dbg_waiting;

assign dbg_cache_miss = cpu_req && !l2_ready;
assign dbg_waiting = !cpu_ready;

assign l2_req = cpu_req;
assign l2_addr = cpu_addr;
assign cache_hit = l2_ready;

always_comb begin
    cpu_ready = l2_ready;

    case(cpu_addr[3:2])
        2'b00: cpu_rdata = l2_rdata[31:0];
        2'b01: cpu_rdata = l2_rdata[63:32];
        2'b10: cpu_rdata = l2_rdata[95:64];
        default: cpu_rdata = l2_rdata[127:96];
    endcase
end

always_ff @(posedge clk or posedge rst) begin
    if(rst)
        state <= 0;
    else if(cpu_req && !l2_ready)
        state <= 1;
    else if(l2_ready)
        state <= 2;
end
endmodule
