`timescale 1ns/1ps
module sim_dram(
    input  logic         clk, rst, req, we,
    input  logic [31:0]  addr,
    input  logic [127:0] wdata,
    output logic [127:0] rdata,
    output logic         ready
);
    logic [127:0] memory [0:255];
    logic [2:0]   cnt;
    logic         busy;
    logic [31:0]  latched_addr;
    logic         latched_we;
    logic [127:0] latched_wdata;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cnt <= 3'd0; busy <= 1'b0;
            latched_addr <= 32'd0; latched_we <= 1'b0; latched_wdata <= 128'd0;
        end else if (!busy && req) begin
            busy <= 1'b1; cnt <= 3'd1;
            latched_addr <= addr; latched_we <= we; latched_wdata <= wdata;
        end else if (busy) begin
            if (cnt == 3'd4) begin
                busy <= 1'b0; cnt <= 3'd0;
                if (latched_we) begin
                    case (latched_addr[3:2])
                        2'd0: memory[latched_addr[31:4]][31:0]   <= latched_wdata[31:0];
                        2'd1: memory[latched_addr[31:4]][63:32]  <= latched_wdata[31:0];
                        2'd2: memory[latched_addr[31:4]][95:64]  <= latched_wdata[31:0];
                        2'd3: memory[latched_addr[31:4]][127:96] <= latched_wdata[31:0];
                    endcase
                end
            end else cnt <= cnt + 3'd1;
        end
    end

    assign ready = busy && (cnt == 3'd4);
    assign rdata = memory[latched_addr[31:4]];

    // ----------------------------------------------------------------
    // COMPREHENSIVE DEMO PROGRAM – all pipeline + cache features
    // ----------------------------------------------------------------
    // Block 0 (0x00-0x0F)  [L1I MISS #1]
    //   0x00: ADDI R1, R0,  8     R1 = 8
    //   0x04: ADDI R2, R0,  5     R2 = 5
    //   0x08: ADD  R3, R1, R2     R3 = 13   [EX forwarding: R1 in EX/MEM]
    //   0x0C: SUB  R4, R3, R2     R4 =  8   [EX forwarding: R3; MEM fwd: R2]
    //
    // Block 1 (0x10-0x1F)  [L1I MISS #2]
    //   0x10: SW   R4, 0x80(R0)   mem[0x80]=8   [L1D MISS – write-through DRAM]
    //   0x14: LW   R5, 0x80(R0)   R5 = 8        [L1D MISS – REFILL from DRAM]
    //   0x18: ADD  R6, R5, R3     R6 = 21       [Load-use stall bubble]
    //   0x1C: LW   R7, 0x80(R0)   R7 = 8        [L1D HIT – block already cached]
    //
    // Block 2 (0x20-0x2F)  [L1I MISS #3]
    //   0x20: BNE  R3, R4, +2     13≠8 → TAKEN → PC=0x30  [branch flush 0x24,0x28]
    //   0x24: ADDI R9, R0, 111    FLUSHED (wrong path)
    //   0x28: ADDI R9, R0, 222    FLUSHED (wrong path)
    //   0x2C: NOP
    //
    // Block 3 (0x30-0x3F)  [L1I MISS #4 – branch target block]
    //   0x30: ADD  R8, R6, R7     R8 = 29       [branch target; no hazard]
    //   0x34: NOP
    // Program layout - one instruction per comment, shows what each line tests
    //
    // Block 0 (0x00-0x0F) - first fetch, L1I miss
    //   0x00: ADDI R1, R0, 8     -> R1 = 8
    //   0x04: ADDI R2, R0, 5     -> R2 = 5
    //   0x08: ADD  R3, R1, R2    -> R3 = 13  (EX forwarding: R1 still in pipeline)
    //   0x0C: SUB  R4, R3, R2    -> R4 = 8   (EX fwd R3, MEM fwd R2)
    //
    // Block 1 (0x10-0x1F) - second block, L1I miss again
    //   0x10: SW   R4, 0x80(R0)  -> mem[0x80] = 8  (L1D miss, write-through to DRAM)
    //   0x14: LW   R5, 0x80(R0)  -> R5 = 8         (L1D miss, DRAM refill)
    //   0x18: ADD  R6, R5, R3    -> R6 = 21         (load-use stall on R5)
    //   0x1C: LW   R7, 0x80(R0)  -> R7 = 8          (L1D hit - block already in cache)
    //
    // Block 2 (0x20-0x2F) - third block, L1I miss
    //   0x20: ADDI R9, R0, 55    -> R9 = 55  (set R9 BEFORE branch - flush proof)
    //   0x24: BNE  R3, R4, +2    -> 13!=8, taken -> PC=0x30  (flushes 0x28 and 0x2C)
    //   0x28: ADDI R9, R0, 111   -> FLUSHED (if R9 becomes 111, flush is broken)
    //   0x2C: ADDI R9, R0, 222   -> FLUSHED
    //
    // Block 3 (0x30-0x3F) - branch target, L1I miss
    //   0x30: ADD  R8, R6, R7    -> R8 = 29  (21+8, no hazard)
    //   0x34: AND  R9, R8, R3    -> R9 = 13  (29 & 13 = 0b11101 & 0b01101 = 0b01101)
    //   0x38: NOP
    //   0x3C: NOP
    //
    // Expected final: R1=8 R2=5 R3=13 R4=8 R5=8 R6=21 R7=8 R8=29 R9=13

    initial begin
        // block 0
        memory[0] = {32'h00622022, 32'h00221820, 32'h20020005, 32'h20010008};

        // block 1
        memory[1] = {32'h8C070080, 32'h00A33020, 32'h8C050080, 32'hAC040080};

        // block 2: ADDI R9=55 | BNE R3,R4,+2 | ADDI R9=111(flushed) | ADDI R9=222(flushed)
        //   0x20: ADDI R9,R0,55  = 0x20090037
        //   0x24: BNE  R3,R4,+2  = 0x14640002  (target = 0x28 + 8 = 0x30)
        //   0x28: ADDI R9,R0,111 = 0x2009006F  flushed
        //   0x2C: ADDI R9,R0,222 = 0x200900DE  flushed
        memory[2] = {32'h200900DE, 32'h2009006F, 32'h14640002, 32'h20090037};

        // block 3: ADD R8,R6,R7 | AND R9,R8,R3 | NOP | NOP
        //   0x30: ADD R8,R6,R7  = 0x00C74020  (R8 = 21+8 = 29)
        //   0x34: AND R9,R8,R3  = 0x01034824  (R9 = 29 & 13 = 13)
        memory[3] = {32'h00000000, 32'h00000000, 32'h01034824, 32'h00C74020};

        for (int i = 4; i < 256; i++) memory[i] = 128'd0;
    end
endmodule
