`timescale 1ns/1ps
module sim_dram(
    input logic clk,
    input logic rst,
    input logic req,
    input logic we,
    input logic [31:0] addr,
    input logic [127:0] wdata,
    output logic [127:0] rdata,
    output logic ready
);

logic [127:0] memory [0:255];
logic [3:0] counter;
logic waiting;
logic dbg_dram_busy;

assign dbg_dram_busy = waiting;

initial begin

    // Block 0
    memory[0] = {

        // SW R5,16(R0)
        32'hAC050010,

        // LW R5,16(R0)
        32'h8C050010,

        // ADD R3,R1,R2
        32'h00221820,

        // ADDI R1,R0,5
        32'h20010005
    };

    // Block 1
    memory[1] = {

        // NOP
        32'h00000000,

        // ORI R4,R3,0x00FF
        32'h346400FF,

        // ADDI R2,R1,10
        32'h2022000A,

        // ADD R6,R3,R4
        32'h00643020
    };

    // Block 2
    memory[2] = {

        // NOP
        32'h00000000,

        // ADDI R7,R6,1
        32'h20C70001,

        // ADD R8,R7,R1
        32'h00E14020,

        // SW R8,20(R0)
        32'hAC080014
    };

end

always_ff @(posedge clk or posedge rst) begin
    if(rst) begin
        counter <= 0;
        waiting <= 0;
        ready <= 0;
    end
    else begin
        ready <= 0;

        if(req && !waiting) begin
            waiting <= 1;
            counter <= 0;
        end

        if(waiting) begin
            counter <= counter + 1;

            if(counter == 4) begin
                rdata <= memory[addr[13:4]];
                ready <= 1;
                waiting <= 0;
            end
        end
    end
end
endmodule
