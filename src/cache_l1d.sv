`timescale 1ns/1ps
module cache_l1d(
    input logic clk,
    input logic rst,
    input logic cpu_req,
    input logic cpu_we,
    input logic [31:0] cpu_addr,
    input logic [31:0] cpu_wdata,
    output logic [31:0] cpu_rdata,
    output logic cpu_ready,

    output logic l2_req,
    output logic l2_we,
    output logic [31:0] l2_addr,
    output logic [127:0] l2_wdata,

    input logic [127:0] l2_rdata,
    input logic l2_ready
);

logic [1:0] state;
logic dirty_bit;

assign l2_req = cpu_req;
assign l2_we = cpu_we;
assign l2_addr = cpu_addr;
assign l2_wdata = {4{cpu_wdata}};

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
    if(rst) begin
        state <= 0;
        dirty_bit <= 0;
    end
    else begin
        if(cpu_we)
            dirty_bit <= 1;

        if(cpu_req && !l2_ready)
            state <= 1;
        else if(l2_ready)
            state <= 2;
    end
end
endmodule
