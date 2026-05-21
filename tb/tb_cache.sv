`timescale 1ns/1ps
// Testbench: Cache Behavior (L1D miss, hit, same-block hit)
// Isolates the cache hierarchy from pipeline hazards.
// No load-use stalls (we put a gap between LW and its first use).
//
// Program:
//   0x00: ADDI R1,R0,7     R1 = 7
//   0x04: ADDI R2,R0,3     R2 = 3
//   0x08: SW   R1,0x20(R0)  mem[0x20] = 7  (L1D miss - write-through to DRAM)
//   0x0C: SW   R2,0x24(R0)  mem[0x24] = 3  (L1D miss - same block, write-through)
//   0x10: LW   R3,0x20(R0)  R3 = 7         (L1D miss - DRAM refill of block 0x20-0x2F)
//   0x14: LW   R4,0x24(R0)  R4 = 3         (L1D HIT  - same block already in cache)
//   0x18: LW   R5,0x20(R0)  R5 = 7         (L1D HIT  - still cached)
//   0x1C: NOP
//
// Expected: R1=7  R2=3  R3=7  R4=3  R5=7

module tb_cache;

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

    // count how many cycles L1D spends in each state
    integer total_cycles, lu_stall_cycles, cache_stall_cycles;
    integer l1d_miss_cycles, l1d_hit_count;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            total_cycles    <= 0; lu_stall_cycles <= 0;
            cache_stall_cycles <= 0; l1d_miss_cycles <= 0;
            l1d_hit_count   <= 0;
        end else begin
            total_cycles <= total_cycles + 1;
            if (cpu.stall_haz)   lu_stall_cycles   <= lu_stall_cycles + 1;
            if (cpu.cache_stall) cache_stall_cycles <= cache_stall_cycles + 1;
            // count L1D miss cycles (state != IDLE)
            if (l1d.state != 0)  l1d_miss_cycles <= l1d_miss_cycles + 1;
            // count L1D hits (ready in same cycle as req, state=IDLE)
            if (d_req && d_ready && l1d.state == 0) l1d_hit_count <= l1d_hit_count + 1;
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
        $dumpfile("tb_cache.vcd");
        $dumpvars(0, tb_cache);

        // Instruction encodings:
        //   ADDI R1,R0,7   = 0x20010007
        //   ADDI R2,R0,3   = 0x20020003
        //   SW   R1,32(R0) = 0xAC010020  (addr=0x20)
        //   SW   R2,36(R0) = 0xAC020024  (addr=0x24, same L1D block)
        //   LW   R3,32(R0) = 0x8C030020  (L1D miss - refill block 0x20-0x2F)
        //   LW   R4,36(R0) = 0x8C040024  (L1D HIT - same block)
        //   LW   R5,32(R0) = 0x8C050020  (L1D HIT - still cached)
        //   NOP            = 0x00000000

        // block 0: [127:96]=SW R2 [95:64]=SW R1 [63:32]=ADDI R2 [31:0]=ADDI R1
        dram.memory[0] = {32'hAC020024, 32'hAC010020, 32'h20020003, 32'h20010007};
        // block 1: [127:96]=NOP [95:64]=LW R5 [63:32]=LW R4 [31:0]=LW R3
        dram.memory[1] = {32'h00000000, 32'h8C050020, 32'h8C040024, 32'h8C030020};

        $display("--- Cache Testbench ---");
        $display("Two SWs + one LW miss, then two LW hits from the same cached block.");
        $display("Watch dram.cnt counting 1-2-3-4 for each DRAM transaction.");
        $display("LW hits should complete in 1 cycle (no stall).");

        rst = 1'b1; @(posedge clk); #1; @(posedge clk); #1;
        rst = 1'b0;

        #3000;

        $display("--- Results ---");
        chk("R1", r1, 32'd7, "ADDI baseline");
        chk("R2", r2, 32'd3, "ADDI baseline");
        chk("R3", r3, 32'd7, "LW [L1D miss - DRAM refill]");
        chk("R4", r4, 32'd3, "LW [L1D HIT - same block, word 1]");
        chk("R5", r5, 32'd7, "LW [L1D HIT - same block, word 0 again]");

        $display("--- Cache Stats ---");
        $display("Total cycles       : %0d", total_cycles);
        $display("Cache stall cycles : %0d  (3 DRAM hits x ~5 cycles each)", cache_stall_cycles);
        $display("L1D miss cycles    : %0d", l1d_miss_cycles);
        $display("L1D hit count      : %0d  (should be 2)", l1d_hit_count);
        $display("Load-use stalls    : %0d  (should be 0)", lu_stall_cycles);
        $display("--- Done ---");
        $finish;
    end

    task automatic chk(input string name, input logic [31:0] got, exp, input string note);
        if (got === exp) $display("  PASS  %s = %0d  | %s", name, got, note);
        else             $display("  FAIL  %s = %0d (expected %0d)  | %s", name, got, exp, note);
    endtask

endmodule
