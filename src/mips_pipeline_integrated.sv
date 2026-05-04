`timescale 1ns/1ps

module mips_pipeline_integrated (
    input  logic        clk,
    input  logic        rst_n,

    // L1I Cache Interface (IF stage)
    output logic        if_cpu_read,
    output logic [31:0] if_cpu_addr,
    input  logic [31:0] if_cpu_rdata,
    input  logic        if_stall,

    // L1D Cache Interface (MEM stage)
    output logic        mem_cpu_read,
    output logic        mem_cpu_write,
    output logic [31:0] mem_cpu_addr,
    output logic [31:0] mem_cpu_wdata,
    input  logic [31:0] mem_cpu_rdata,
    input  logic        mem_stall
);

    // 5-stage pipeline registers
    logic [31:0] pc;
    logic [31:0] pc_next;
    logic [31:0] pc_write_data;

    // IF_ID register
    logic [31:0] if_id_instr;
    logic [31:0] if_id_pc;
    logic        if_id_write;
    logic        if_id_flush;

    // ID_EX register
    logic [31:0] id_ex_instr;
    logic [31:0] id_ex_pc;
    logic [31:0] id_ex_rs_data;
    logic [31:0] id_ex_rt_data;
    logic [31:0] id_ex_imm;
    logic [5:0]  id_ex_opcode;
    logic [5:0]  id_ex_funct;
    logic [4:0]  id_ex_rs;
    logic [4:0]  id_ex_rt;
    logic [4:0]  id_ex_rd;
    logic [3:0]  id_ex_alu_op;
    logic        id_ex_mem_read;
    logic        id_ex_mem_write;
    logic        id_ex_reg_write;
    logic        id_ex_flush;

    // EX_MEM register
    logic [31:0] ex_mem_instr;
    logic [31:0] ex_mem_pc;
    logic [31:0] ex_mem_alu_result;
    logic [31:0] ex_mem_rt_data;
    logic [4:0]  ex_mem_rd;
    logic        ex_mem_mem_read;
    logic        ex_mem_mem_write;
    logic        ex_mem_reg_write;
    logic        ex_mem_flush;

    // MEM_WB register
    logic [31:0] mem_wb_instr;
    logic [31:0] mem_wb_pc;
    logic [31:0] mem_wb_alu_result;
    logic [31:0] mem_wb_mem_data;
    logic [4:0]  mem_wb_rd;
    logic        mem_wb_reg_write;
    logic        mem_wb_is_load;

    // Register file
    logic [31:0] regs [0:31];

    // Decode signals
    logic [5:0]  opcode;
    logic [4:0]  rs;
    logic [4:0]  rt;
    logic [4:0]  rd;
    logic [5:0]  funct;
    logic [15:0] imm_16;
    logic [31:0] imm;

    // Control signals
    logic        mem_read;
    logic        mem_write;
    logic        reg_write;
    logic [3:0]  alu_op;

    // ALU signals
    logic [31:0] alu_a;
    logic [31:0] alu_b;
    logic [31:0] alu_result;
    logic        zero;

    // Hazard detection
    logic        load_use_hazard;
    logic        pc_write;
    logic        branch_taken;
    logic [31:0] branch_target;

    // Forwarding
    logic [1:0]  forward_a;
    logic [1:0]  forward_b;
    logic [31:0] forwarded_a;
    logic [31:0] forwarded_b;

    // ====== INSTRUCTION FETCH STAGE ======
    always_comb begin
        if_cpu_read = 1'b1;  // Always request instruction
        if_cpu_addr = pc;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'b0;
        end else if (pc_write && !if_stall && !mem_stall) begin
            pc <= pc_next;
        end
    end

    always_comb begin
        if (branch_taken) begin
            pc_next = branch_target;
        end else begin
            pc_next = pc + 32'd4;
        end
        pc_write = 1'b1;  // Always want to advance
    end

    // IF_ID pipeline register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_instr <= 32'b0;
            if_id_pc <= 32'b0;
        end else if ((if_id_write || if_id_flush) && !mem_stall) begin
            if (if_id_flush) begin
                if_id_instr <= 32'b0;
                if_id_pc <= 32'b0;
            end else begin
                if_id_instr <= if_cpu_rdata;
                if_id_pc <= pc;
            end
        end
    end

    always_comb begin
        if_id_write = ~(load_use_hazard | if_stall | mem_stall);
        if_id_flush = branch_taken | load_use_hazard;
    end

    // ====== INSTRUCTION DECODE STAGE ======
    assign opcode = if_id_instr[31:26];
    assign rs = if_id_instr[25:21];
    assign rt = if_id_instr[20:16];
    assign rd = if_id_instr[15:11];
    assign funct = if_id_instr[5:0];
    assign imm_16 = if_id_instr[15:0];

    // Sign-extend immediate
    assign imm = {{16{imm_16[15]}}, imm_16};

    // Control logic
    always_comb begin
        case (opcode)
            6'b000000: begin  // R-type
                alu_op = {funct[3:2], funct[1:0]};  // add(00), sub(01), and(10), or(11)
                mem_read = 1'b0;
                mem_write = 1'b0;
                reg_write = 1'b1;
            end
            6'b001000: begin  // addi
                alu_op = 4'b0000;
                mem_read = 1'b0;
                mem_write = 1'b0;
                reg_write = 1'b1;
            end
            6'b100011: begin  // lw
                alu_op = 4'b0000;
                mem_read = 1'b1;
                mem_write = 1'b0;
                reg_write = 1'b1;
            end
            6'b101011: begin  // sw
                alu_op = 4'b0000;
                mem_read = 1'b0;
                mem_write = 1'b1;
                reg_write = 1'b0;
            end
            6'b000100: begin  // beq
                alu_op = 4'b0001;  // sub
                mem_read = 1'b0;
                mem_write = 1'b0;
                reg_write = 1'b0;
            end
            default: begin
                alu_op = 4'b0000;
                mem_read = 1'b0;
                mem_write = 1'b0;
                reg_write = 1'b0;
            end
        endcase
    end

    // Register file read
    logic [31:0] rs_data;
    logic [31:0] rt_data;

    always_comb begin
        rs_data = (rs == 5'b0) ? 32'b0 : regs[rs];
        rt_data = (rt == 5'b0) ? 32'b0 : regs[rt];
    end

    // ID_EX pipeline register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_instr <= 32'b0;
            id_ex_pc <= 32'b0;
            id_ex_rs_data <= 32'b0;
            id_ex_rt_data <= 32'b0;
            id_ex_imm <= 32'b0;
            id_ex_opcode <= 6'b0;
            id_ex_funct <= 6'b0;
            id_ex_rs <= 5'b0;
            id_ex_rt <= 5'b0;
            id_ex_rd <= 5'b0;
            id_ex_alu_op <= 4'b0;
            id_ex_mem_read <= 1'b0;
            id_ex_mem_write <= 1'b0;
            id_ex_reg_write <= 1'b0;
        end else if (!mem_stall) begin
            if (id_ex_flush) begin
                id_ex_instr <= 32'b0;
                id_ex_pc <= 32'b0;
                id_ex_rs_data <= 32'b0;
                id_ex_rt_data <= 32'b0;
                id_ex_imm <= 32'b0;
                id_ex_opcode <= 6'b0;
                id_ex_funct <= 6'b0;
                id_ex_rs <= 5'b0;
                id_ex_rt <= 5'b0;
                id_ex_rd <= 5'b0;
                id_ex_alu_op <= 4'b0;
                id_ex_mem_read <= 1'b0;
                id_ex_mem_write <= 1'b0;
                id_ex_reg_write <= 1'b0;
            end else begin
                id_ex_instr <= if_id_instr;
                id_ex_pc <= if_id_pc;
                id_ex_rs_data <= rs_data;
                id_ex_rt_data <= rt_data;
                id_ex_imm <= imm;
                id_ex_opcode <= opcode;
                id_ex_funct <= funct;
                id_ex_rs <= rs;
                id_ex_rt <= rt;
                id_ex_rd <= rd;
                id_ex_alu_op <= alu_op;
                id_ex_mem_read <= mem_read;
                id_ex_mem_write <= mem_write;
                id_ex_reg_write <= reg_write;
            end
        end
    end

    assign id_ex_flush = branch_taken | load_use_hazard;

    // ====== HAZARD DETECTION ======
    // Load-use hazard: if ID_EX will read memory and result is needed by IF_ID
    always_comb begin
        load_use_hazard = id_ex_mem_read && ((id_ex_rt == rs) || (id_ex_rt == rt));
    end

    // ====== EXECUTION STAGE ======
    // Forwarding multiplexers
    forwarding_unit forward_inst (
        .ex_mem_rd_addr(ex_mem_rd),
        .ex_mem_reg_write(ex_mem_reg_write),
        .mem_wb_rd_addr(mem_wb_rd),
        .mem_wb_reg_write(mem_wb_reg_write),
        .id_ex_rs(id_ex_rs),
        .id_ex_rt(id_ex_rt),
        .forward_a(forward_a),
        .forward_b(forward_b)
    );

    always_comb begin
        case (forward_a)
            2'b10: forwarded_a = ex_mem_alu_result;
            2'b01: forwarded_a = mem_wb_alu_result;
            default: forwarded_a = id_ex_rs_data;
        endcase

        case (forward_b)
            2'b10: forwarded_b = ex_mem_alu_result;
            2'b01: forwarded_b = mem_wb_alu_result;
            default: forwarded_b = id_ex_rt_data;
        endcase
    end

    // ALU input selection (R-type uses registers, I-type uses immediate)
    always_comb begin
        alu_a = forwarded_a;

        if (id_ex_opcode == 6'b000000) begin  // R-type
            alu_b = forwarded_b;
        end else begin  // I-type
            alu_b = id_ex_imm;
        end
    end

    // ALU
    always_comb begin
        case (id_ex_alu_op)
            4'b0000: alu_result = alu_a + alu_b;           // add
            4'b0001: alu_result = alu_a - alu_b;           // sub / beq comparison
            4'b0010: alu_result = alu_a & alu_b;           // and
            4'b0011: alu_result = alu_a | alu_b;           // or
            4'b0111: alu_result = (alu_a < alu_b) ? 32'd1 : 32'd0; // slt
            default: alu_result = alu_a + alu_b;
        endcase
    end

    assign zero = (alu_result == 32'b0);

    // Branch logic
    always_comb begin
        if (id_ex_opcode == 6'b000100 && zero) begin  // beq and zero
            branch_taken = 1'b1;
            branch_target = id_ex_pc + (id_ex_imm << 2);
        end else begin
            branch_taken = 1'b0;
            branch_target = 32'b0;
        end
    end

    // EX_MEM pipeline register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_instr <= 32'b0;
            ex_mem_pc <= 32'b0;
            ex_mem_alu_result <= 32'b0;
            ex_mem_rt_data <= 32'b0;
            ex_mem_rd <= 5'b0;
            ex_mem_mem_read <= 1'b0;
            ex_mem_mem_write <= 1'b0;
            ex_mem_reg_write <= 1'b0;
        end else if (!mem_stall) begin
            ex_mem_instr <= id_ex_instr;
            ex_mem_pc <= id_ex_pc;
            ex_mem_alu_result <= alu_result;
            ex_mem_rt_data <= forwarded_b;
            ex_mem_rd <= id_ex_rd;
            ex_mem_mem_read <= id_ex_mem_read;
            ex_mem_mem_write <= id_ex_mem_write;
            ex_mem_reg_write <= id_ex_reg_write;
        end
    end

    // ====== MEMORY STAGE ======
    always_comb begin
        mem_cpu_read = ex_mem_mem_read;
        mem_cpu_write = ex_mem_mem_write;
        mem_cpu_addr = ex_mem_alu_result;
        mem_cpu_wdata = ex_mem_rt_data;
    end

    // MEM_WB pipeline register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_instr <= 32'b0;
            mem_wb_pc <= 32'b0;
            mem_wb_alu_result <= 32'b0;
            mem_wb_mem_data <= 32'b0;
            mem_wb_rd <= 5'b0;
            mem_wb_reg_write <= 1'b0;
            mem_wb_is_load <= 1'b0;
        end else begin
            mem_wb_instr <= ex_mem_instr;
            mem_wb_pc <= ex_mem_pc;
            mem_wb_alu_result <= ex_mem_alu_result;
            mem_wb_mem_data <= mem_cpu_rdata;
            mem_wb_rd <= ex_mem_rd;
            mem_wb_reg_write <= ex_mem_reg_write;
            mem_wb_is_load <= ex_mem_mem_read;
        end
    end

    // ====== WRITE-BACK STAGE ======
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 32; i++) begin
                regs[i] <= 32'b0;
            end
        end else if (mem_wb_reg_write && mem_wb_rd != 5'b0) begin
            if (mem_wb_is_load) begin
                regs[mem_wb_rd] <= mem_wb_mem_data;
            end else begin
                regs[mem_wb_rd] <= mem_wb_alu_result;
            end
        end
    end

endmodule
