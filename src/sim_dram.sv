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

    // ==========================================
    // DECLARATIONS
    // ==========================================
    // This latency simulates the slow access time of main memory
    localparam LATENCY = 5;
    
    localparam IDLE    = 2'b00;
    localparam WAIT    = 2'b01;
    localparam RESPOND = 2'b10;

    logic [1:0] state, next_state;

    // A small chunk of memory to simulate DRAM
    logic [127:0] memory [0:1023];
    logic [3:0] counter;
    logic [31:0] active_addr;
    integer i;

    // ==========================================
    // INITIALIZATION (Loads the test program)
    // ==========================================
    initial begin
        // Zero out memory so we don't get 'x' values in simulation
        for (i = 0; i < 1024; i = i + 1) begin
            memory[i] = 128'h0;
        end
        
        // --- OUR TEST PROGRAM ---
        // This is a simple program to prove the pipeline and caches work.
        // Address 0x0: ADDI $1, $0, 5    (0x20010005)
        // Address 0x4: ADDI $2, $0, 10   (0x2002000A)
        // Address 0x8: ADD  $3, $1, $2   (0x00221820)
        // Address 0xC: SW   $3, 16($0)   (0xAC030010)
        // We pack all 4 instructions into the very first 128-bit memory block.
        memory[0] = 128'hAC030010_00221820_2002000A_20010005;
    end

    // ==========================================
    // SEQUENTIAL LOGIC
    // ==========================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= IDLE;
            counter     <= 0;
            active_addr <= 32'b0;
        end else begin
            state <= next_state;
            
            // Keep track of how long we've been waiting
            if (state == WAIT) begin
                counter <= counter + 1;
            end else begin
                counter <= 0;
            end

            // Lock in the requested address when we start handling a request
            if (state == IDLE && req) begin
                active_addr <= addr;
            end
            
            // Actually do the writing if it's a write request
            if (state == RESPOND && we) begin
                memory[active_addr[13:4]] <= wdata;
            end
        end
    end

    // ==========================================
    // COMBINATIONAL LOGIC
    // ==========================================
    always_comb begin
        next_state = state;
        ready      = 1'b0;
        rdata      = 128'b0;

        case (state)
            IDLE: begin
                // Just hanging out until a request comes in
                if (req) begin
                    next_state = WAIT;
                end
            end
            
            WAIT: begin
                // Simulate the memory delay
                if (counter >= (LATENCY - 1)) begin
                    next_state = RESPOND;
                end
            end
            
            RESPOND: begin
                ready = 1'b1; // Tell the caller we're done
                if (!we) begin
                    rdata = memory[active_addr[13:4]]; // Give them the data if it was a read
                end
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end

endmodule
