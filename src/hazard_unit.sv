`timescale 1ns/1ps

/**
 * Hazard Unit
 * Detects Load-Use hazards and stalls the pipeline.
 */
module hazard_unit(
    input logic id_ex_memread,
    input logic [4:0] id_ex_rt,
    input logic [4:0] if_id_rs,
    input logic [4:0] if_id_rt,
    output logic stall
);

    // Load-Use Hazard:
    // If the instruction in EX is a Load (LW) and its target register
    // is one of the source registers of the instruction in ID.
    assign stall = id_ex_memread && 
                   ((id_ex_rt == if_id_rs) || (id_ex_rt == if_id_rt)) && 
                   (id_ex_rt != 0);

endmodule