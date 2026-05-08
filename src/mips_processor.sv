`timescale 1ns / 1ps

module mips_processor(

    input logic clk,
    input logic rst,

    output logic imem_req,
    output logic [31:0] imem_addr,
    input logic [31:0] imem_rdata,
    input logic imem_ready,

    output logic dmem_req,
    output logic dmem_we,
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    input logic [31:0] dmem_rdata,
    input logic dmem_ready

);

logic mem_stall;

logic hazard_stall;
logic flush_ID;
logic flush_EX;

logic en_PC;
logic en_IF_ID;
logic en_ID_EX;
logic en_EX_MEM;
logic en_MEM_WB;

logic [31:0] pc;
logic [31:0] next_pc;
logic [31:0] pc_plus_4_IF;

logic [31:0] instr_ID;
logic [31:0] pc_plus_4_ID;

logic [4:0] rs_ID;
logic [4:0] rt_ID;
logic [4:0] rd_ID;

logic [15:0] imm_ID;

logic [5:0] opcode;
logic [5:0] funct;

logic [31:0] sign_ext_imm_ID;
logic [31:0] zero_ext_imm_ID;
logic [31:0] ext_imm_ID;

logic [31:0] reg_data1_ID;
logic [31:0] reg_data2_ID;

logic reg_dst_ID;
logic alu_src_ID;
logic mem_to_reg_ID;
logic reg_write_ID;
logic mem_read_ID;
logic mem_write_ID;
logic branch_ID;

logic [2:0] alu_ctrl_ID;

logic branch_taken;
logic [31:0] branch_target;

logic [31:0] reg_data1_EX;
logic [31:0] reg_data2_EX;
logic [31:0] sign_ext_imm_EX;

logic [4:0] rs_EX;
logic [4:0] rt_EX;
logic [4:0] rd_EX;

logic reg_write_EX;
logic mem_to_reg_EX;
logic mem_write_EX;
logic alu_src_EX;
logic reg_dst_EX;
logic mem_read_EX;

logic [2:0] alu_ctrl_EX;

logic [31:0] alu_in1;
logic [31:0] alu_in2;

logic [31:0] alu_out_EX;

logic [31:0] mem_write_data_EX;

logic [4:0] dest_reg_EX;

logic [1:0] forward_A;
logic [1:0] forward_B;

logic [31:0] fwd_b_val;

logic [31:0] alu_out_MEM;
logic [31:0] mem_write_data_MEM;

logic [4:0] dest_reg_MEM;

logic reg_write_MEM;
logic mem_to_reg_MEM;
logic mem_write_MEM;
logic mem_read_MEM;

logic [31:0] mem_read_data_WB;
logic [31:0] alu_out_WB;

logic [4:0] dest_reg_WB;

logic reg_write_WB;
logic mem_to_reg_WB;

logic [31:0] wb_data;

logic [31:0] reg_file [0:31];

integer i;

initial begin

    for(i=0;i<32;i=i+1)
        reg_file[i] = 0;

end

assign mem_stall =
    ((imem_req && !imem_ready) && !rst) ||
    ((dmem_req && !dmem_ready) && !rst);

assign en_PC     = !mem_stall && !hazard_stall;
assign en_IF_ID  = !mem_stall && !hazard_stall;
assign en_ID_EX  = !mem_stall;
assign en_EX_MEM = !mem_stall;
assign en_MEM_WB = !mem_stall;

assign pc_plus_4_IF = pc + 4;

assign next_pc =
    branch_taken ? branch_target :
                   pc_plus_4_IF;

assign imem_req = !rst;
assign imem_addr = pc;

always @(posedge clk or posedge rst) begin

    if(rst)
        pc <= 0;

    else if(en_PC)
        pc <= next_pc;

end

always @(posedge clk or posedge rst) begin

    if(rst || (flush_ID && !mem_stall)) begin

        instr_ID <= 32'h00000000;
        pc_plus_4_ID <= 0;

    end

    else if(en_IF_ID) begin

        instr_ID <= imem_rdata;
        pc_plus_4_ID <= pc_plus_4_IF;

    end

end

assign rs_ID = instr_ID[25:21];
assign rt_ID = instr_ID[20:16];
assign rd_ID = instr_ID[15:11];

assign imm_ID = instr_ID[15:0];

assign opcode = instr_ID[31:26];
assign funct  = instr_ID[5:0];

assign sign_ext_imm_ID =
    {{16{imm_ID[15]}}, imm_ID};

assign zero_ext_imm_ID =
    {16'b0, imm_ID};

assign ext_imm_ID =
    (opcode == 6'h0D) ?
    zero_ext_imm_ID :
    sign_ext_imm_ID;

always @(*) begin

    reg_dst_ID    = 0;
    alu_src_ID    = 0;
    mem_to_reg_ID = 0;
    reg_write_ID  = 0;
    mem_read_ID   = 0;
    mem_write_ID  = 0;
    branch_ID     = 0;

    alu_ctrl_ID   = 3'b000;

    case(opcode)

        6'h00: begin

            reg_dst_ID = 1;
            reg_write_ID = 1;

            case(funct)

                6'h20:
                    alu_ctrl_ID = 3'b010;

                6'h22:
                    alu_ctrl_ID = 3'b110;

                6'h24:
                    alu_ctrl_ID = 3'b000;

                6'h25:
                    alu_ctrl_ID = 3'b001;

                6'h2A:
                    alu_ctrl_ID = 3'b111;

            endcase

        end

        6'h08: begin

            alu_src_ID = 1;
            reg_write_ID = 1;
            alu_ctrl_ID = 3'b010;

        end

        6'h0D: begin

            alu_src_ID = 1;
            reg_write_ID = 1;
            alu_ctrl_ID = 3'b001;

        end

        6'h23: begin

            alu_src_ID = 1;
            mem_to_reg_ID = 1;
            reg_write_ID = 1;
            mem_read_ID = 1;
            alu_ctrl_ID = 3'b010;

        end

        6'h2B: begin

            alu_src_ID = 1;
            mem_write_ID = 1;
            alu_ctrl_ID = 3'b010;

        end

        6'h04: begin

            branch_ID = 1;
            alu_ctrl_ID = 3'b110;

        end

    endcase

end

always @(posedge clk) begin

    if(reg_write_WB &&
       dest_reg_WB != 0 &&
       !mem_stall)

        reg_file[dest_reg_WB] <= wb_data;

end

assign reg_data1_ID =
    (rs_ID == 0) ? 0 :
                   reg_file[rs_ID];

assign reg_data2_ID =
    (rt_ID == 0) ? 0 :
                   reg_file[rt_ID];

assign branch_target =
    pc_plus_4_ID + (ext_imm_ID << 2);

assign branch_taken =
    branch_ID &&
    (reg_data1_ID == reg_data2_ID);

always @(posedge clk or posedge rst) begin

    if(rst || (flush_EX && !mem_stall)) begin

        reg_data1_EX <= 0;
        reg_data2_EX <= 0;
        sign_ext_imm_EX <= 0;

        rs_EX <= 0;
        rt_EX <= 0;
        rd_EX <= 0;

        reg_write_EX <= 0;
        mem_to_reg_EX <= 0;
        mem_write_EX <= 0;
        alu_src_EX <= 0;
        reg_dst_EX <= 0;
        mem_read_EX <= 0;

        alu_ctrl_EX <= 0;

    end

    else if(en_ID_EX) begin

        reg_data1_EX <= reg_data1_ID;
        reg_data2_EX <= reg_data2_ID;

        sign_ext_imm_EX <= ext_imm_ID;

        rs_EX <= rs_ID;
        rt_EX <= rt_ID;
        rd_EX <= rd_ID;

        reg_write_EX <= reg_write_ID;
        mem_to_reg_EX <= mem_to_reg_ID;
        mem_write_EX <= mem_write_ID;
        alu_src_EX <= alu_src_ID;
        reg_dst_EX <= reg_dst_ID;
        mem_read_EX <= mem_read_ID;

        alu_ctrl_EX <= alu_ctrl_ID;

    end

end

always @(*) begin

    case(forward_A)

        2'b10:
            alu_in1 = alu_out_MEM;

        2'b01:
            alu_in1 = wb_data;

        default:
            alu_in1 = reg_data1_EX;

    endcase

    case(forward_B)

        2'b10:
            fwd_b_val = alu_out_MEM;

        2'b01:
            fwd_b_val = wb_data;

        default:
            fwd_b_val = reg_data2_EX;

    endcase

    alu_in2 =
        alu_src_EX ?
        sign_ext_imm_EX :
        fwd_b_val;

end

assign dest_reg_EX =
    reg_dst_EX ? rd_EX :
                 rt_EX;

always @(*) begin

    alu_out_EX = 0;

    case(alu_ctrl_EX)

        3'b010:
            alu_out_EX = alu_in1 + alu_in2;

        3'b110:
            alu_out_EX = alu_in1 - alu_in2;

        3'b000:
            alu_out_EX = alu_in1 & alu_in2;

        3'b001:
            alu_out_EX = alu_in1 | alu_in2;

        3'b111:
            alu_out_EX =
            ($signed(alu_in1) < $signed(alu_in2));

    endcase

end

always @(*) begin

    case(forward_B)

        2'b10:
            mem_write_data_EX = alu_out_MEM;

        2'b01:
            mem_write_data_EX = wb_data;

        default:
            mem_write_data_EX = reg_data2_EX;

    endcase

end

always @(posedge clk or posedge rst) begin

    if(rst) begin

        alu_out_MEM <= 0;
        mem_write_data_MEM <= 0;

        dest_reg_MEM <= 0;

        reg_write_MEM <= 0;
        mem_to_reg_MEM <= 0;

        mem_write_MEM <= 0;
        mem_read_MEM <= 0;

    end

    else if(en_EX_MEM) begin

        alu_out_MEM <= alu_out_EX;
        mem_write_data_MEM <= mem_write_data_EX;

        dest_reg_MEM <= dest_reg_EX;

        reg_write_MEM <= reg_write_EX;
        mem_to_reg_MEM <= mem_to_reg_EX;

        mem_write_MEM <= mem_write_EX;
        mem_read_MEM <= mem_read_EX;

    end

end

assign dmem_req =
    mem_read_MEM || mem_write_MEM;

assign dmem_we = mem_write_MEM;

assign dmem_addr = alu_out_MEM;

assign dmem_wdata = mem_write_data_MEM;

always @(posedge clk or posedge rst) begin

    if(rst) begin

        mem_read_data_WB <= 0;
        alu_out_WB <= 0;

        dest_reg_WB <= 0;

        reg_write_WB <= 0;
        mem_to_reg_WB <= 0;

    end

    else if(en_MEM_WB) begin

        mem_read_data_WB <= dmem_rdata;
        alu_out_WB <= alu_out_MEM;

        dest_reg_WB <= dest_reg_MEM;

        reg_write_WB <= reg_write_MEM;
        mem_to_reg_WB <= mem_to_reg_MEM;

    end

end

assign wb_data =
    mem_to_reg_WB ?
    mem_read_data_WB :
    alu_out_WB;

hazard_unit hazard_u(

    .rs_ID(rs_ID),
    .rt_ID(rt_ID),
    .rt_EX(rt_EX),

    .mem_read_EX(mem_read_EX),

    .branch_taken(branch_taken),

    .stall_pipeline(hazard_stall),

    .flush_ID(flush_ID),
    .flush_EX(flush_EX)

);

forwarding_unit forward_u(

    .rs_EX(rs_EX),
    .rt_EX(rt_EX),

    .rd_MEM(dest_reg_MEM),
    .reg_write_MEM(reg_write_MEM),

    .rd_WB(dest_reg_WB),
    .reg_write_WB(reg_write_WB),

    .forward_A(forward_A),
    .forward_B(forward_B)

);

endmodule