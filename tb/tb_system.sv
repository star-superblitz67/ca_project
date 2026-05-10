`timescale 1ns/1ps

/**
 * System Testbench
 * Connects the CPU, L1 Caches, L2 Arbiter, and DRAM.
 */
module tb_system;
    logic clk = 0;
    logic rst;

    // CPU <-> L1
    logic i_req, i_ready, d_req, d_we, d_ready;
    logic [31:0] i_addr, i_data, d_addr, d_wdata, d_rdata;

    // L1 <-> L2
    logic l2i_req, l2i_ready, l2d_req, l2d_we, l2d_ready;
    logic [31:0] l2i_addr, l2d_addr;
    logic [127:0] l2i_rdata, l2d_wdata, l2d_rdata;

    // L2 <-> DRAM
    logic m_req, m_we, m_ready;
    logic [31:0] m_addr;
    logic [127:0] m_wdata, m_rdata;

    // Debug Registers
    logic [31:0] r1, r2, r3, r4, r5, r7;

    // Clock Generation
    always #5 clk = ~clk;

    mips_processor cpu(
        .clk(clk), .rst(rst),
        .imem_req(i_req), .imem_addr(i_addr), .imem_rdata(i_data), .imem_ready(i_ready),
        .dmem_req(d_req), .dmem_we(d_we), .dmem_addr(d_addr), .dmem_wdata(d_wdata), .dmem_rdata(d_rdata), .dmem_ready(d_ready),
        .dbg_r1(r1), .dbg_r2(r2), .dbg_r3(r3), .dbg_r4(r4), .dbg_r5(r5), .dbg_r7(r7)
    );

    cache_l1i l1i(
        .clk(clk), .rst(rst),
        .cpu_req(i_req), .cpu_addr(i_addr), .cpu_rdata(i_data), .cpu_ready(i_ready),
        .l2_req(l2i_req), .l2_addr(l2i_addr), .l2_rdata(l2i_rdata), .l2_ready(l2i_ready)
    );

    cache_l1d l1d(
        .clk(clk), .rst(rst),
        .cpu_req(d_req), .cpu_we(d_we), .cpu_addr(d_addr), .cpu_wdata(d_wdata), .cpu_rdata(d_rdata), .cpu_ready(d_ready),
        .l2_req(l2d_req), .l2_we(l2d_we), .l2_addr(l2d_addr), .l2_wdata(l2d_wdata), .l2_rdata(l2d_rdata), .l2_ready(l2d_ready)
    );

    cache_l2 l2(
        .clk(clk), .rst(rst),
        .l1i_req(l2i_req), .l1i_addr(l2i_addr), .l1i_rdata(l2i_rdata), .l1i_ready(l2i_ready),
        .l1d_req(l2d_req), .l1d_we(l2d_we), .l1d_addr(l2d_addr), .l1d_wdata(l2d_wdata), .l1d_rdata(l2d_rdata), .l1d_ready(l2d_ready),
        .mem_req(m_req), .mem_we(m_we), .mem_addr(m_addr), .mem_wdata(m_wdata), .mem_rdata(m_rdata), .mem_ready(m_ready)
    );

    sim_dram dram(
        .clk(clk), .rst(rst),
        .req(m_req), .we(m_we), .addr(m_addr), .wdata(m_wdata), .rdata(m_rdata), .ready(m_ready)
    );

    initial begin
        $dumpfile("mips_waveform.vcd");
        $dumpvars(0, tb_system);

        $display("--- Starting Simulation ---");
        rst = 1; #20; rst = 0;

        // Run for enough time to complete the program
        #3000;

        $display("\n--- Simulation Results ---");
        $display("R1 (Expected 5):   %0d", r1);
        $display("R2 (Expected 10):  %0d", r2);
        $display("R3 (Expected 15):  %0d", r3);
        $display("R4 (Expected 15):  %0d", r4);
        $display("R5 (Expected 20):  %0d", r5);
        $display("R7 (Expected 275): %0d", r7);
        
        $display("\nSimulation Finished.");
        $finish;
    end

endmodule
