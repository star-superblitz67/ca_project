module mips_pipeline (
    input  logic        clk,
    input  logic        rst_n,
    output logic [31:0] pc_out,
    output logic [31:0] alu_result
);

    logic [31:0] pc, next_pc;
    logic [31:0] if_id_instr, id_ex_instr, ex_mem_instr, mem_wb_instr;
    logic [31:0] if_id_pc, id_ex_pc, ex_mem_pc, mem_wb_pc;
    logic [31:0] id_ex_read_data1, id_ex_read_data2;
    logic [31:0] ex_mem_read_data1, ex_mem_read_data2;
    logic [31:0] mem_wb_read_data1, mem_wb_read_data2;
    logic [31:0] ex_mem_alu_result, mem_wb_alu_result;
    logic [31:0] ex_mem_wdata, mem_wb_wdata;
    logic [31:0] mem_wb_wdata_mem;
    logic [31:0] wb_data;
    logic [4:0]  if_id_rs, if_id_rt, if_id_rd;
    logic [4:0]  id_ex_rs, id_ex_rt, id_ex_rd;
    logic [4:0]  ex_mem_rd, ex_mem_rd_addr;
    logic [4:0]  mem_wb_rd, mem_wb_rd_addr;
    logic [1:0]  forward_a, forward_b;
    logic [31:0] alu_a, alu_b;
    logic [31:0] alu_result_next;
    logic        reg_write, mem_read, mem_write;
    logic [2:0]  alu_op;
    logic        ex_mem_reg_write, ex_mem_mem_read, ex_mem_mem_write;
    logic        mem_wb_reg_write, mem_wb_mem_read, mem_wb_mem_write;
    logic        id_ex_mem_read, id_ex_mem_write;
    logic        pc_write, if_id_write, id_ex_flush;
    logic        branch, jump;
    logic [31:0] branch_target;
    logic        branch_taken;
    logic        cache_stall;

    logic [31:0] instruction_mem [0:1023];
    logic [31:0] data_mem [0:1023];
    logic [31:0] register_file [0:31];
    integer i;
    logic [11:2] data_mem_addr;

    assign pc_out = pc;
    assign cache_stall = 1'b0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'd0;
        end else if (pc_write) begin
            if (branch_taken)
                pc <= branch_target;
            else if (jump)
                pc <= {if_id_pc[31:28], if_id_instr[25:0], 2'b00};
            else
                pc <= next_pc;
        end
    end

    assign next_pc = pc + 32'd4;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_instr <= 32'd0;
            if_id_pc <= 32'd0;
        end else if (if_id_write) begin
            if_id_instr <= instruction_mem[pc[11:2]];
            if_id_pc <= pc;
        end else if (id_ex_flush) begin
            if_id_instr <= 32'd0;
            if_id_pc <= if_id_pc;
        end
    end

    assign if_id_rs = if_id_instr[25:21];
    assign if_id_rt = if_id_instr[20:16];
    assign if_id_rd = if_id_instr[15:11];

    logic ctrl_reg_write, ctrl_mem_read, ctrl_mem_write;
    logic [2:0] ctrl_alu_op;
    logic ctrl_branch, ctrl_jump;

    always @(*) begin
        case (if_id_instr[31:26])
            6'b000000: begin
                ctrl_reg_write = 1'b1;
                ctrl_mem_read = 1'b0;
                ctrl_mem_write = 1'b0;
                ctrl_alu_op = 3'd0;
                ctrl_branch = 1'b0;
                ctrl_jump = 1'b0;
                case (if_id_instr[5:0])
                    6'b100000: ctrl_alu_op = 3'd0;
                    6'b100010: ctrl_alu_op = 3'd1;
                    6'b100100: ctrl_alu_op = 3'd2;
                    6'b100101: ctrl_alu_op = 3'd3;
                    6'b101010: ctrl_alu_op = 3'd4;
                    default: ctrl_alu_op = 3'd0;
                endcase
            end
            6'b100011: begin
                ctrl_reg_write = 1'b1;
                ctrl_mem_read = 1'b1;
                ctrl_mem_write = 1'b0;
                ctrl_alu_op = 3'd0;
                ctrl_branch = 1'b0;
                ctrl_jump = 1'b0;
            end
            6'b101011: begin
                ctrl_reg_write = 1'b0;
                ctrl_mem_read = 1'b0;
                ctrl_mem_write = 1'b1;
                ctrl_alu_op = 3'd0;
                ctrl_branch = 1'b0;
                ctrl_jump = 1'b0;
            end
            6'b001000: begin
                ctrl_reg_write = 1'b1;
                ctrl_mem_read = 1'b0;
                ctrl_mem_write = 1'b0;
                ctrl_alu_op = 3'd5;
                ctrl_branch = 1'b0;
                ctrl_jump = 1'b0;
            end
            6'b000100: begin
                ctrl_reg_write = 1'b0;
                ctrl_mem_read = 1'b0;
                ctrl_mem_write = 1'b0;
                ctrl_alu_op = 3'd1;
                ctrl_branch = 1'b1;
                ctrl_jump = 1'b0;
            end
            6'b000010: begin
                ctrl_reg_write = 1'b0;
                ctrl_mem_read = 1'b0;
                ctrl_mem_write = 1'b0;
                ctrl_alu_op = 3'd0;
                ctrl_branch = 1'b0;
                ctrl_jump = 1'b1;
            end
            default: begin
                ctrl_reg_write = 1'b0;
                ctrl_mem_read = 1'b0;
                ctrl_mem_write = 1'b0;
                ctrl_alu_op = 3'd0;
                ctrl_branch = 1'b0;
                ctrl_jump = 1'b0;
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_instr <= 32'd0;
            id_ex_pc <= 32'd0;
            id_ex_rs <= 5'd0;
            id_ex_rt <= 5'd0;
            id_ex_rd <= 5'd0;
            id_ex_mem_read <= 1'b0;
            id_ex_mem_write <= 1'b0;
            reg_write <= 1'b0;
            alu_op <= 3'd0;
            branch <= 1'b0;
            jump <= 1'b0;
        end else if (if_id_write) begin
            id_ex_instr <= if_id_instr;
            id_ex_pc <= if_id_pc;
            id_ex_rs <= if_id_rs;
            id_ex_rt <= if_id_rt;
            id_ex_rd <= if_id_rd;
            id_ex_mem_read <= ctrl_mem_read;
            id_ex_mem_write <= ctrl_mem_write;
            reg_write <= ctrl_reg_write;
            alu_op <= ctrl_alu_op;
            branch <= ctrl_branch;
            jump <= ctrl_jump;
        end else if (id_ex_flush) begin
            id_ex_instr <= 32'd0;
            id_ex_mem_read <= 1'b0;
            id_ex_mem_write <= 1'b0;
            reg_write <= 1'b0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                register_file[i] <= 32'd0;
        end else if (mem_wb_reg_write && mem_wb_rd_addr != 5'd0) begin
            register_file[mem_wb_rd_addr] <= wb_data;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_read_data1 <= 32'd0;
            id_ex_read_data2 <= 32'd0;
        end else if (if_id_write) begin
            if (if_id_rs == 5'd0)
                id_ex_read_data1 <= 32'd0;
            else
                id_ex_read_data1 <= register_file[if_id_rs];
            if (if_id_rt == 5'd0)
                id_ex_read_data2 <= 32'd0;
            else
                id_ex_read_data2 <= register_file[if_id_rt];
        end
    end

    forwarding_unit fwd_u (
        .ex_mem_rd       (mem_wb_alu_result),
        .mem_wb_rd       (wb_data),
        .ex_mem_reg_write(ex_mem_reg_write),
        .mem_wb_reg_write(mem_wb_reg_write),
        .id_ex_rs        (id_ex_rs),
        .id_ex_rt        (id_ex_rt),
        .ex_mem_rd_addr  (ex_mem_rd_addr),
        .mem_wb_rd_addr  (mem_wb_rd_addr),
        .id_ex_mem_read  (id_ex_mem_read),
        .forward_a       (forward_a),
        .forward_b       (forward_b),
        .stall_forward   ()
    );

    always_comb begin
        case (forward_a)
            2'b00: alu_a = id_ex_read_data1;
            2'b01: alu_a = mem_wb_alu_result;
            2'b10: alu_a = ex_mem_alu_result;
            default: alu_a = id_ex_read_data1;
        endcase

        case (forward_b)
            2'b00: alu_b = id_ex_read_data2;
            2'b01: alu_b = mem_wb_alu_result;
            2'b10: alu_b = ex_mem_alu_result;
            default: alu_b = id_ex_read_data2;
        endcase
    end

    always @(*) begin
        case (alu_op)
            3'd0: alu_result_next = alu_a + alu_b;
            3'd1: alu_result_next = alu_a - alu_b;
            3'd2: alu_result_next = alu_a & alu_b;
            3'd3: alu_result_next = alu_a | alu_b;
            3'd4: alu_result_next = (alu_a < alu_b) ? 32'd1 : 32'd0;
            3'd5: alu_result_next = alu_a + $signed({{16{id_ex_instr[15]}}, id_ex_instr[15:0]});
            default: alu_result_next = alu_a + alu_b;
        endcase
    end

    assign branch_target = id_ex_pc + 32'd4 + $signed({{14{id_ex_instr[15]}}, id_ex_instr[15:0], 2'b00});
    assign branch_taken = branch && (alu_a == alu_b);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_instr <= 32'd0;
            ex_mem_pc <= 32'd0;
            ex_mem_read_data1 <= 32'd0;
            ex_mem_alu_result <= 32'd0;
            ex_mem_wdata <= 32'd0;
            ex_mem_rd_addr <= 5'd0;
            ex_mem_reg_write <= 1'b0;
            ex_mem_mem_read <= 1'b0;
            ex_mem_mem_write <= 1'b0;
        end else begin
            ex_mem_instr <= id_ex_instr;
            ex_mem_pc <= id_ex_pc;
            ex_mem_read_data1 <= alu_a;
            ex_mem_alu_result <= alu_result_next;
            ex_mem_wdata <= id_ex_read_data2;
            ex_mem_rd_addr <= id_ex_rd;
            ex_mem_reg_write <= reg_write;
            ex_mem_mem_read <= id_ex_mem_read;
            ex_mem_mem_write <= id_ex_mem_write;
        end
    end

    assign ex_mem_rd = ex_mem_rd_addr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_instr <= 32'd0;
            mem_wb_pc <= 32'd0;
            mem_wb_read_data1 <= 32'd0;
            mem_wb_read_data2 <= 32'd0;
            mem_wb_alu_result <= 32'd0;
            mem_wb_wdata_mem <= 32'd0;
            mem_wb_rd_addr <= 5'd0;
            mem_wb_reg_write <= 1'b0;
            mem_wb_mem_read <= 1'b0;
            mem_wb_mem_write <= 1'b0;
        end else begin
            mem_wb_instr <= ex_mem_instr;
            mem_wb_pc <= ex_mem_pc;
            mem_wb_read_data1 <= ex_mem_read_data1;
            mem_wb_read_data2 <= ex_mem_wdata;
            mem_wb_alu_result <= ex_mem_alu_result;
            data_mem_addr = ex_mem_alu_result[11:2];
            mem_wb_wdata_mem <= data_mem[data_mem_addr];
            mem_wb_rd_addr <= ex_mem_rd_addr;
            mem_wb_reg_write <= ex_mem_reg_write;
            mem_wb_mem_read <= ex_mem_mem_read;
            mem_wb_mem_write <= ex_mem_mem_write;
        end
    end

    assign mem_wb_rd = mem_wb_rd_addr;

    always_comb begin
        if (mem_wb_mem_read)
            wb_data = mem_wb_wdata_mem;
        else if (mem_wb_reg_write)
            wb_data = mem_wb_alu_result;
        else
            wb_data = 32'd0;
    end

    always_ff @(posedge clk) begin
        if (ex_mem_mem_write) begin
            data_mem_addr = ex_mem_alu_result[11:2];
            data_mem[data_mem_addr] <= ex_mem_wdata;
        end
    end

    hazard_unit hazard_u (
        .id_ex_mem_read  (id_ex_mem_read),
        .id_ex_rt        (id_ex_rt),
        .if_id_rs        (if_id_rs),
        .if_id_rt        (if_id_rt),
        .ex_mem_mem_write(ex_mem_mem_write),
        .id_ex_rs        (id_ex_rs),
        .id_ex_rt_next   (id_ex_rt),
        .cache_stall     (cache_stall),
        .pc_write        (pc_write),
        .if_id_write     (if_id_write),
        .id_ex_flush     (id_ex_flush)
    );

    assign alu_result = alu_result_next;

endmodule
