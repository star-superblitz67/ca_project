`timescale 1ns/1ps
module forwarding_unit(
    input logic [4:0] rs_ex,
    input logic [4:0] rt_ex,
    input logic [4:0] rd_mem,
    input logic [4:0] rd_wb,
    input logic regwrite_mem,
    input logic regwrite_wb,
    output logic [1:0] forwardA,
    output logic [1:0] forwardB
);

always_comb begin
    forwardA = 2'b00;
    forwardB = 2'b00;

    if(regwrite_mem && (rd_mem != 0) && (rd_mem == rs_ex))
        forwardA = 2'b10;
    else if(regwrite_wb && (rd_wb != 0) && (rd_wb == rs_ex))
        forwardA = 2'b01;

    if(regwrite_mem && (rd_mem != 0) && (rd_mem == rt_ex))
        forwardB = 2'b10;
    else if(regwrite_wb && (rd_wb != 0) && (rd_wb == rt_ex))
        forwardB = 2'b01;
end
endmodule
