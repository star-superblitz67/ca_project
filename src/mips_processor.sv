`timescale 1ns/1ps

/*
 * Final 5-Stage Pipelined MIPS Processor
 * Features:
 * - Full Hazard Detection (Load-Use stalls)
 * - Forwarding Unit (EX-EX and MEM-EX)
 * - 5 Stages: IF, ID, EX, MEM, WB
 * - Integrated with Multi-level Cache Hierarchy via mem_stall
 */

module mips_processor(
    input logic clk,
    input logic rst,

    // Instruction Memory Interface
    output logic imem_req,
    output logic [31:0] imem_addr,
    input logic [31:0] imem_rdata,
    input logic imem_ready,

    // Data Memory Interface
    output logic dmem_req,
    output logic dmem_we,
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    input logic [31:0] dmem_rdata,
    input logic dmem_ready,

    // Debug Signals for GTKWave
    output logic [31:0] dbg_r1,
    output logic [31:0] dbg_r2,
    output logic [31:0] dbg_r3,
    output logic [31:0] dbg_r4,
    output logic [31:0] dbg_r5,
    output logic [31:0] dbg_r7
);

    // --------------------------------------------------------
    // STALL & ENABLE LOGIC
    // --------------------------------------------------------
    logic mem_stall;
    // Stall if either cache is busy
    assign mem_stall = (imem_req && !imem_ready) || (dmem_req && !dmem_ready);
    
    logic en;
    assign en = !mem_stall; // Global pipeline enable

    // --------------------------------------------------------
    // PIPELINE REGISTERS
    // --------------------------------------------------------
    
    // IF/ID
    logic [31:0] if_id_pc, if_id_instr;

    // ID/EX
    logic [31:0] id_ex_pc, id_ex_rs_val, id_ex_rt_val, id_ex_imm;
    logic [4:0]  id_ex_rs, id_ex_rt, id_ex_rd;
    logic id_ex_regwrite, id_ex_memtoreg, id_ex_memwrite, id_ex_memread, id_ex_alusrc, id_ex_regdst, id_ex_branch, id_ex_bne;
    logic [2:0] id_ex_aluctrl;

    // EX/MEM
    logic [31:0] ex_mem_alu_out, ex_mem_rt_val;
    logic [4:0]  ex_mem_write_reg;
    logic ex_mem_regwrite, ex_mem_memtoreg, ex_mem_memwrite, ex_mem_memread;

    // MEM/WB
    logic [31:0] mem_wb_read_data, mem_wb_alu_out;
    logic [4:0]  mem_wb_write_reg;
    logic mem_wb_regwrite, mem_wb_memtoreg;

    // --------------------------------------------------------
    // REGISTER FILE & WB STAGE
    // --------------------------------------------------------
    logic [31:0] reg_file [0:31];
    logic [31:0] wb_data;
    
    assign wb_data = mem_wb_memtoreg ? mem_wb_read_data : mem_wb_alu_out;

    initial begin
        for(int i=0; i<32; i++) reg_file[i] = 0;
    end

    always_ff @(posedge clk) begin
        if (en && mem_wb_regwrite && mem_wb_write_reg != 0) begin
            reg_file[mem_wb_write_reg] <= wb_data;
        end
    end

    // Debug Mapping
    assign dbg_r1 = reg_file[1];
    assign dbg_r2 = reg_file[2];
    assign dbg_r3 = reg_file[3];
    assign dbg_r4 = reg_file[4];
    assign dbg_r5 = reg_file[5];
    assign dbg_r7 = reg_file[7];

    // --------------------------------------------------------
    // IF STAGE
    // --------------------------------------------------------
    logic [31:0] pc_reg, next_pc, branch_target;
    logic branch_taken;

    assign imem_req = !rst;
    assign imem_addr = pc_reg;
    assign next_pc = branch_taken ? branch_target : pc_reg + 4;

    // --------------------------------------------------------
    // ID STAGE
    // --------------------------------------------------------
    logic [5:0] opcode = if_id_instr[31:26];
    logic [5:0] funct  = if_id_instr[5:0];
    logic [4:0] rs_addr = if_id_instr[25:21];
    logic [4:0] rt_addr = if_id_instr[20:16];
    logic [4:0] rd_addr = if_id_instr[15:11];

    logic ctrl_regwrite, ctrl_memtoreg, ctrl_memwrite, ctrl_memread, ctrl_alusrc, ctrl_regdst, ctrl_branch, ctrl_bne;
    logic [2:0] ctrl_aluctrl;

    always_comb begin
        {ctrl_regwrite, ctrl_regdst, ctrl_alusrc, ctrl_memwrite, ctrl_memread, ctrl_memtoreg, ctrl_branch, ctrl_bne} = 8'b0;
        ctrl_aluctrl = 3'b010; // Default ADD
        case(opcode)
            6'h00: begin // R-type
                ctrl_regwrite = 1; ctrl_regdst = 1;
                case(funct)
                    6'h20: ctrl_aluctrl = 3'b010; // ADD
                    6'h22: ctrl_aluctrl = 3'b110; // SUB
                    6'h24: ctrl_aluctrl = 3'b000; // AND
                    6'h25: ctrl_aluctrl = 3'b001; // OR
                    6'h2A: ctrl_aluctrl = 3'b111; // SLT
                endcase
            end
            6'h23: begin ctrl_regwrite = 1; ctrl_memtoreg = 1; ctrl_memread = 1; ctrl_alusrc = 1; end // LW
            6'h2B: begin ctrl_memwrite = 1; ctrl_alusrc = 1; end // SW
            6'h08: begin ctrl_regwrite = 1; ctrl_alusrc = 1; end // ADDI
            6'h0D: begin ctrl_regwrite = 1; ctrl_alusrc = 1; ctrl_aluctrl = 3'b001; end // ORI
            6'h04: begin ctrl_branch = 1; ctrl_aluctrl = 3'b110; end // BEQ
            6'h05: begin ctrl_branch = 1; ctrl_bne = 1; ctrl_aluctrl = 3'b110; end // BNE
        endcase
    end

    logic [31:0] imm_ext = (opcode == 6'h0D) ? {16'b0, if_id_instr[15:0]} : {{16{if_id_instr[15]}}, if_id_instr[15:0]};
    
    // ID Stage Forwarding (for branches if needed, but here we do it in EX)
    logic [31:0] rs_val = (rs_addr == 0) ? 0 : 
                         (mem_wb_regwrite && mem_wb_write_reg == rs_addr) ? wb_data : reg_file[rs_addr];
    logic [31:0] rt_val = (rt_addr == 0) ? 0 : 
                         (mem_wb_regwrite && mem_wb_write_reg == rt_addr) ? wb_data : reg_file[rt_addr];

    // --------------------------------------------------------
    // EX STAGE
    // --------------------------------------------------------
    logic [1:0] forward_a, forward_b;
    logic [31:0] fwd_a_val, fwd_b_val;

    always_comb begin
        case(forward_a)
            2'b10: fwd_a_val = ex_mem_alu_out;
            2'b01: fwd_a_val = wb_data;
            default: fwd_a_val = id_ex_rs_val;
        endcase
        case(forward_b)
            2'b10: fwd_b_val = ex_mem_alu_out;
            2'b01: fwd_b_val = wb_data;
            default: fwd_b_val = id_ex_rt_val;
        endcase
    end

    logic [31:0] alu_in2 = id_ex_alusrc ? id_ex_imm : fwd_b_val;
    logic [31:0] alu_res;

    always_comb begin
        case(id_ex_aluctrl)
            3'b000: alu_res = fwd_a_val & alu_in2;
            3'b001: alu_res = fwd_a_val | alu_in2;
            3'b010: alu_res = fwd_a_val + alu_in2;
            3'b110: alu_res = fwd_a_val - alu_in2;
            3'b111: alu_res = ($signed(fwd_a_val) < $signed(alu_in2)) ? 1 : 0;
            default: alu_res = fwd_a_val + alu_in2;
        endcase
    end

    assign branch_taken = id_ex_branch && (id_ex_bne ? (alu_res != 0) : (alu_res == 0));
    assign branch_target = id_ex_pc + 4 + (id_ex_imm << 2);

    // --------------------------------------------------------
    // MEM STAGE
    // --------------------------------------------------------
    assign dmem_req = ex_mem_memread || ex_mem_memwrite;
    assign dmem_we  = ex_mem_memwrite;
    assign dmem_addr = ex_mem_alu_out;
    assign dmem_wdata = ex_mem_rt_val;

    // --------------------------------------------------------
    // PIPELINE CONTROL
    // --------------------------------------------------------
    logic stall_haz;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pc_reg <= 0;
            if_id_instr <= 0;
            id_ex_regwrite <= 0;
            ex_mem_regwrite <= 0;
            mem_wb_regwrite <= 0;
        end else if (en) begin
            // 1. Handle IF/ID
            if (branch_taken) begin
                pc_reg <= next_pc;
                if_id_instr <= 0; // Flush
            end else if (stall_haz) begin
                // PC and IF/ID don't update
            end else begin
                pc_reg <= next_pc;
                if_id_pc <= pc_reg + 4;
                if_id_instr <= imem_rdata;
            end

            // 2. Handle ID/EX
            if (branch_taken || stall_haz) begin
                id_ex_regwrite <= 0;
                id_ex_memread <= 0;
                id_ex_memwrite <= 0;
                id_ex_branch <= 0;
            end else begin
                id_ex_pc <= if_id_pc;
                id_ex_rs_val <= rs_val;
                id_ex_rt_val <= rt_val;
                id_ex_rs <= rs_addr;
                id_ex_rt <= rt_addr;
                id_ex_rd <= rd_addr;
                id_ex_imm <= imm_ext;
                id_ex_regwrite <= ctrl_regwrite;
                id_ex_regdst <= ctrl_regdst;
                id_ex_alusrc <= ctrl_alusrc;
                id_ex_memread <= ctrl_memread;
                id_ex_memwrite <= ctrl_memwrite;
                id_ex_memtoreg <= ctrl_memtoreg;
                id_ex_aluctrl <= ctrl_aluctrl;
                id_ex_branch <= ctrl_branch;
                id_ex_bne <= ctrl_bne;
            end

            // 3. Handle EX/MEM (Always advance if en is 1)
            ex_mem_alu_out <= alu_res;
            ex_mem_rt_val <= fwd_b_val;
            ex_mem_write_reg <= id_ex_regdst ? id_ex_rd : id_ex_rt;
            ex_mem_regwrite <= id_ex_regwrite;
            ex_mem_memread <= id_ex_memread;
            ex_mem_memwrite <= id_ex_memwrite;
            ex_mem_memtoreg <= id_ex_memtoreg;

            // 4. Handle MEM/WB (Always advance if en is 1)
            mem_wb_read_data <= dmem_rdata;
            mem_wb_alu_out <= ex_mem_alu_out;
            mem_wb_write_reg <= ex_mem_write_reg;
            mem_wb_regwrite <= ex_mem_regwrite;
            mem_wb_memtoreg <= ex_mem_memtoreg;
        end
    end

    // --------------------------------------------------------
    // SUB-MODULES
    // --------------------------------------------------------
    hazard_unit hu(
        .id_ex_memread(id_ex_memread),
        .id_ex_rt(id_ex_rt),
        .if_id_rs(rs_addr),
        .if_id_rt(rt_addr),
        .stall(stall_haz)
    );

    forwarding_unit fu(
        .id_ex_rs(id_ex_rs),
        .id_ex_rt(id_ex_rt),
        .ex_mem_rd(ex_mem_write_reg),
        .mem_wb_rd(mem_wb_write_reg),
        .ex_mem_regwrite(ex_mem_regwrite),
        .mem_wb_regwrite(mem_wb_regwrite),
        .forward_a(forward_a),
        .forward_b(forward_b)
    );

endmodule
