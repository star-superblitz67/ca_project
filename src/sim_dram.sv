`timescale 1ns/1ps

/**
 * DRAM Simulator with 4-cycle Latency (Fixed)
 * Features:
 * - Word-level write support within 128-bit blocks (prevents code corruption).
 * - Pre-loaded with a textbook-style test program.
 */
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

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            counter <= 0;
            waiting <= 0;
        end else if (req && !waiting) begin
            waiting <= 1;
            counter <= 1;
        end else if (waiting) begin
            if (counter == 4) begin
                waiting <= 0;
                counter <= 0;
                if (we) begin
                    // Support word-level write to prevent overwriting adjacent instructions
                    case(addr[3:2])
                        2'b00: memory[addr[31:4]][31:0]   <= wdata[31:0];
                        2'b01: memory[addr[31:4]][63:32]  <= wdata[31:0]; // Broadcaster source
                        2'b10: memory[addr[31:4]][95:64]  <= wdata[31:0];
                        2'b11: memory[addr[31:4]][127:96] <= wdata[31:0];
                    endcase
                end
            end else begin
                counter <= counter + 1;
            end
        end
    end

    assign ready = (waiting && counter == 4);
    assign rdata = memory[addr[31:4]];

    initial begin
        // --- Test Program ---
        // Block 0: Initialization
        memory[0] = {
            32'hAC030080, // SW R3, 128(R0)  -> Target Address 0x80
            32'h00221820, // ADD R3, R1, R2
            32'h2002000A, // ADDI R2, R0, 10
            32'h20010005  // ADDI R1, R0, 5
        };

        // Block 1: Hazards and Stalls
        memory[1] = {
            32'h200603E7, // ADDI R6, R0, 999 (Should be flushed)
            32'h14A30001, // BNE R5, R3, 1    (If R5!=R3, skip next instruction)
            32'h00812820, // ADD R5, R4, R1   (Load-Use Hazard on R4)
            32'h8C040080  // LW R4, 128(R0)  <- Read from 0x80
        };

        // Block 2: Branch Target
        memory[2] = {
            32'h00000000, // NOP
            32'h00000000, // NOP
            32'hAC070084, // SW R7, 132(R0)
            32'h34A700FF  // ORI R7, R5, 0xFF (Target)
        };

        for (int i=3; i<256; i++) memory[i] = 0;
    end

endmodule
