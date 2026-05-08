`timescale 1ns / 1ps

module tb_system();

    // ==========================================
    // SYSTEM SIGNALS
    // ==========================================
    logic clk;
    logic rst;

    // Connections between CPU and L1 Instruction Cache
    logic        imem_req, imem_ready;
    logic [31:0] imem_addr, imem_rdata;

    // Connections between CPU and L1 Data Cache
    logic        dmem_req, dmem_we, dmem_ready;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;

    // Connections between L1 Instruction Cache and L2 Cache
    logic         l2_i_req, l2_i_ready;
    logic [31:0]  l2_i_addr;
    logic [127:0] l2_i_rdata;

    // Connections between L1 Data Cache and L2 Cache
    logic         l2_d_req, l2_d_we, l2_d_ready;
    logic [31:0]  l2_d_addr;
    logic [127:0] l2_d_wdata, l2_d_rdata;

    // Connections between L2 Cache and Main Memory (DRAM)
    logic         mem_req, mem_we, mem_ready;
    logic [31:0]  mem_addr;
    logic [127:0] mem_wdata, mem_rdata;

    // Clock generator
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns period clock
    end

    // ==========================================
    // MODULE INSTANTIATIONS
    // ==========================================
    
    // The main processor core
    mips_processor cpu (
        .clk(clk), .rst(rst),
        .imem_req(imem_req), .imem_addr(imem_addr), .imem_rdata(imem_rdata), .imem_ready(imem_ready),
        .dmem_req(dmem_req), .dmem_we(dmem_we), .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata), .dmem_ready(dmem_ready)
    );

    // Level 1 Instruction Cache
    cache_l1i l1i (
        .clk(clk), .rst(rst),
        .cpu_req(imem_req), .cpu_addr(imem_addr), .cpu_rdata(imem_rdata), .cpu_ready(imem_ready),
        .l2_req(l2_i_req), .l2_addr(l2_i_addr), .l2_rdata(l2_i_rdata), .l2_ready(l2_i_ready)
    );

    // Level 1 Data Cache
    cache_l1d l1d (
        .clk(clk), .rst(rst),
        .cpu_req(dmem_req), .cpu_we(dmem_we), .cpu_addr(dmem_addr), .cpu_wdata(dmem_wdata), .cpu_rdata(dmem_rdata), .cpu_ready(dmem_ready),
        .l2_req(l2_d_req), .l2_we(l2_d_we), .l2_addr(l2_d_addr), .l2_wdata(l2_d_wdata), .l2_rdata(l2_d_rdata), .l2_ready(l2_d_ready)
    );

    // Unified Level 2 Cache
    cache_l2 l2 (
        .clk(clk), .rst(rst),
        .l1i_req(l2_i_req), .l1i_addr(l2_i_addr), .l1i_rdata(l2_i_rdata), .l1i_ready(l2_i_ready),
        .l1d_req(l2_d_req), .l1d_we(l2_d_we), .l1d_addr(l2_d_addr), .l1d_wdata(l2_d_wdata), .l1d_rdata(l2_d_rdata), .l1d_ready(l2_d_ready),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ready(mem_ready)
    );

    // Main Memory Simulator
    sim_dram dram (
        .clk(clk), .rst(rst),
        .req(mem_req), .we(mem_we), .addr(mem_addr), .wdata(mem_wdata), .rdata(mem_rdata), .ready(mem_ready)
    );

    // ==========================================
    // SIMULATION CONTROL
    // ==========================================
    initial begin
        // Setup GTKWave to dump all signals so we can look at them later
        $dumpfile("mips_waveform.vcd");
        $dumpvars(0, tb_system);

        // Start by resetting the whole system
        rst = 1;
        #20 rst = 0;
        
        // Let it run for a while. We expect the test program to finish relatively quickly.
        #2000;
        $display("Simulation completed. Check mips_waveform.vcd in GTKWave.");
        $finish;
    end

endmodule
