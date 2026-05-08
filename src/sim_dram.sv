`timescale 1ns / 1ps

module sim_dram (
    input  logic         clk,
    input  logic         rst,

    input  logic         req,
    input  logic         we,
    input  logic [31:0]  addr,
    input  logic [127:0] wdata,
    output logic [127:0] rdata,
    output logic         ready
);

    // Simulated 16KB DRAM block
    logic [127:0] memory [0:1023];

    // AMAT Latency parameter
    localparam LATENCY = 5;
    
    typedef enum logic [1:0] { IDLE, WAIT, RESPOND } state_t;
    state_t state, next_state;

    logic [3:0] counter;
    logic [31:0] active_addr;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            counter <= 0;
            for (i=0; i<1024; i=i+1) memory[i] <= 128'h0;
            
            // --- INJECT TEST PROGRAM HERE ---
            // 0xC: SW   $3, 16($0)   (0xAC030010)
            // 0x8: ADD  $3, $1, $2   (0x00221820)
            // 0x4: ADDI $2, $0, 10   (0x2002000A)
            // 0x0: ADDI $1, $0, 5    (0x20010005)
            // Packed together into one 128-bit cache line:
            memory[0] <= 128'hAC030010_00221820_2002000A_20010005;
        end else begin
            state <= next_state;
            
            if (state == WAIT) counter <= counter + 1;
            else               counter <= 0;

            if (state == IDLE && req) active_addr <= addr;
            if (state == RESPOND && we) memory[active_addr[13:4]] <= wdata;
        end
    end

    // Access sequence controller
    always_comb begin
        next_state = state;
        ready = 1'b0;
        rdata = 128'b0;

        case (state)
            IDLE:    if (req) next_state = WAIT;
            WAIT:    if (counter == LATENCY - 1) next_state = RESPOND;
            RESPOND: begin
                ready = 1'b1;
                if (!we) rdata = memory[active_addr[13:4]];
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

endmodule