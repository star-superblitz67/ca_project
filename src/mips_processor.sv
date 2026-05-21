`timescale 1ns/1ps

// Harris & Harris 5-stage MIPS pipeline with forwarding, stalls, branch flush, and cache hierarchy.
module mips_processor(
    input  logic        clk,
    input  logic        rst,
    // Instruction Memory Interface (to L1I cache)
    output logic        imem_req,
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,
    input  logic        imem_ready,
    // Data Memory Interface (to L1D cache)
    output logic        dmem_req,
    output logic        dmem_we,
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    input  logic [31:0] dmem_rdata,
    input  logic        dmem_ready,
    // GTKWave debug: expose key registers
    output logic [31:0] dbg_r1, dbg_r2, dbg_r3, dbg_r4, dbg_r5, dbg_r6, dbg_r7, dbg_r8, dbg_r9, dbg_r10
);

    // imem_stall: waiting for L1I; dmem_stall: waiting for L1D
    logic imem_stall, dmem_stall, cache_stall;
    logic stall_haz;    // load-use hazard stall
    logic branch_taken;

    assign imem_stall  = imem_req  && !imem_ready;
    assign dmem_stall  = dmem_req  && !dmem_ready;
    assign cache_stall = imem_stall || dmem_stall;

    // Global freeze: any stall stops the entire pipeline advance
    logic pipe_stall;
    assign pipe_stall = cache_stall || stall_haz;

    // Register File (32 x 32-bit)
    logic [31:0] reg_file [0:31];

    logic [31:0] mem_wb_alu_out, mem_wb_read_data;
    logic [4:0]  mem_wb_write_reg;
    logic        mem_wb_regwrite, mem_wb_memtoreg;

    // WB data mux
    logic [31:0] wb_data;
    assign wb_data = mem_wb_memtoreg ? mem_wb_read_data : mem_wb_alu_out;

    // Synchronous write, async read
    integer ri;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (ri = 0; ri < 32; ri = ri + 1)
                reg_file[ri] <= 32'd0;
        end else if (!cache_stall) begin
            if (mem_wb_regwrite && mem_wb_write_reg != 5'd0)
                reg_file[mem_wb_write_reg] <= wb_data;
        end
    end

    // IF Stage – Program Counter
    logic [31:0] pc_reg;
    logic [31:0] branch_target;

    assign imem_req  = !rst;
    assign imem_addr = pc_reg;

    logic jump_taken;
    logic [31:0] jump_target;

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            pc_reg <= 32'd0;
        else if (cache_stall)
            pc_reg <= pc_reg;           // freeze on any cache miss
        else if (branch_taken)
            pc_reg <= branch_target;    // branch redirect
        else if (stall_haz)
            pc_reg <= pc_reg;           // load-use: hold PC
        else if (jump_taken)
            pc_reg <= jump_target;      // jump redirect
        else
            pc_reg <= pc_reg + 32'd4;
    end

    // IF/ID Pipeline Register
    logic [31:0] if_id_pc, if_id_instr;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            if_id_pc    <= 32'd0;
            if_id_instr <= 32'd0;
        end else if (cache_stall) begin
            // freeze – hold current values
            if_id_pc    <= if_id_pc;
            if_id_instr <= if_id_instr;
        end else if (branch_taken) begin
            // flush: insert NOP into ID
            if_id_pc    <= 32'd0;
            if_id_instr <= 32'd0;
        end else if (stall_haz) begin
            // hold: do not accept new instruction
            if_id_pc    <= if_id_pc;
            if_id_instr <= if_id_instr;
        end else if (jump_taken) begin
            // flush IF when jump is taken in ID
            if_id_pc    <= 32'd0;
            if_id_instr <= 32'd0;
        end else begin
            if_id_pc    <= pc_reg;
            if_id_instr <= imem_rdata;
        end
    end

    // ID Stage – Decode + Register Read
    logic [5:0] id_opcode, id_funct;
    logic [4:0] id_rs_addr, id_rt_addr, id_rd_addr;
    logic [31:0] id_imm_ext;

    assign id_opcode  = if_id_instr[31:26];
    assign id_funct   = if_id_instr[5:0];
    assign id_rs_addr = if_id_instr[25:21];
    assign id_rt_addr = if_id_instr[20:16];
    assign id_rd_addr = if_id_instr[15:11];

    logic ctrl_regwrite, ctrl_memtoreg, ctrl_memwrite, ctrl_memread;
    logic ctrl_alusrc, ctrl_regdst, ctrl_branch, ctrl_bne, ctrl_jump;
    logic [2:0] ctrl_aluctrl;

    always_comb begin
        // Safe defaults – NOP behaviour
        ctrl_regwrite = 1'b0;
        ctrl_regdst   = 1'b0;
        ctrl_alusrc   = 1'b0;
        ctrl_memwrite = 1'b0;
        ctrl_memread  = 1'b0;
        ctrl_memtoreg = 1'b0;
        ctrl_branch   = 1'b0;
        ctrl_bne      = 1'b0;
        ctrl_jump     = 1'b0;
        ctrl_aluctrl  = 3'b010;   // ADD

        case (id_opcode)
            6'h00: begin // R-type
                ctrl_regwrite = 1'b1;
                ctrl_regdst   = 1'b1;
                case (id_funct)
                    6'h20: ctrl_aluctrl = 3'b010; // ADD
                    6'h22: ctrl_aluctrl = 3'b110; // SUB
                    6'h24: ctrl_aluctrl = 3'b000; // AND
                    6'h25: ctrl_aluctrl = 3'b001; // OR
                    default: ctrl_aluctrl = 3'b010;
                endcase
            end
            6'h23: begin // LW
                ctrl_regwrite = 1'b1;
                ctrl_memtoreg = 1'b1;
                ctrl_memread  = 1'b1;
                ctrl_alusrc   = 1'b1;
            end
            6'h2B: begin // SW
                ctrl_memwrite = 1'b1;
                ctrl_alusrc   = 1'b1;
            end
            6'h08: begin // ADDI
                ctrl_regwrite = 1'b1;
                ctrl_alusrc   = 1'b1;
                ctrl_aluctrl  = 3'b010;
            end
            6'h0D: begin // ORI
                ctrl_regwrite = 1'b1;
                ctrl_alusrc   = 1'b1;
                ctrl_aluctrl  = 3'b001;
            end
            6'h04: begin // BEQ
                ctrl_branch  = 1'b1;
                ctrl_aluctrl = 3'b110; // SUB for compare
            end
            6'h05: begin // BNE
                ctrl_branch  = 1'b1;
                ctrl_bne     = 1'b1;
                ctrl_aluctrl = 3'b110;
            end
            6'h02: begin // J
                ctrl_jump    = 1'b1;
            end
            default: ; // NOP / unknown → all zeros
        endcase
    end

    // Jump target calculation (resolved in ID)
    assign jump_taken  = ctrl_jump;
    assign jump_target = {if_id_pc[31:28], if_id_instr[25:0], 2'b00};

    // Immediate extension: zero-extend for ORI, sign-extend otherwise
    assign id_imm_ext = (id_opcode == 6'h0D) ? {16'b0, if_id_instr[15:0]}
                                               : {{16{if_id_instr[15]}}, if_id_instr[15:0]};

    // Register read with WB forwarding (handles in-flight WB to ID)
    logic [31:0] id_rs_val, id_rt_val;
    assign id_rs_val = (id_rs_addr == 5'd0) ? 32'd0 :
                       (mem_wb_regwrite && mem_wb_write_reg == id_rs_addr) ? wb_data :
                       reg_file[id_rs_addr];
    assign id_rt_val = (id_rt_addr == 5'd0) ? 32'd0 :
                       (mem_wb_regwrite && mem_wb_write_reg == id_rt_addr) ? wb_data :
                       reg_file[id_rt_addr];

    // ID/EX Pipeline Register
    logic [31:0] id_ex_pc, id_ex_rs_val, id_ex_rt_val, id_ex_imm;
    logic [4:0]  id_ex_rs, id_ex_rt, id_ex_rd;
    logic        id_ex_regwrite, id_ex_memtoreg, id_ex_memwrite, id_ex_memread;
    logic        id_ex_alusrc, id_ex_regdst, id_ex_branch, id_ex_bne;
    logic [2:0]  id_ex_aluctrl;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            id_ex_pc       <= 32'd0;
            id_ex_rs_val   <= 32'd0;
            id_ex_rt_val   <= 32'd0;
            id_ex_imm      <= 32'd0;
            id_ex_rs       <= 5'd0;
            id_ex_rt       <= 5'd0;
            id_ex_rd       <= 5'd0;
            id_ex_regwrite <= 1'b0;
            id_ex_memtoreg <= 1'b0;
            id_ex_memwrite <= 1'b0;
            id_ex_memread  <= 1'b0;
            id_ex_alusrc   <= 1'b0;
            id_ex_regdst   <= 1'b0;
            id_ex_branch   <= 1'b0;
            id_ex_bne      <= 1'b0;
            id_ex_aluctrl  <= 3'b010;
        end else if (cache_stall) begin
            // Freeze entire pipeline
        end else if (branch_taken || stall_haz) begin
            // Flush EX: insert NOP (bubble)
            id_ex_pc       <= 32'd0;
            id_ex_rs_val   <= 32'd0;
            id_ex_rt_val   <= 32'd0;
            id_ex_imm      <= 32'd0;
            id_ex_rs       <= 5'd0;
            id_ex_rt       <= 5'd0;
            id_ex_rd       <= 5'd0;
            id_ex_regwrite <= 1'b0;
            id_ex_memtoreg <= 1'b0;
            id_ex_memwrite <= 1'b0;
            id_ex_memread  <= 1'b0;
            id_ex_alusrc   <= 1'b0;
            id_ex_regdst   <= 1'b0;
            id_ex_branch   <= 1'b0;
            id_ex_bne      <= 1'b0;
            id_ex_aluctrl  <= 3'b010;
        end else begin
            id_ex_pc       <= if_id_pc;
            id_ex_rs_val   <= id_rs_val;
            id_ex_rt_val   <= id_rt_val;
            id_ex_imm      <= id_imm_ext;
            id_ex_rs       <= id_rs_addr;
            id_ex_rt       <= id_rt_addr;
            id_ex_rd       <= id_rd_addr;
            id_ex_regwrite <= ctrl_regwrite;
            id_ex_memtoreg <= ctrl_memtoreg;
            id_ex_memwrite <= ctrl_memwrite;
            id_ex_memread  <= ctrl_memread;
            id_ex_alusrc   <= ctrl_alusrc;
            id_ex_regdst   <= ctrl_regdst;
            id_ex_branch   <= ctrl_branch;
            id_ex_bne      <= ctrl_bne;
            id_ex_aluctrl  <= ctrl_aluctrl;
        end
    end

    // EX Stage – ALU + Forwarding
    logic [1:0] forward_a, forward_b;

    // EX/MEM register (needed by forwarding unit)
    logic [31:0] ex_mem_alu_out, ex_mem_rt_val;
    logic [4:0]  ex_mem_write_reg;
    logic        ex_mem_regwrite, ex_mem_memtoreg, ex_mem_memwrite, ex_mem_memread;

    // Forwarded operand selection
    logic [31:0] fwd_a_val, fwd_b_val;
    always_comb begin
        case (forward_a)
            2'b10:   fwd_a_val = ex_mem_alu_out; // EX hazard
            2'b01:   fwd_a_val = wb_data;         // MEM hazard
            default: fwd_a_val = id_ex_rs_val;    // no hazard
        endcase

        case (forward_b)
            2'b10:   fwd_b_val = ex_mem_alu_out;
            2'b01:   fwd_b_val = wb_data;
            default: fwd_b_val = id_ex_rt_val;
        endcase
    end

    // ALU input B mux (immediate vs register)
    logic [31:0] alu_in_b;
    assign alu_in_b = id_ex_alusrc ? id_ex_imm : fwd_b_val;

    // ALU
    logic [31:0] alu_res;
    always_comb begin
        case (id_ex_aluctrl)
            3'b000:  alu_res = fwd_a_val & alu_in_b;  // AND
            3'b001:  alu_res = fwd_a_val | alu_in_b;  // OR
            3'b010:  alu_res = fwd_a_val + alu_in_b;  // ADD
            3'b110:  alu_res = fwd_a_val - alu_in_b;  // SUB
            default: alu_res = fwd_a_val + alu_in_b;
        endcase
    end

    // Branch decision (resolved in EX stage)
    assign branch_taken  = id_ex_branch && (id_ex_bne ? (alu_res != 32'd0) : (alu_res == 32'd0));
    assign branch_target = id_ex_pc + 32'd4 + {id_ex_imm[29:0], 2'b00}; // imm<<2

    // Destination register mux
    logic [4:0] ex_write_reg;
    assign ex_write_reg = id_ex_regdst ? id_ex_rd : id_ex_rt;

    // EX/MEM Pipeline Register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ex_mem_alu_out   <= 32'd0;
            ex_mem_rt_val    <= 32'd0;
            ex_mem_write_reg <= 5'd0;
            ex_mem_regwrite  <= 1'b0;
            ex_mem_memtoreg  <= 1'b0;
            ex_mem_memwrite  <= 1'b0;
            ex_mem_memread   <= 1'b0;
        end else if (cache_stall) begin
            // Freeze
        end else if (branch_taken) begin
            // Flush MEM stage bubble
            ex_mem_alu_out   <= 32'd0;
            ex_mem_rt_val    <= 32'd0;
            ex_mem_write_reg <= 5'd0;
            ex_mem_regwrite  <= 1'b0;
            ex_mem_memtoreg  <= 1'b0;
            ex_mem_memwrite  <= 1'b0;
            ex_mem_memread   <= 1'b0;
        end else begin
            ex_mem_alu_out   <= alu_res;
            ex_mem_rt_val    <= fwd_b_val;
            ex_mem_write_reg <= ex_write_reg;
            ex_mem_regwrite  <= id_ex_regwrite;
            ex_mem_memtoreg  <= id_ex_memtoreg;
            ex_mem_memwrite  <= id_ex_memwrite;
            ex_mem_memread   <= id_ex_memread;
        end
    end

    // MEM Stage – Data Memory Interface
    assign dmem_req   = ex_mem_memread || ex_mem_memwrite;
    assign dmem_we    = ex_mem_memwrite;
    assign dmem_addr  = ex_mem_alu_out;
    assign dmem_wdata = ex_mem_rt_val;

    // MEM/WB Pipeline Register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_wb_read_data  <= 32'd0;
            mem_wb_alu_out    <= 32'd0;
            mem_wb_write_reg  <= 5'd0;
            mem_wb_regwrite   <= 1'b0;
            mem_wb_memtoreg   <= 1'b0;
        end else if (cache_stall) begin
            // Freeze
        end else begin
            mem_wb_read_data  <= dmem_rdata;
            mem_wb_alu_out    <= ex_mem_alu_out;
            mem_wb_write_reg  <= ex_mem_write_reg;
            mem_wb_regwrite   <= ex_mem_regwrite;
            mem_wb_memtoreg   <= ex_mem_memtoreg;
        end
    end

    // Hazard Unit (load-use detection)
    hazard_unit hu(
        .id_ex_memread (id_ex_memread),
        .id_ex_rt      (id_ex_rt),
        .if_id_rs      (id_rs_addr),
        .if_id_rt      (id_rt_addr),
        .stall         (stall_haz)
    );

    // Forwarding Unit
    forwarding_unit fu(
        .id_ex_rs        (id_ex_rs),
        .id_ex_rt        (id_ex_rt),
        .ex_mem_rd       (ex_mem_write_reg),
        .mem_wb_rd       (mem_wb_write_reg),
        .ex_mem_regwrite (ex_mem_regwrite),
        .mem_wb_regwrite (mem_wb_regwrite),
        .forward_a       (forward_a),
        .forward_b       (forward_b)
    );

    // GTKWave debug outputs
    assign dbg_r1 = reg_file[1];
    assign dbg_r2 = reg_file[2];
    assign dbg_r3 = reg_file[3];
    assign dbg_r4 = reg_file[4];
    assign dbg_r5 = reg_file[5];
    assign dbg_r6 = reg_file[6];
    assign dbg_r7 = reg_file[7];
    assign dbg_r8 = reg_file[8];
    assign dbg_r9 = reg_file[9];
    assign dbg_r10 = reg_file[10];

endmodule
