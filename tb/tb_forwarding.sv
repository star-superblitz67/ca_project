`timescale 1ns/1ps
// Testbench: Forwarding Unit
// Tests EX forwarding and MEM forwarding back-to-back.
// Every instruction depends on the one before it, so the forwarding
// unit has to do work on almost every cycle.
//
// Program:
//   0x00: ADDI R1,R0,10    R1 = 10
//   0x04: ADD  R2,R1,R1    R2 = 20   (EX fwd: R1 from EX/MEM for both A and B)
//   0x08: ADD  R3,R2,R1    R3 = 30   (EX fwd: R2 from EX/MEM; MEM fwd: R1 from MEM/WB)
//   0x0C: ADD  R4,R3,R2    R4 = 50   (EX fwd: R3; MEM fwd: R2)
//   0x10: SUB  R5,R4,R3    R5 = 20   (EX fwd: R4; MEM fwd: R3)
//
// Expected: R1=10  R2=20  R3=30  R4=50  R5=20
//
// Instruction encodings:
//   ADDI R1,R0,10 = 0x2001000A
//   ADD  R2,R1,R1 = 0x00211020  (rs=1,rt=1,rd=2)
//   ADD  R3,R2,R1 = 0x00411820  (rs=2,rt=1,rd=3)
//   ADD  R4,R3,R2 = 0x00622020  (rs=3,rt=2,rd=4)
//   SUB  R5,R4,R3 = 0x00832822  (rs=4,rt=3,rd=5)

module tb_forwarding;

    logic clk, rst;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    logic        i_req, i_ready;
    logic [31:0] i_addr, i_data;
    logic        d_req, d_we, d_ready;
    logic [31:0] d_addr, d_wdata, d_rdata;
    logic        l2i_req, l2i_ready;
    logic [31:0] l2i_addr;
    logic [127:0] l2i_rdata;
    logic        l2d_req, l2d_we, l2d_ready;
    logic [31:0] l2d_addr;
    logic [127:0] l2d_wdata, l2d_rdata;
    logic        m_req, m_we, m_ready;
    logic [31:0] m_addr;
    logic [127:0] m_wdata, m_rdata;
    logic [31:0] r1,r2,r3,r4,r5,r6,r7,r8,r9;

    integer total_cycles, lu_stall_cycles, cache_stall_cycles;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            total_cycles <= 0; lu_stall_cycles <= 0; cache_stall_cycles <= 0;
        end else begin
            total_cycles <= total_cycles + 1;
            if (cpu.stall_haz)   lu_stall_cycles   <= lu_stall_cycles + 1;
            if (cpu.cache_stall) cache_stall_cycles <= cache_stall_cycles + 1;
        end
    end

    mips_processor cpu(
        .clk(clk),.rst(rst),
        .imem_req(i_req),.imem_addr(i_addr),.imem_rdata(i_data),.imem_ready(i_ready),
        .dmem_req(d_req),.dmem_we(d_we),.dmem_addr(d_addr),
        .dmem_wdata(d_wdata),.dmem_rdata(d_rdata),.dmem_ready(d_ready),
        .dbg_r1(r1),.dbg_r2(r2),.dbg_r3(r3),.dbg_r4(r4),.dbg_r5(r5),
        .dbg_r6(r6),.dbg_r7(r7),.dbg_r8(r8),.dbg_r9(r9)
    );
    cache_l1i l1i(.clk(clk),.rst(rst),.cpu_req(i_req),.cpu_addr(i_addr),
        .cpu_rdata(i_data),.cpu_ready(i_ready),
        .l2_req(l2i_req),.l2_addr(l2i_addr),.l2_rdata(l2i_rdata),.l2_ready(l2i_ready));
    cache_l1d l1d(.clk(clk),.rst(rst),.cpu_req(d_req),.cpu_we(d_we),
        .cpu_addr(d_addr),.cpu_wdata(d_wdata),.cpu_rdata(d_rdata),.cpu_ready(d_ready),
        .l2_req(l2d_req),.l2_we(l2d_we),.l2_addr(l2d_addr),.l2_wdata(l2d_wdata),
        .l2_rdata(l2d_rdata),.l2_ready(l2d_ready));
    cache_l2 l2(.clk(clk),.rst(rst),
        .l1i_req(l2i_req),.l1i_addr(l2i_addr),.l1i_rdata(l2i_rdata),.l1i_ready(l2i_ready),
        .l1d_req(l2d_req),.l1d_we(l2d_we),.l1d_addr(l2d_addr),.l1d_wdata(l2d_wdata),
        .l1d_rdata(l2d_rdata),.l1d_ready(l2d_ready),
        .mem_req(m_req),.mem_we(m_we),.mem_addr(m_addr),.mem_wdata(m_wdata),
        .mem_rdata(m_rdata),.mem_ready(m_ready));
    sim_dram_bare dram(.clk(clk),.rst(rst),.req(m_req),.we(m_we),
        .addr(m_addr),.wdata(m_wdata),.rdata(m_rdata),.ready(m_ready));

    initial begin
        $dumpfile("tb_forwarding.vcd");
        $dumpvars(0, tb_forwarding);

        // load program before reset
        // block 0: [127:96]=0x0C  [95:64]=0x08  [63:32]=0x04  [31:0]=0x00
        dram.memory[0] = {32'h00622020, 32'h00411820, 32'h00211020, 32'h2001000A};
        // block 1: [31:0]=0x10 = SUB R5,R4,R3; rest NOP
        dram.memory[1] = {32'h00000000, 32'h00000000, 32'h00000000, 32'h00832822};

        $display("--- Forwarding Testbench ---");
        $display("Every instruction uses the result of the previous one.");
        $display("No stalls expected - forwarding should handle everything.");

        rst = 1'b1; @(posedge clk); #1; @(posedge clk); #1;
        rst = 1'b0;

        #2000;

        $display("--- Results ---");
        chk("R1", r1, 32'd10, "ADDI baseline");
        chk("R2", r2, 32'd20, "ADD [EX fwd: R1 used twice]");
        chk("R3", r3, 32'd30, "ADD [EX fwd R2, MEM fwd R1]");
        chk("R4", r4, 32'd50, "ADD [EX fwd R3, MEM fwd R2]");
        chk("R5", r5, 32'd20, "SUB [EX fwd R4, MEM fwd R3]");

        $display("--- Cycle Stats ---");
        $display("Total cycles      : %0d", total_cycles);
        $display("Load-use stalls   : %0d  (should be 0 - no loads)", lu_stall_cycles);
        $display("Cache stall cycles: %0d", cache_stall_cycles);
        $display("--- Done ---");
        $finish;
    end

    task automatic chk(input string name, input logic [31:0] got, exp, input string note);
        if (got === exp) $display("  PASS  %s = %0d  | %s", name, got, note);
        else             $display("  FAIL  %s = %0d (expected %0d)  | %s", name, got, exp, note);
    endtask

endmodule
