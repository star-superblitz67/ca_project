`timescale 1ns / 1ps

module mips_processor (
    input  logic        clk,
    input  logic        rst,

    // L1 Instruction Cache Interface
    output logic        imem_req,
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,
    input  logic        imem_ready,

    // L1 Data Cache Interface
    output logic        dmem_req,
    output logic        dmem_we,
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    input  logic [31:0] dmem_rdata,
    input  logic        dmem_ready
);

    // ==========================================
    // DECLARATIONS (Harris & Harris Conventions)
    // ==========================================
    // We strictly use the Harris and Harris naming style here (F for Fetch, D for Decode, etc.)
    
    logic mem_stall;
    logic hazard_stall, flush_ID, flush_EX;
    logic en_PC, en_IF_ID, en_ID_EX, en_EX_MEM, en_MEM_WB;
    
    // FETCH (F) Stage Signals
    logic [31:0] PCF, PCPlus4F, PCNextF;
    logic [31:0] InstrF;
    
    // DECODE (D) Stage Signals
    logic [31:0] InstrD, PCPlus4D;
    logic [4:0]  RsD, RtD, RdD;
    logic [15:0] ImmD;
    logic [31:0] SignImmD, ZeroImmD, ExtImmD;
    logic [5:0]  OpcodeD, FunctD;
    logic [31:0] RD1D, RD2D;
    logic        RegWriteD, MemtoRegD, MemWriteD, BranchD, ALUSrcD, RegDstD;
    logic [2:0]  ALUControlD;
    logic        BranchTakenD;
    logic [31:0] BranchTargetD;
    
    // EXECUTE (E) Stage Signals
    logic [31:0] RD1E, RD2E, ExtImmE;
    logic [4:0]  RsE, RtE, RdE, WriteRegE;
    logic        RegWriteE, MemtoRegE, MemWriteE, ALUSrcE, RegDstE;
    logic [2:0]  ALUControlE;
    logic [31:0] SrcAE, SrcBE, ALUOutE, WriteDataE;
    logic [1:0]  ForwardAE, ForwardBE;
    
    // MEMORY (M) Stage Signals
    logic [31:0] ALUOutM, WriteDataM, ReadDataM;
    logic [4:0]  WriteRegM;
    logic        RegWriteM, MemtoRegM, MemWriteM;
    
    // WRITEBACK (W) Stage Signals
    logic [31:0] ReadDataW, ALUOutW, ResultW;
    logic [4:0]  WriteRegW;
    logic        RegWriteW, MemtoRegW;

    // The core register file
    logic [31:0] reg_file [0:31];
    integer i;

    // ==========================================
    // PIPELINE STALL LOGIC
    // ==========================================
    // If either cache isn't ready, the entire pipeline freezes!
    assign mem_stall = (imem_req && !imem_ready) || (dmem_req && !dmem_ready);

    assign en_PC     = !mem_stall && !hazard_stall;
    assign en_IF_ID  = !mem_stall && !hazard_stall;
    assign en_ID_EX  = !mem_stall;
    assign en_EX_MEM = !mem_stall;
    assign en_MEM_WB = !mem_stall;

    // ==========================================
    // FETCH (F) STAGE
    // ==========================================
    assign PCPlus4F = PCF + 4;
    assign PCNextF  = BranchTakenD ? BranchTargetD : PCPlus4F;
    
    assign imem_req  = 1'b1; // Always asking for the next instruction
    assign imem_addr = PCF;
    assign InstrF    = imem_rdata;

    // Update the PC register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) PCF <= 32'b0;
        else if (en_PC) PCF <= PCNextF;
    end

    // IF/ID Pipeline Register
    always_ff @(posedge clk or posedge rst) begin
        if (rst || (flush_ID && !mem_stall)) begin
            InstrD   <= 32'b0;
            PCPlus4D <= 32'b0;
        end else if (en_IF_ID) begin
            InstrD   <= InstrF;
            PCPlus4D <= PCPlus4F;
        end
    end

    // ==========================================
    // DECODE (D) STAGE
    // ==========================================
    // Slice up the instruction
    assign RsD    = InstrD[25:21];
    assign RtD    = InstrD[20:16];
    assign RdD    = InstrD[15:11];
    assign ImmD   = InstrD[15:0];
    assign OpcodeD= InstrD[31:26];
    assign FunctD = InstrD[5:0];

    // Extensions for immediates
    assign SignImmD = {{16{ImmD[15]}}, ImmD};
    assign ZeroImmD = {16'b0, ImmD};
    
    // Special case: ORI uses zero extension, everything else uses sign extension
    assign ExtImmD  = (OpcodeD == 6'h0D) ? ZeroImmD : SignImmD;

    // Control Unit Logic
    always_comb begin
        // Setting up default values
        RegWriteD = 0; MemtoRegD = 0; MemWriteD = 0; BranchD = 0;
        ALUSrcD = 0; RegDstD = 0; ALUControlD = 3'b000;
        
        case(OpcodeD)
            6'h00: begin // R-Type instructions (ADD, SUB, AND, OR, SLT)
                RegDstD = 1; RegWriteD = 1;
                case(FunctD)
                    6'h20: ALUControlD = 3'b010; 
                    6'h22: ALUControlD = 3'b110; 
                    6'h24: ALUControlD = 3'b000; 
                    6'h25: ALUControlD = 3'b001; 
                    6'h2A: ALUControlD = 3'b111; 
                endcase
            end
            6'h08: begin // ADDI
                ALUSrcD = 1; RegWriteD = 1; ALUControlD = 3'b010;
            end
            6'h0D: begin // ORI
                ALUSrcD = 1; RegWriteD = 1; ALUControlD = 3'b001;
            end
            6'h23: begin // LW (Load Word)
                ALUSrcD = 1; MemtoRegD = 1; RegWriteD = 1; ALUControlD = 3'b010;
            end
            6'h2B: begin // SW (Store Word)
                ALUSrcD = 1; MemWriteD = 1; ALUControlD = 3'b010;
            end
            6'h04: begin // BEQ (Branch on Equal)
                BranchD = 1; ALUControlD = 3'b110;
            end
        endcase
    end

    // Clean out the register file initially
    initial begin
        for (i = 0; i < 32; i = i + 1) reg_file[i] = 32'b0;
    end

    // Write back to the register file on the *falling* clock edge
    // This solves issues where we read and write to the same register in the same cycle
    always_ff @(negedge clk) begin
        if (RegWriteW && WriteRegW != 0 && !mem_stall) begin
            reg_file[WriteRegW] <= ResultW;
        end
    end

    // Grab data from registers (reg 0 is always 0)
    assign RD1D = (RsD == 0) ? 0 : reg_file[RsD];
    assign RD2D = (RtD == 0) ? 0 : reg_file[RtD];

    // Calculate branch info early in Decode stage
    assign BranchTargetD = PCPlus4D + (ExtImmD << 2);
    assign BranchTakenD  = BranchD && (RD1D == RD2D);

    // ID/EX Pipeline Register
    always_ff @(posedge clk or posedge rst) begin
        if (rst || (flush_EX && !mem_stall)) begin
            RD1E <= 0; RD2E <= 0; ExtImmE <= 0; RsE <= 0; RtE <= 0; RdE <= 0;
            RegWriteE <= 0; MemtoRegE <= 0; MemWriteE <= 0; ALUSrcE <= 0; RegDstE <= 0; ALUControlE <= 0;
        end else if (en_ID_EX) begin
            RD1E <= RD1D; RD2E <= RD2D; ExtImmE <= ExtImmD; RsE <= RsD; RtE <= RtD; RdE <= RdD;
            RegWriteE <= RegWriteD; MemtoRegE <= MemtoRegD; MemWriteE <= MemWriteD; 
            ALUSrcE <= ALUSrcD; RegDstE <= RegDstD; ALUControlE <= ALUControlD;
        end
    end

    // ==========================================
    // EXECUTE (E) STAGE
    // ==========================================
    // Applying forwarded data if the Forwarding Unit tells us to
    always_comb begin
        case(ForwardAE)
            2'b10: SrcAE = ALUOutM;
            2'b01: SrcAE = ResultW;
            default: SrcAE = RD1E;
        endcase
        
        case(ForwardBE)
            2'b10: WriteDataE = ALUOutM;
            2'b01: WriteDataE = ResultW;
            default: WriteDataE = RD2E;
        endcase
    end

    // Decide if ALU input B is a register or an immediate value
    assign SrcBE = ALUSrcE ? ExtImmE : WriteDataE;
    
    // Determine which register we're writing the result to
    assign WriteRegE = RegDstE ? RdE : RtE;

    // The Arithmetic Logic Unit
    always_comb begin
        case(ALUControlE)
            3'b010: ALUOutE = SrcAE + SrcBE;
            3'b110: ALUOutE = SrcAE - SrcBE;
            3'b000: ALUOutE = SrcAE & SrcBE;
            3'b001: ALUOutE = SrcAE | SrcBE;
            3'b111: ALUOutE = ($signed(SrcAE) < $signed(SrcBE)) ? 32'b1 : 32'b0;
            default: ALUOutE = 32'b0;
        endcase
    end

    // EX/MEM Pipeline Register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ALUOutM <= 0; WriteDataM <= 0; WriteRegM <= 0;
            RegWriteM <= 0; MemtoRegM <= 0; MemWriteM <= 0;
        end else if (en_EX_MEM) begin
            ALUOutM <= ALUOutE; WriteDataM <= WriteDataE; WriteRegM <= WriteRegE;
            RegWriteM <= RegWriteE; MemtoRegM <= MemtoRegE; MemWriteM <= MemWriteE;
        end
    end

    // ==========================================
    // MEMORY (M) STAGE
    // ==========================================
    // Hooking up the Data Cache interface
    assign dmem_req   = MemtoRegM || MemWriteM;
    assign dmem_we    = MemWriteM;
    assign dmem_addr  = ALUOutM;
    assign dmem_wdata = WriteDataM;
    assign ReadDataM  = dmem_rdata;

    // MEM/WB Pipeline Register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ReadDataW <= 0; ALUOutW <= 0; WriteRegW <= 0;
            RegWriteW <= 0; MemtoRegW <= 0;
        end else if (en_MEM_WB) begin
            ReadDataW <= ReadDataM;
            ALUOutW <= ALUOutM;
            WriteRegW <= WriteRegM;
            RegWriteW <= RegWriteM;
            MemtoRegW <= MemtoRegM;
        end
    end

    // ==========================================
    // WRITEBACK (W) STAGE
    // ==========================================
    // Pick the final result to write back to the register file
    assign ResultW = MemtoRegW ? ReadDataW : ALUOutW;

    // ==========================================
    // SUBMODULE INSTANTIATIONS
    // ==========================================
    hazard_unit hazard_u (
        .rs_ID(RsD), .rt_ID(RtD), .rt_EX(RtE),
        .mem_read_EX(MemtoRegE), .branch_taken(BranchTakenD),
        .stall_pipeline(hazard_stall), .flush_ID(flush_ID), .flush_EX(flush_EX)
    );

    forwarding_unit forward_u (
        .rs_EX(RsE), .rt_EX(RtE),
        .rd_MEM(WriteRegM), .reg_write_MEM(RegWriteM),
        .rd_WB(WriteRegW), .reg_write_WB(RegWriteW),
        .forward_A(ForwardAE), .forward_B(ForwardBE)
    );

endmodule
