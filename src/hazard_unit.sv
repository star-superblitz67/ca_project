`timescale 1ns/1ps
// Hazard Unit – detects load-use hazards and stalls the pipeline for one cycle.
module hazard_unit(
    input logic id_ex_memread,
    input logic [4:0] id_ex_rt,
    input logic [4:0] if_id_rs,
    input logic [4:0] if_id_rt,
    output logic stall
);

    // Stall if EX stage is a LW and its dest matches either source in ID
    assign stall = id_ex_memread && 
                   ((id_ex_rt == if_id_rs) || (id_ex_rt == if_id_rt)) && 
                   (id_ex_rt != 0);

endmodule