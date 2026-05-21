`timescale 1ns/1ps
// Same DRAM logic as sim_dram.sv but no built-in program.
// The testbench loads whatever program it needs into dram.memory[].
module sim_dram_bare(
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

    // start with everything zeroed so unloaded blocks read as NOPs
    initial begin
        cnt          = 3'd0;
        busy         = 1'b0;
        latched_addr = 32'd0;
        latched_we   = 1'b0;
        latched_wdata = 128'd0;
        for (int i = 0; i < 256; i++) memory[i] = 128'd0;
    end

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

endmodule
