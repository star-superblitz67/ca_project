`timescale 1ns/1ps

/**
 * Forwarding Unit
 * Resolves data hazards by bypassing results from EX/MEM and MEM/WB stages.
 */
module forwarding_unit(
    input logic [4:0] id_ex_rs,
    input logic [4:0] id_ex_rt,
    input logic [4:0] ex_mem_rd,
    input logic [4:0] mem_wb_rd,
    input logic ex_mem_regwrite,
    input logic mem_wb_regwrite,
    output logic [1:0] forward_a,
    output logic [1:0] forward_b
);

    always_comb begin
        // --- Forwarding for ALU Operand A ---
        forward_a = 2'b00;
        // 1. EX Hazard (Priority)
        if (ex_mem_regwrite && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs))
            forward_a = 2'b10;
        // 2. MEM Hazard
        else if (mem_wb_regwrite && (mem_wb_rd != 0) && (mem_wb_rd == id_ex_rs))
            forward_a = 2'b01;

        // --- Forwarding for ALU Operand B ---
        forward_b = 2'b00;
        // 1. EX Hazard (Priority)
        if (ex_mem_regwrite && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rt))
            forward_b = 2'b10;
        // 2. MEM Hazard
        else if (mem_wb_regwrite && (mem_wb_rd != 0) && (mem_wb_rd == id_ex_rt))
            forward_b = 2'b01;
    end

endmodule