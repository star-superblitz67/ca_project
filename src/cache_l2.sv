`timescale 1ns/1ps
module cache_l2(
    input logic clk,
    input logic rst,

    input logic l1i_req,
    input logic [31:0] l1i_addr,
    output logic [127:0] l1i_rdata,
    output logic l1i_ready,

    input logic l1d_req,
    input logic l1d_we,
    input logic [31:0] l1d_addr,
    input logic [127:0] l1d_wdata,
    output logic [127:0] l1d_rdata,
    output logic l1d_ready,

    output logic mem_req,
    output logic mem_we,
    output logic [31:0] mem_addr,
    output logic [127:0] mem_wdata,

    input logic [127:0] mem_rdata,
    input logic mem_ready
);

logic [1:0] state;

assign mem_req = l1i_req || l1d_req;
assign mem_we = l1d_we;
assign mem_addr = l1d_req ? l1d_addr : l1i_addr;
assign mem_wdata = l1d_wdata;

assign l1i_rdata = mem_rdata;
assign l1d_rdata = mem_rdata;

assign l1i_ready = mem_ready && l1i_req;
assign l1d_ready = mem_ready && l1d_req;

always_ff @(posedge clk or posedge rst) begin
    if(rst)
        state <= 0;
    else if(mem_req && !mem_ready)
        state <= 1;
    else if(mem_ready)
        state <= 2;
end
endmodule
