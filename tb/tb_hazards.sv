`timescale 1ns/1ps
// Testbench: Hazards (load-use stall + branch flush)
// Specifically tests that:
//   1. A load followed immediately by a dependent instruction inserts exactly 1 bubble.
//   2. A taken branch flushes the 2 instructions behind it.
//
// Program:
//   0x00: ADDI R1,R0,5     R1 = 5
//   0x04: ADDI R2,R0,5     R2 = 5
//   0x08: SW   R1,0x40(R0)  mem[0x40] = 5  (L1D miss, write-through)
//   0x0C: LW   R3,0x40(R0)  R3 = 5         (L1D miss, DRAM refill)
//   0x10: ADD  R4,R3,R2     R4 = 10        (load-use stall: R3 from LW above)
//   0x14: ADDI R5,R0,1      R5 = 1         (set before branch)
//   0x18: BEQ  R1,R2,+1     R1==R2, taken -> 0x20
//   0x1C: ADDI R5,R0,99     FLUSHED (if R5=99, flush broke)
//   0x20: ADDI R5,R0,42     R5 = 42        (branch target, also L1I miss)
//
// Expected: R1=5  R2=5  R3=5  R4=10  R5=42

module tb_hazards;

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
        $dumpfile("tb_hazards.vcd");
        $dumpvars(0, tb_hazards);

        // Instruction encodings:
        //   ADDI R1,R0,5   = 0x20010005
        //   ADDI R2,R0,5   = 0x20020005
        //   SW   R1,64(R0) = 0xAC010040
        //   LW   R3,64(R0) = 0x8C030040
        //   ADD  R4,R3,R2  = 0x00622020  (rs=3,rt=2,rd=4)
        //   ADDI R5,R0,1   = 0x20050001
        //   BEQ  R1,R2,+1  = 0x10220001  (target = 0x1C+4 = 0x20)
        //   ADDI R5,R0,99  = 0x20050063  <- flushed
        //   ADDI R5,R0,42  = 0x2005002A  <- branch target

        // block 0: [127:96]=LW [95:64]=SW [63:32]=ADDI R2 [31:0]=ADDI R1
        dram.memory[0] = {32'h8C030040, 32'hAC010040, 32'h20020005, 32'h20010005};
        // block 1: [127:96]=ADDI R5=99(flush) [95:64]=BEQ [63:32]=ADDI R5=1 [31:0]=ADD R4
        dram.memory[1] = {32'h20050063, 32'h10220001, 32'h20050001, 32'h00622020};
        // block 2: [31:0]=ADDI R5=42 (branch target), rest NOP
        dram.memory[2] = {32'h00000000, 32'h00000000, 32'h00000000, 32'h2005002A};

        $display("--- Hazards Testbench ---");
        $display("Tests load-use stall (LW->ADD) and branch flush (BEQ taken).");
        $display("Expect 1 load-use stall. R5 should be 42, not 99 (flush works).");

        rst = 1'b1; @(posedge clk); #1; @(posedge clk); #1;
        rst = 1'b0;

        #3000;

        $display("--- Results ---");
        chk("R1", r1, 32'd5,  "ADDI");
        chk("R2", r2, 32'd5,  "ADDI");
        chk("R3", r3, 32'd5,  "LW [L1D miss]");
        chk("R4", r4, 32'd10, "ADD [load-use stall on R3]");
        chk("R5", r5, 32'd42, "ADDI [branch target; not 99 = flush worked]");

        $display("--- Cycle Stats ---");
        $display("Total cycles      : %0d", total_cycles);
        $display("Load-use stalls   : %0d  (expect 1)", lu_stall_cycles);
        $display("Cache stall cycles: %0d", cache_stall_cycles);
        $display("--- Done ---");
        $finish;
    end

    task automatic chk(input string name, input logic [31:0] got, exp, input string note);
        if (got === exp) $display("  PASS  %s = %0d  | %s", name, got, note);
        else             $display("  FAIL  %s = %0d (expected %0d)  | %s", name, got, exp, note);
    endtask

endmodule
