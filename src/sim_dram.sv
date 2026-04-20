// Simulated DRAM with Parameterized Latency
// Flat memory array model with shift-register delay for mem_ready timing

module sim_dram #(
    parameter LATENCY = 20,      // Cycles until mem_ready asserts (default 20 for L2->DRAM)
    parameter ADDR_WIDTH = 12,   // Address width (supports up to 4KB flat array)
    parameter DATA_WIDTH = 32    // Data width (32-bit words)
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   mem_read,
    input  logic                   mem_write,
    input  logic [ADDR_WIDTH-1:0]  addr,
    input  logic [DATA_WIDTH-1:0]  write_data,
    output logic [DATA_WIDTH-1:0]  read_data,
    output logic                   mem_ready
);

    // Flat memory array (simplified: support up to 4096 words = 16KB)
    logic [DATA_WIDTH-1:0] memory [0:(1 << ADDR_WIDTH) - 1];

    // Shift register for mem_ready timing: tracks when a read/write was issued
    // When a valid transaction occurs, load the shift register
    // mem_ready asserts when the shift register counts down to 0
    logic [7:0] ready_shift_reg;  // 8-bit shift register (supports LATENCY up to 255)
    logic transaction_valid;

    assign transaction_valid = mem_read | mem_write;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready_shift_reg <= 8'b0;
        end else begin
            if (transaction_valid) begin
                // New transaction: load the shift register with LATENCY value
                ready_shift_reg <= LATENCY[7:0];
            end else if (ready_shift_reg != 8'b0) begin
                // Countdown: decrement each cycle until we reach 0
                ready_shift_reg <= ready_shift_reg - 1;
            end
        end
    end

    // mem_ready asserts when shift register reaches 0 AND a transaction was in flight
    assign mem_ready = (ready_shift_reg == 8'b0) && ~transaction_valid;

    // READ operation: combinational
    always_comb begin
        if (mem_read)
            read_data = memory[addr];
        else
            read_data = 32'b0;
    end

    // WRITE operation: synchronous (executed on posedge clk)
    always_ff @(posedge clk) begin
        if (mem_write) begin
            memory[addr] <= write_data;
        end
    end

    // Initialize memory with some test data
    initial begin
        for (int i = 0; i < (1 << ADDR_WIDTH); i = i + 1) begin
            memory[i] = 32'b0;
        end
        // Optional: pre-load some test values
        memory[0]  = 32'hDEADBEEF;
        memory[1]  = 32'hCAFEBABE;
        memory[2]  = 32'hFEEDFACE;
        memory[4]  = 32'hC0DEFEED;
    end

endmodule
