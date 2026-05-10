`timescale 1ns/1ps
module hazard_unit(
    input logic memread_ex,
    input logic [4:0] rt_ex,
    input logic [4:0] rs_id,
    input logic [4:0] rt_id,
    output logic stall
);
assign stall = memread_ex && ((rt_ex == rs_id) || (rt_ex == rt_id));
endmodule
