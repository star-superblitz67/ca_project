// L1 Instruction Cache (1KB, direct-mapped, read-only)
// Connects to cache_l2 for misses
// No write operations, no replacement policy needed

module cache_l1i #(
    parameter DATA_WIDTH  = 32,
    parameter ADDR_WIDTH  = 32,
    parameter LINE_SIZE   = 16,  // bytes (4 words)
    parameter NUM_SETS    = 64,
    parameter NUM_WAYS    = 1,   // Direct-mapped
    parameter MISS_LATENCY = 8   // cycles from L1I miss to L2 response
) (
    input  logic                        clk,
    input  logic                        rst_n,
    
    // CPU/Pipeline interface (from IF stage)
    input  logic                        cpu_read,
    input  logic [ADDR_WIDTH-1:0]       cpu_addr,
    output logic [DATA_WIDTH-1:0]       cpu_rdata,
    output logic                        if_stall,
    
    // L2 interface (read from cache_l2)
    output logic                        l2_read,
    output logic [ADDR_WIDTH-1:0]       l2_addr,
    input  logic [DATA_WIDTH-1:0]       l2_rdata,
    input  logic                        l2_ready
);

    // Cache dimensions
    localparam OFFSET_BITS = $clog2(LINE_SIZE / 4);  // 2 bits for 4 words
    localparam INDEX_BITS  = $clog2(NUM_SETS);        // 6 bits for 64 sets
    localparam TAG_BITS    = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS - 2;  // 22 bits

    // Address decomposition
    logic [TAG_BITS-1:0]    tag_in;
    logic [INDEX_BITS-1:0]  index_in;
    logic [OFFSET_BITS-1:0] offset_in;

    assign offset_in = cpu_addr[OFFSET_BITS+1:2];
    assign index_in  = cpu_addr[INDEX_BITS+OFFSET_BITS+1:OFFSET_BITS+2];
    assign tag_in    = cpu_addr[ADDR_WIDTH-1:INDEX_BITS+OFFSET_BITS+2];

    // Cache storage: direct-mapped [set][0]
    logic [TAG_BITS-1:0]    tag_array    [0:NUM_SETS-1];
    logic                   valid_array  [0:NUM_SETS-1];
    logic [DATA_WIDTH-1:0]  data_array   [0:(NUM_SETS*(LINE_SIZE/4))-1];

    // FSM states
    typedef enum logic [1:0] {
        IDLE,           // Normal operation
        ALLOCATE        // Reading missing line from L2
    } state_t;

    state_t state, next_state;
    logic hit;
    
    // Combinational hit detection (direct-mapped)
    always_comb begin
        hit = valid_array[index_in] && (tag_array[index_in] == tag_in);
    end

    // FSM state transitions and L2 requests
    always_comb begin
        next_state = state;
        l2_read = 1'b0;
        l2_addr = cpu_addr;
        cpu_rdata = 32'b0;
        if_stall = 1'b0;

        if (state == IDLE) begin
            if (cpu_read) begin
                if (hit) begin
                    if_stall = 1'b0;  // Hit: no stall
                    next_state = IDLE;
                end else begin
                    // Miss: fetch from L2
                    next_state = ALLOCATE;
                    if_stall = 1'b1;  // Stall pipeline on miss
                end
            end
        end else if (state == ALLOCATE) begin
            l2_read = 1'b1;
            l2_addr = {tag_in, index_in, 4'b0};  // Line-aligned address
            if_stall = 1'b1;
            if (l2_ready) begin
                // Fetch from L2 complete
                next_state = IDLE;
            end
        end else begin
            next_state = IDLE;
        end
    end

    // Sequential state update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // Cache data read logic
    always_comb begin
        if (hit) begin
            // Read from cache on hit
            cpu_rdata = data_array[index_in * (LINE_SIZE/4) + offset_in];
        end else begin
            cpu_rdata = l2_rdata;
        end
    end

    // Instruction fetch (no write operations)
    always_ff @(posedge clk) begin
        // On L2 data arrival (allocate), write full line
        if (state == ALLOCATE && l2_ready) begin
            valid_array[index_in] <= 1'b1;
            tag_array[index_in] <= tag_in;
            data_array[index_in * (LINE_SIZE/4) + offset_in] <= l2_rdata;
        end
    end

    // Initialize cache on reset
    initial begin
        for (int s = 0; s < NUM_SETS; s = s + 1) begin
            tag_array[s] <= {TAG_BITS{1'b0}};
            valid_array[s] <= 1'b0;
        end
        for (int i = 0; i < (NUM_SETS * (LINE_SIZE/4)); i = i + 1) begin
            data_array[i] <= 32'b0;
        end
    end

endmodule
