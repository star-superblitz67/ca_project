`timescale 1ns / 1ps

module hazard_unit (
    input  logic [4:0] rs_ID,
    input  logic [4:0] rt_ID,
    input  logic [4:0] rt_EX,
    input  logic       mem_read_EX,
    input  logic       branch_taken,
    
    output logic       stall_pipeline, // Stalls PC and IF/ID
    output logic       flush_ID,       // Flushes IF/ID
    output logic       flush_EX        // Flushes ID/EX
);

    // Detect Load-Use hazard: Stall if the EX stage is loading data that the ID stage needs.
    // Ignores $zero (register 0) as it cannot be overwritten.
    logic load_use_hazard;
    assign load_use_hazard = mem_read_EX && ((rt_EX == rs_ID) || (rt_EX == rt_ID)) && (rt_EX != 0);

    // Pause PC and IF/ID registers for 1 cycle to allow memory read to complete
    assign stall_pipeline = load_use_hazard;

    // Flush EX to insert a NOP on a load-use hazard.
    // Flush ID (and EX) on a taken branch to discard the incorrectly fetched instruction.
    assign flush_EX = load_use_hazard || branch_taken;
    assign flush_ID = branch_taken;

endmodule
