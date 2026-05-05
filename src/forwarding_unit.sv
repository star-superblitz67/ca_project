// ============================================================================
// Forwarding Unit: Data Hazard Resolution  
// ============================================================================
// Purpose: Detects Read-After-Write (RAW) data dependencies and forwards results
//          from execution and memory stages to prevent stalling on ALU hazards
//
// Strategy: Compare source registers of current instruction with destination 
//           registers of pending writes. Forward result if match found.
//
// Priority: EX_MEM result (highest) > MEM_WB result > use register file (lowest)
//           Highest priority forwarding prevents data corruption when RAW chain
//           exists (e.g., add $1,$2,$3; addi $2,$1,10; must use new $1 value)
//
// Limitations: Cannot resolve load-use hazard (data from memory not ready in EX)
//              Must stall pipeline for immediate use of load result
// ============================================================================

module forwarding_unit (
    input  logic [4:0]  ex_mem_rd,             // Destination register from EX_MEM stage
    input  logic        ex_mem_reg_write,     // Write-enable for EX_MEM destination register
    input  logic [4:0]  mem_wb_rd,             // Destination register from MEM_WB stage
    input  logic        mem_wb_reg_write,     // Write-enable for MEM_WB destination register
    input  logic [4:0]  id_ex_rs,             // Source register address for operand A
    input  logic [4:0]  id_ex_rt,             // Source register address for operand B
    output logic [1:0]  forward_a,            // Operand A forwarding selector
    output logic [1:0]  forward_b             // Operand B forwarding selector
    // forward_a/b encoding: 2'b10 = EX_MEM result, 2'b01 = MEM_WB result, 2'b00 = no forward
);

    // Operand A: Detect if source register matches any pending write destination
    always_comb begin
        // EX_MEM stage has highest priority (result most recent)
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs)) begin
            forward_a = 2'b10;  // Forward from ALU result (execution just completed)
        // MEM_WB stage has second priority
        end else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs)) begin
            forward_a = 2'b01;  // Forward from memory/ALU result (write-back this cycle)
        // No match - use value from register file
        end else begin
            forward_a = 2'b00;  // No forwarding needed
        end
    end

    // Operand B: Detect if source register matches any pending write destination
    always_comb begin
        // EX_MEM stage has highest priority (result most recent)
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rt)) begin
            forward_b = 2'b10;  // Forward from ALU result (execution just completed)
        // MEM_WB stage has second priority
        end else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rt)) begin
            forward_b = 2'b01;  // Forward from memory/ALU result (write-back this cycle)
        // No match - use value from register file
        end else begin
            forward_b = 2'b00;  // No forwarding needed
        end
    end

endmodule
