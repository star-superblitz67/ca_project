`timescale 1ns / 1ps

module hazard_unit (
    input  logic [4:0] rs_ID,
    input  logic [4:0] rt_ID,
    input  logic [4:0] rt_EX,
    input  logic       mem_read_EX,
    input  logic       branch_taken,
    
    output logic       stall_pipeline, // Stalls the PC and IF/ID register
    output logic       flush_ID,       // Flushes the IF/ID register
    output logic       flush_EX        // Flushes the ID/EX register
);

    logic load_use_hazard;
    assign load_use_hazard = mem_read_EX && ((rt_EX == rs_ID) || (rt_EX == rt_ID)) && (rt_EX != 0);

    assign stall_pipeline = load_use_hazard;
    assign flush_EX = load_use_hazard || branch_taken;
    assign flush_ID = branch_taken;

endmodule
