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

    // We need to catch load-use hazards here. If the instruction in the EX stage is reading from memory,
    // and the instruction in the ID stage needs that exact data, we have to stall for a cycle to let the load finish.
    // We also make sure we aren't checking register 0, since it's hardwired to 0.
    logic load_use_hazard;
    assign load_use_hazard = mem_read_EX && ((rt_EX == rs_ID) || (rt_EX == rt_ID)) && (rt_EX != 0);

    // If we detect a load-use hazard, tell the pipeline to hit the brakes.
    assign stall_pipeline = load_use_hazard;

    // Flushing is basically throwing away an instruction.
    // If we have a load-use hazard, we stalled the earlier stages, but the instruction moving into EX needs to be a bubble (NOP).
    // If a branch is taken, the instruction we just fetched is the wrong one, so we flush ID.
    assign flush_EX = load_use_hazard || branch_taken;
    assign flush_ID = branch_taken;

endmodule
