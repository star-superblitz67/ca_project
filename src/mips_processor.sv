`timescale 1ns/1ps

// ============================================================================
// MIPS 5-Stage Pipeline Processor with Cache Interfaces
// ============================================================================
// Architecture: IF → ID → EX → MEM → WB
// Features:
//   - Forwarding unit for RAW hazard resolution (prevents ALU stalls)
//   - Hazard detection for load-use hazards (forces stall on immediate load use)
//   - Branch support (BEQ instruction with predicted PC update)
//   - Separate cache interfaces for instruction (L1I) and data (L1D)
//   - Dual stall signals: if_stall (instruction cache miss) and mem_stall (data cache miss)
// ============================================================================

module mips_pipeline_integrated (
    input  logic        clk,
    input  logic        rst_n,

    // Instruction Fetch to L1I Cache Interface
    output logic        if_cpu_read,           // Request new instruction
    output logic [31:0] if_cpu_addr,           // Instruction address (PC)
    input  logic [31:0] if_cpu_rdata,          // Instruction from cache
    input  logic        if_stall,              // Instruction cache miss (freeze IF stage)

    // Memory Load/Store to L1D Cache Interface
    output logic        mem_cpu_read,          // Read data from cache
    output logic        mem_cpu_write,         // Write data to cache
    output logic [31:0] mem_cpu_addr,          // Memory address (from ALU)
    output logic [31:0] mem_cpu_wdata,         // Data to write
    input  logic [31:0] mem_cpu_rdata,         // Data from cache
    input  logic        mem_stall              // Data cache miss (freeze MEM stage and earlier)
);

    // ========================================================================
    // INSTRUCTION FETCH STAGE - Supplies instructions to pipeline
    // ========================================================================
    logic [31:0] pc;                           // Current program counter
    logic [31:0] pc_next;                      // Next PC value
    logic        branch_taken;                 // Branch condition met
    logic [31:0] branch_addr;                  // Target address for branch

    // PC update logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'b0;
        end else if (!if_stall && !mem_stall) begin
            pc <= pc_next;
        end
    end

    // Next PC calculation
    always_comb begin
        if (branch_taken) begin
            pc_next = branch_addr;
        end else begin
            pc_next = pc + 32'd4;
        end
    end

    assign if_cpu_read = 1'b1;
    assign if_cpu_addr = pc;

    // ========================================================================
    // IF_ID PIPELINE REGISTER
    // ========================================================================
    logic [31:0] if_id_instr;
    logic [31:0] if_id_pc;
    logic        if_id_write;
    logic        if_id_flush;

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

    // ========================================================================
    // INSTRUCTION DECODE STAGE
    // ========================================================================
    logic [5:0]  opcode;
    logic [4:0]  rs;
    logic [4:0]  rt;
    logic [4:0]  rd;
    logic [5:0]  funct;
    logic [15:0] imm_16;
    logic [31:0] imm;

    assign opcode = if_id_instr[31:26];
    assign rs = if_id_instr[25:21];
    assign rt = if_id_instr[20:16];
    assign rd = if_id_instr[15:11];
    assign funct = if_id_instr[5:0];
    assign imm_16 = if_id_instr[15:0];
    assign imm = {{16{imm_16[15]}}, imm_16};

    logic        mem_read;
    logic        mem_write;
    logic        reg_write;
    logic [3:0]  alu_op;

    always_comb begin
        case (opcode)
            6'b000000: begin  // R-type
                case (funct)
                    6'b100000: alu_op = 4'b0000;  // add
                    6'b100010: alu_op = 4'b0001;  // sub
                    6'b100100: alu_op = 4'b0010;  // and
                    6'b100101: alu_op = 4'b0011;  // or
                    6'b101010: alu_op = 4'b0100;  // slt
                    default:   alu_op = 4'b0000;
                endcase
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
                alu_op = 4'b0001;
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

    logic [31:0] rf [0:31];
    logic [31:0] rs_data;
    logic [31:0] rt_data;

    always_comb begin
        if (rs == 5'b00000) rs_data = 32'b0;
        else if (rs == 5'b00001) rs_data = rf[1];
        else if (rs == 5'b00010) rs_data = rf[2];
        else if (rs == 5'b00011) rs_data = rf[3];
        else if (rs == 5'b00100) rs_data = rf[4];
        else if (rs == 5'b00101) rs_data = rf[5];
        else if (rs == 5'b00110) rs_data = rf[6];
        else if (rs == 5'b00111) rs_data = rf[7];
        else if (rs == 5'b01000) rs_data = rf[8];
        else if (rs == 5'b01001) rs_data = rf[9];
        else if (rs == 5'b01010) rs_data = rf[10];
        else if (rs == 5'b01011) rs_data = rf[11];
        else if (rs == 5'b01100) rs_data = rf[12];
        else if (rs == 5'b01101) rs_data = rf[13];
        else if (rs == 5'b01110) rs_data = rf[14];
        else if (rs == 5'b01111) rs_data = rf[15];
        else if (rs == 5'b10000) rs_data = rf[16];
        else if (rs == 5'b10001) rs_data = rf[17];
        else if (rs == 5'b10010) rs_data = rf[18];
        else if (rs == 5'b10011) rs_data = rf[19];
        else if (rs == 5'b10100) rs_data = rf[20];
        else if (rs == 5'b10101) rs_data = rf[21];
        else if (rs == 5'b10110) rs_data = rf[22];
        else if (rs == 5'b10111) rs_data = rf[23];
        else if (rs == 5'b11000) rs_data = rf[24];
        else if (rs == 5'b11001) rs_data = rf[25];
        else if (rs == 5'b11010) rs_data = rf[26];
        else if (rs == 5'b11011) rs_data = rf[27];
        else if (rs == 5'b11100) rs_data = rf[28];
        else if (rs == 5'b11101) rs_data = rf[29];
        else if (rs == 5'b11110) rs_data = rf[30];
        else rs_data = rf[31];

        if (rt == 5'b00000) rt_data = 32'b0;
        else if (rt == 5'b00001) rt_data = rf[1];
        else if (rt == 5'b00010) rt_data = rf[2];
        else if (rt == 5'b00011) rt_data = rf[3];
        else if (rt == 5'b00100) rt_data = rf[4];
        else if (rt == 5'b00101) rt_data = rf[5];
        else if (rt == 5'b00110) rt_data = rf[6];
        else if (rt == 5'b00111) rt_data = rf[7];
        else if (rt == 5'b01000) rt_data = rf[8];
        else if (rt == 5'b01001) rt_data = rf[9];
        else if (rt == 5'b01010) rt_data = rf[10];
        else if (rt == 5'b01011) rt_data = rf[11];
        else if (rt == 5'b01100) rt_data = rf[12];
        else if (rt == 5'b01101) rt_data = rf[13];
        else if (rt == 5'b01110) rt_data = rf[14];
        else if (rt == 5'b01111) rt_data = rf[15];
        else if (rt == 5'b10000) rt_data = rf[16];
        else if (rt == 5'b10001) rt_data = rf[17];
        else if (rt == 5'b10010) rt_data = rf[18];
        else if (rt == 5'b10011) rt_data = rf[19];
        else if (rt == 5'b10100) rt_data = rf[20];
        else if (rt == 5'b10101) rt_data = rf[21];
        else if (rt == 5'b10110) rt_data = rf[22];
        else if (rt == 5'b10111) rt_data = rf[23];
        else if (rt == 5'b11000) rt_data = rf[24];
        else if (rt == 5'b11001) rt_data = rf[25];
        else if (rt == 5'b11010) rt_data = rf[26];
        else if (rt == 5'b11011) rt_data = rf[27];
        else if (rt == 5'b11100) rt_data = rf[28];
        else if (rt == 5'b11101) rt_data = rf[29];
        else if (rt == 5'b11110) rt_data = rf[30];
        else rt_data = rf[31];
    end

    // ========================================================================
    // ID_EX PIPELINE REGISTER
    // ========================================================================
    logic [31:0] id_ex_instr;
    logic [31:0] id_ex_pc;
    logic [31:0] id_ex_a;
    logic [31:0] id_ex_b;
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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_instr <= 32'b0;
            id_ex_pc <= 32'b0;
            id_ex_a <= 32'b0;
            id_ex_b <= 32'b0;
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
                id_ex_a <= 32'b0;
                id_ex_b <= 32'b0;
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
                id_ex_a <= rs_data;
                id_ex_b <= rt_data;
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

    // ========================================================================
    // HAZARD DETECTION
    // ========================================================================
    logic load_use_hazard;

    always_comb begin
        load_use_hazard = id_ex_mem_read && (
            (id_ex_rt == rs) ||
            (id_ex_rt == rt)
        );
    end

    // ========================================================================
    // EXECUTION STAGE
    // ========================================================================
    logic [1:0]  forward_a;
    logic [1:0]  forward_b;

    forwarding_unit forward_inst (
        .ex_mem_rd(ex_mem_rd),
        .ex_mem_reg_write(ex_mem_reg_write),
        .mem_wb_rd(mem_wb_rd),
        .mem_wb_reg_write(mem_wb_reg_write),
        .id_ex_rs(id_ex_rs),
        .id_ex_rt(id_ex_rt),
        .forward_a(forward_a),
        .forward_b(forward_b)
    );

    logic [31:0] alu_a;
    logic [31:0] alu_b;
    logic [31:0] forward_a_ex;
    logic [31:0] forward_b_ex;
    logic [31:0] forward_a_mem;
    logic [31:0] forward_b_mem;

    always_comb begin
        case (forward_a)
            2'b10: alu_a = forward_a_ex;
            2'b01: alu_a = forward_a_mem;
            default: alu_a = id_ex_a;
        endcase

        if (id_ex_opcode == 6'b000000) begin
            case (forward_b)
                2'b10: alu_b = forward_b_ex;
                2'b01: alu_b = forward_b_mem;
                default: alu_b = id_ex_b;
            endcase
        end else begin
            alu_b = id_ex_imm;
        end
    end

    logic [31:0] alu_out;
    logic        zero;

    always_comb begin
        case (id_ex_alu_op)
            4'b0000: alu_out = alu_a + alu_b;
            4'b0001: alu_out = alu_a - alu_b;
            4'b0010: alu_out = alu_a & alu_b;
            4'b0011: alu_out = alu_a | alu_b;
            4'b0111: alu_out = (alu_a < alu_b) ? 32'd1 : 32'd0;
            default: alu_out = alu_a + alu_b;
        endcase
    end

    assign zero = (alu_out == 32'b0);

    always_comb begin
        if (id_ex_opcode == 6'b000100 && zero) begin
            branch_taken = 1'b1;
            branch_addr = id_ex_pc + (id_ex_imm << 2);
        end else begin
            branch_taken = 1'b0;
            branch_addr = 32'b0;
        end
    end

    // ========================================================================
    // EX_MEM PIPELINE REGISTER
    // ========================================================================
    logic [31:0] ex_mem_instr;
    logic [31:0] ex_mem_pc;
    logic [31:0] ex_mem_alu_out;
    logic [31:0] ex_mem_data;
    logic [4:0]  ex_mem_rd;
    logic        ex_mem_mem_read;
    logic        ex_mem_mem_write;
    logic        ex_mem_reg_write;
    logic        ex_mem_flush;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_instr <= 32'b0;
            ex_mem_pc <= 32'b0;
            ex_mem_alu_out <= 32'b0;
            ex_mem_data <= 32'b0;
            ex_mem_rd <= 5'b0;
            ex_mem_mem_read <= 1'b0;
            ex_mem_mem_write <= 1'b0;
            ex_mem_reg_write <= 1'b0;
        end else if (!mem_stall) begin
            ex_mem_instr <= id_ex_instr;
            ex_mem_pc <= id_ex_pc;
            ex_mem_alu_out <= alu_out;
            ex_mem_data <= alu_b;
            ex_mem_rd <= id_ex_rd;
            ex_mem_mem_read <= id_ex_mem_read;
            ex_mem_mem_write <= id_ex_mem_write;
            ex_mem_reg_write <= id_ex_reg_write;
        end
    end

    // ========================================================================
    // MEMORY STAGE
    // ========================================================================
    assign mem_cpu_read = ex_mem_mem_read;
    assign mem_cpu_write = ex_mem_mem_write;
    assign mem_cpu_addr = ex_mem_alu_out;
    assign mem_cpu_wdata = ex_mem_data;

    assign forward_a_ex = ex_mem_alu_out;
    assign forward_b_ex = ex_mem_alu_out;

    // ========================================================================
    // MEM_WB PIPELINE REGISTER
    // ========================================================================
    logic [31:0] mem_wb_instr;
    logic [31:0] mem_wb_pc;
    logic [31:0] mem_wb_alu_out;
    logic [31:0] mem_wb_mem_data;
    logic [4:0]  mem_wb_rd;
    logic        mem_wb_reg_write;
    logic        mem_wb_is_load;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_instr <= 32'b0;
            mem_wb_pc <= 32'b0;
            mem_wb_alu_out <= 32'b0;
            mem_wb_mem_data <= 32'b0;
            mem_wb_rd <= 5'b0;
            mem_wb_reg_write <= 1'b0;
            mem_wb_is_load <= 1'b0;
        end else begin
            mem_wb_instr <= ex_mem_instr;
            mem_wb_pc <= ex_mem_pc;
            mem_wb_alu_out <= ex_mem_alu_out;
            mem_wb_mem_data <= mem_cpu_rdata;
            mem_wb_rd <= ex_mem_rd;
            mem_wb_reg_write <= ex_mem_reg_write;
            mem_wb_is_load <= ex_mem_mem_read;
        end
    end

    assign forward_a_mem = mem_wb_is_load ? mem_wb_mem_data : mem_wb_alu_out;
    assign forward_b_mem = mem_wb_is_load ? mem_wb_mem_data : mem_wb_alu_out;

    // ========================================================================
    // WRITE-BACK STAGE
    // ========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 32; i++) begin
                rf[i] <= 32'b0;
            end
        end else if (mem_wb_reg_write && mem_wb_rd != 5'b0) begin
            if (mem_wb_is_load) begin
                rf[mem_wb_rd] <= mem_wb_mem_data;
            end else begin
                rf[mem_wb_rd] <= mem_wb_alu_out;
            end
        end
    end

endmodule
