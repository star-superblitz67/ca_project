`timescale 1ns/1ps
module tb_system;

    logic clk, rst;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // CPU <-> L1I
    logic        i_req, i_ready;
    logic [31:0] i_addr, i_data;
    // CPU <-> L1D
    logic        d_req, d_we, d_ready;
    logic [31:0] d_addr, d_wdata, d_rdata;
    // L1I <-> L2
    logic        l2i_req, l2i_ready;
    logic [31:0] l2i_addr;
    logic [127:0] l2i_rdata;
    // L1D <-> L2
    logic        l2d_req, l2d_we, l2d_ready;
    logic [31:0] l2d_addr;
    logic [127:0] l2d_wdata, l2d_rdata;
    // L2 <-> DRAM
    logic        m_req, m_we, m_ready;
    logic [31:0] m_addr;
    logic [127:0] m_wdata, m_rdata;
    // debug registers
    logic [31:0] r1,r2,r3,r4,r5,r6,r7,r8,r9,r10;

    // cycle counters - useful to see the overhead each hazard caused
    integer total_cycles, lu_stall_cycles, cache_stall_cycles;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            total_cycles      <= 0;
            lu_stall_cycles   <= 0;
            cache_stall_cycles <= 0;
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
        .dbg_r6(r6),.dbg_r7(r7),.dbg_r8(r8),.dbg_r9(r9),.dbg_r10(r10)
    );
    cache_l1i l1i(
        .clk(clk),.rst(rst),
        .cpu_req(i_req),.cpu_addr(i_addr),.cpu_rdata(i_data),.cpu_ready(i_ready),
        .l2_req(l2i_req),.l2_addr(l2i_addr),.l2_rdata(l2i_rdata),.l2_ready(l2i_ready)
    );
    cache_l1d l1d(
        .clk(clk),.rst(rst),
        .cpu_req(d_req),.cpu_we(d_we),.cpu_addr(d_addr),.cpu_wdata(d_wdata),
        .cpu_rdata(d_rdata),.cpu_ready(d_ready),
        .l2_req(l2d_req),.l2_we(l2d_we),.l2_addr(l2d_addr),.l2_wdata(l2d_wdata),
        .l2_rdata(l2d_rdata),.l2_ready(l2d_ready)
    );
    cache_l2 l2(
        .clk(clk),.rst(rst),
        .l1i_req(l2i_req),.l1i_addr(l2i_addr),.l1i_rdata(l2i_rdata),.l1i_ready(l2i_ready),
        .l1d_req(l2d_req),.l1d_we(l2d_we),.l1d_addr(l2d_addr),.l1d_wdata(l2d_wdata),
        .l1d_rdata(l2d_rdata),.l1d_ready(l2d_ready),
        .mem_req(m_req),.mem_we(m_we),.mem_addr(m_addr),.mem_wdata(m_wdata),
        .mem_rdata(m_rdata),.mem_ready(m_ready)
    );
    sim_dram dram(
        .clk(clk),.rst(rst),
        .req(m_req),.we(m_we),.addr(m_addr),.wdata(m_wdata),
        .rdata(m_rdata),.ready(m_ready)
    );

    initial begin
        $dumpfile("mips_waveform.vcd");
        $dumpvars(0, tb_system);

        $display("--- MIPS 5-Stage Pipeline: All Features Demo ---");
        $display("EX Forwarding    : ADD  R3 = R1+R2  (R1 still in pipeline)");
        $display("EX+MEM Fwd       : SUB  R4 = R3-R2");
        $display("L1D miss (write) : SW   R4 -> mem[0x80]");
        $display("L1D miss (read)  : LW   R5 <- mem[0x80]  DRAM refill");
        $display("Load-use stall   : ADD  R6 = R5+R3");
        $display("L1D hit          : LW   R7 <- mem[0x80]  from cache");
        $display("Branch taken     : BNE  R3,R4 (13!=8) -> 0x30, flushes 0x28+0x2C");
        $display("Flush proof      : R9=55 before branch; wrong-path would set 111/222");
        $display("L1I miss (blk4)  : ADD  R8 = R6+R7  at branch target block");
        $display("AND instruction  : AND  R9 = R8&R3  (29&13=13)");
        $display("JUMP instruction : J    0x44 (target in block 4)");
        $display("Jump flush proof : delay slot 0x3C flushed, R8 != 999");
        $display("Jump target hit  : ADDI R10 = 42 at 0x44");
        $display("------------------------------------------------");

        rst = 1'b1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst = 1'b0;

        #6000;

        $display("");
        $display("--- Results ---");
        chk("R1", r1, 32'd8,  "ADDI");
        chk("R2", r2, 32'd5,  "ADDI");
        chk("R3", r3, 32'd13, "ADD  [EX forwarding]");
        chk("R4", r4, 32'd8,  "SUB  [EX+MEM forwarding]");
        chk("R5", r5, 32'd8,  "LW   [L1D miss - DRAM refill]");
        chk("R6", r6, 32'd21, "ADD  [load-use stall]");
        chk("R7", r7, 32'd8,  "LW   [L1D hit]");
        chk("R8", r8, 32'd29, "ADD  [branch target - L1I miss]");
        chk("R9", r9, 32'd13, "AND  [29&13=13; flush proof: not 111 or 222]");
        chk("R10", r10, 32'd42, "ADDI [jump target hit, delay slot flushed]");

        $display("");
        $display("--- Cycle Stats ---");
        $display("Total cycles      : %0d", total_cycles);
        $display("Load-use stalls   : %0d  (each = 1 wasted cycle)", lu_stall_cycles);
        $display("Cache stall cycles: %0d  (L1 misses waiting on DRAM)", cache_stall_cycles);
        $display("Useful cycles     : %0d", total_cycles - lu_stall_cycles - cache_stall_cycles);
        $display("--- Done ---");
        $finish;
    end

    task automatic chk(
        input string name,
        input logic [31:0] got, exp,
        input string feat
    );
        if (got === exp)
            $display("  PASS  %s = %0d  | %s", name, got, feat);
        else
            $display("  FAIL  %s = %0d (expected %0d)  | %s", name, got, exp, feat);
    endtask

endmodule
