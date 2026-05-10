`timescale 1ns/1ps
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

logic [31:0] pc;
logic [31:0] instr;
logic [31:0] reg_file [0:31];

logic [31:0] dbg_r1;
logic [31:0] dbg_r2;
logic [31:0] dbg_r3;
logic [31:0] dbg_r4;
logic [31:0] dbg_r5;
logic [31:0] dbg_r6;

logic dbg_mem_stall;
logic dbg_imem_ready;
logic dbg_dmem_ready;

assign dbg_imem_ready = imem_ready;
assign dbg_dmem_ready = dmem_ready;

assign dbg_mem_stall =
    (imem_req && !imem_ready) ||
    (dmem_req && !dmem_ready);

assign dbg_r1 = reg_file[1];
assign dbg_r2 = reg_file[2];
assign dbg_r3 = reg_file[3];
assign dbg_r4 = reg_file[4];
assign dbg_r5 = reg_file[5];
assign dbg_r6 = reg_file[6];

assign imem_req = !rst;
assign imem_addr = pc;

assign dmem_req = 0;
assign dmem_we = 0;
assign dmem_addr = 0;
assign dmem_wdata = 0;

integer i;
initial begin
    for(i=0;i<32;i=i+1)
        reg_file[i] = 0;
end

always_ff @(posedge clk or posedge rst) begin
    if(rst)
        pc <= 0;
    else if(imem_ready) begin

        instr <= imem_rdata;

        case(imem_rdata[31:26])

            6'h08:
                reg_file[imem_rdata[20:16]] <=
                    reg_file[imem_rdata[25:21]] +
                    {{16{imem_rdata[15]}}, imem_rdata[15:0]};

            6'h0D:
                reg_file[imem_rdata[20:16]] <=
                    reg_file[imem_rdata[25:21]] |
                    {16'b0, imem_rdata[15:0]};

            6'h00:
                if(imem_rdata[5:0] == 6'h20)
                    reg_file[imem_rdata[15:11]] <=
                        reg_file[imem_rdata[25:21]] +
                        reg_file[imem_rdata[20:16]];

        endcase

        pc <= pc + 4;
    end
end
endmodule
