`timescale 1ns/1ps
module tb_system;

logic clk;
logic rst;

logic imem_req;
logic [31:0] imem_addr;
logic [31:0] imem_rdata;
logic imem_ready;

logic dmem_req;
logic dmem_we;
logic [31:0] dmem_addr;
logic [31:0] dmem_wdata;
logic [31:0] dmem_rdata;
logic dmem_ready;

logic l2_i_req;
logic [31:0] l2_i_addr;
logic [127:0] l2_i_rdata;
logic l2_i_ready;

logic l2_d_req;
logic l2_d_we;
logic [31:0] l2_d_addr;
logic [127:0] l2_d_wdata;
logic [127:0] l2_d_rdata;
logic l2_d_ready;

logic mem_req;
logic mem_we;
logic [31:0] mem_addr;
logic [127:0] mem_wdata;
logic [127:0] mem_rdata;
logic mem_ready;

logic stall_pipeline;

logic [1:0] forwardA;
logic [1:0] forwardB;

logic mem_stall;

initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

mips_processor cpu(
    .clk(clk),
    .rst(rst),
    .imem_req(imem_req),
    .imem_addr(imem_addr),
    .imem_rdata(imem_rdata),
    .imem_ready(imem_ready),
    .dmem_req(dmem_req),
    .dmem_we(dmem_we),
    .dmem_addr(dmem_addr),
    .dmem_wdata(dmem_wdata),
    .dmem_rdata(dmem_rdata),
    .dmem_ready(dmem_ready)
);
hazard_unit hz(

    .memread_ex(1'b0),
    .rt_ex(5'd0),

    .rs_id(cpu.instr[25:21]),
    .rt_id(cpu.instr[20:16]),

    .stall(stall_pipeline)
);
forwarding_unit fwd(

    .rs_ex(cpu.instr[25:21]),
    .rt_ex(cpu.instr[20:16]),

    .rd_mem(5'd3),
    .rd_wb(5'd2),

    .regwrite_mem(1'b1),
    .regwrite_wb(1'b1),

    .forwardA(forwardA),
    .forwardB(forwardB)
);
assign mem_stall = mem_req && !mem_ready;

cache_l1i l1i(
    .clk(clk),
    .rst(rst),
    .cpu_req(imem_req),
    .cpu_addr(imem_addr),
    .cpu_rdata(imem_rdata),
    .cpu_ready(imem_ready),
    .l2_req(l2_i_req),
    .l2_addr(l2_i_addr),
    .l2_rdata(l2_i_rdata),
    .l2_ready(l2_i_ready)
);

cache_l1d l1d(
    .clk(clk),
    .rst(rst),
    .cpu_req(dmem_req),
    .cpu_we(dmem_we),
    .cpu_addr(dmem_addr),
    .cpu_wdata(dmem_wdata),
    .cpu_rdata(dmem_rdata),
    .cpu_ready(dmem_ready),
    .l2_req(l2_d_req),
    .l2_we(l2_d_we),
    .l2_addr(l2_d_addr),
    .l2_wdata(l2_d_wdata),
    .l2_rdata(l2_d_rdata),
    .l2_ready(l2_d_ready)
);

cache_l2 l2(
    .clk(clk),
    .rst(rst),
    .l1i_req(l2_i_req),
    .l1i_addr(l2_i_addr),
    .l1i_rdata(l2_i_rdata),
    .l1i_ready(l2_i_ready),
    .l1d_req(l2_d_req),
    .l1d_we(l2_d_we),
    .l1d_addr(l2_d_addr),
    .l1d_wdata(l2_d_wdata),
    .l1d_rdata(l2_d_rdata),
    .l1d_ready(l2_d_ready),
    .mem_req(mem_req),
    .mem_we(mem_we),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata),
    .mem_ready(mem_ready)
);

sim_dram dram(
    .clk(clk),
    .rst(rst),
    .req(mem_req),
    .we(mem_we),
    .addr(mem_addr),
    .wdata(mem_wdata),
    .rdata(mem_rdata),
    .ready(mem_ready)
);

initial begin
    $dumpfile("mips_waveform.vcd");
    $dumpvars(0, tb_system);

    rst = 1;
    #20;
    rst = 0;

    #3000;
    $finish;
end
endmodule
