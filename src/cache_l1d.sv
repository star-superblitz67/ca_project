// L1 Data Cache (1KB, 2-way set-associative, write-back)
// Connects to cache_l2 for misses
// LRU replacement for 2-way sets

module cache_l1d #(
    parameter DATA_WIDTH  = 32,
    parameter ADDR_WIDTH  = 32,
    parameter LINE_SIZE   = 16,  // bytes (4 words)
    parameter NUM_SETS    = 32,
    parameter NUM_WAYS    = 2,
    parameter MISS_LATENCY = 8   // cycles from L1D miss to L2 response
) (
    input  logic                        clk,
    input  logic                        rst_n,
    
    // CPU/Pipeline interface (from MEM stage)
    input  logic                        cpu_read,
    input  logic                        cpu_write,
    input  logic [ADDR_WIDTH-1:0]       cpu_addr,
    input  logic [DATA_WIDTH-1:0]       cpu_wdata,
    output logic [DATA_WIDTH-1:0]       cpu_rdata,
    output logic                        mem_stall,
    
    // L2 interface (read/write to cache_l2)
    output logic                        l2_read,
    output logic                        l2_write,
    output logic [ADDR_WIDTH-1:0]       l2_addr,
    output logic [DATA_WIDTH-1:0]       l2_wdata,
    input  logic [DATA_WIDTH-1:0]       l2_rdata,
    input  logic                        l2_ready
);

    // Cache dimensions
    localparam OFFSET_BITS = $clog2(LINE_SIZE / 4);  // 2 bits for 4 words
    localparam INDEX_BITS  = $clog2(NUM_SETS);        // 5 bits for 32 sets
    localparam TAG_BITS    = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS - 2;  // 23 bits

    // Address decomposition
    logic [TAG_BITS-1:0]    tag_in;
    logic [INDEX_BITS-1:0]  index_in;
    logic [OFFSET_BITS-1:0] offset_in;

    assign offset_in = cpu_addr[OFFSET_BITS+1:2];
    assign index_in  = cpu_addr[INDEX_BITS+OFFSET_BITS+1:OFFSET_BITS+2];
    assign tag_in    = cpu_addr[ADDR_WIDTH-1:INDEX_BITS+OFFSET_BITS+2];

    // Cache storage: [set][way]
    logic [TAG_BITS-1:0]    tag_array    [0:NUM_SETS-1][0:NUM_WAYS-1];
    logic                   valid_array  [0:NUM_SETS-1][0:NUM_WAYS-1];
    logic                   dirty_array  [0:NUM_SETS-1][0:NUM_WAYS-1];
    logic [DATA_WIDTH-1:0]  data_array   [0:(NUM_SETS*NUM_WAYS*(LINE_SIZE/4))-1];

    // LRU state: 1 bit per set (0 = way0 most recently used, 1 = way1 most recently used)
    logic lru_array [0:NUM_SETS-1];

    // FSM states
    typedef enum logic [2:0] {
        IDLE,           // Normal operation
        WRITEBACK,      // Writing dirty line to L2
        ALLOCATE        // Reading missing line from L2
    } state_t;

    state_t state, next_state;
    logic [2:0]             victim_way;
    logic                   hit;
    logic [2:0]             hit_way;
    
    // Unrolled hit detection for 2-way (compatible with Icarus)
    logic hit_way0, hit_way1;
    
    always_comb begin
        hit_way0 = valid_array[index_in][0] && (tag_array[index_in][0] == tag_in);
        hit_way1 = valid_array[index_in][1] && (tag_array[index_in][1] == tag_in);
    end

    always_comb begin
        hit = hit_way0 | hit_way1;
        if (hit_way0)
            hit_way = 3'd0;
        else if (hit_way1)
            hit_way = 3'd1;
        else
            hit_way = 3'd0;
    end

    // LRU victim selection for 2-way: 
    // lru_array[set] == 0 -> way0 is LRU (victim is way0)
    // lru_array[set] == 1 -> way1 is LRU (victim is way1)
    always_comb begin
        victim_way = {2'b0, lru_array[index_in]};
    end

    // Update LRU on every hit
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int s = 0; s < NUM_SETS; s = s + 1) begin
                lru_array[s] <= 1'b0;
            end
        end else if (hit && state == IDLE) begin
            // Mark accessed way as most-recently-used (opposite of victim)
            lru_array[index_in] <= ~hit_way[0];  // If way0 hit, mark way1 as LRU
        end else if (state == ALLOCATE && l2_ready) begin
            // Mark allocated way as most-recently-used
            lru_array[index_in] <= ~victim_way[0];  // If way0 allocated, mark way1 as LRU
        end
    end

    // Victim line metadata
    logic victim_valid, victim_dirty;
    logic [TAG_BITS-1:0] victim_tag;
    
    always_comb begin
        if (victim_way == 3'd0) begin
            victim_valid = valid_array[index_in][0];
            victim_dirty = dirty_array[index_in][0];
            victim_tag = tag_array[index_in][0];
        end else begin
            victim_valid = valid_array[index_in][1];
            victim_dirty = dirty_array[index_in][1];
            victim_tag = tag_array[index_in][1];
        end
    end

    // FSM state transitions and L2 requests
    always_comb begin
        next_state = state;
        l2_read = 1'b0;
        l2_write = 1'b0;
        l2_addr = cpu_addr;
        l2_wdata = 32'b0;
        cpu_rdata = 32'b0;
        mem_stall = 1'b0;

        if (state == IDLE) begin
            if (cpu_read | cpu_write) begin
                if (hit) begin
                    mem_stall = 1'b0;  // Hit: no stall
                    next_state = IDLE;
                end else begin
                    // Miss: check if victim line is dirty
                    if (victim_valid && victim_dirty) begin
                        next_state = WRITEBACK;  // Dirty eviction needed
                    end else begin
                        next_state = ALLOCATE;   // Clean eviction or invalid line
                    end
                    mem_stall = 1'b1;  // Stall pipeline on miss
                end
            end
        end else if (state == WRITEBACK) begin
            l2_write = 1'b1;
            l2_addr = {victim_tag, index_in, 4'b0};  // Line-aligned address
            l2_wdata = 32'b0;  // Simplified: would write full line
            mem_stall = 1'b1;
            if (l2_ready) begin
                next_state = ALLOCATE;  // After writeback, fetch new line
            end
        end else if (state == ALLOCATE) begin
            l2_read = 1'b1;
            l2_addr = {tag_in, index_in, 4'b0};  // Line-aligned address
            mem_stall = 1'b1;
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
            if (hit_way == 3'd0)
                cpu_rdata = data_array[index_in * NUM_WAYS * (LINE_SIZE/4) + 0 * (LINE_SIZE/4) + offset_in];
            else if (hit_way == 3'd1)
                cpu_rdata = data_array[index_in * NUM_WAYS * (LINE_SIZE/4) + 1 * (LINE_SIZE/4) + offset_in];
            else
                cpu_rdata = 32'b0;
        end else begin
            cpu_rdata = l2_rdata;
        end
    end

    // Write path (hit only, write-back)
    always_ff @(posedge clk) begin
        if (cpu_write && hit && state == IDLE) begin
            if (hit_way == 3'd0) begin
                data_array[index_in * NUM_WAYS * (LINE_SIZE/4) + 0 * (LINE_SIZE/4) + offset_in] <= cpu_wdata;
                dirty_array[index_in][0] <= 1'b1;  // Mark as dirty on write
            end else if (hit_way == 3'd1) begin
                data_array[index_in * NUM_WAYS * (LINE_SIZE/4) + 1 * (LINE_SIZE/4) + offset_in] <= cpu_wdata;
                dirty_array[index_in][1] <= 1'b1;  // Mark as dirty on write
            end
        end

        // On L2 data arrival (allocate), write full line
        if (state == ALLOCATE && l2_ready) begin
            if (victim_way == 3'd0) begin
                valid_array[index_in][0] <= 1'b1;
                tag_array[index_in][0] <= tag_in;
                dirty_array[index_in][0] <= 1'b0;  // Fresh line from L2
                data_array[index_in * NUM_WAYS * (LINE_SIZE/4) + 0 * (LINE_SIZE/4) + offset_in] <= l2_rdata;
            end else if (victim_way == 3'd1) begin
                valid_array[index_in][1] <= 1'b1;
                tag_array[index_in][1] <= tag_in;
                dirty_array[index_in][1] <= 1'b0;  // Fresh line from L2
                data_array[index_in * NUM_WAYS * (LINE_SIZE/4) + 1 * (LINE_SIZE/4) + offset_in] <= l2_rdata;
            end
        end
    end

    // Initialize cache on reset
    initial begin
        for (int s = 0; s < NUM_SETS; s = s + 1) begin
            for (int w = 0; w < NUM_WAYS; w = w + 1) begin
                tag_array[s][w] <= {TAG_BITS{1'b0}};
                valid_array[s][w] <= 1'b0;
                dirty_array[s][w] <= 1'b0;
            end
            lru_array[s] <= 1'b0;
        end
        for (int i = 0; i < (NUM_SETS * NUM_WAYS * (LINE_SIZE/4)); i = i + 1) begin
            data_array[i] <= 32'b0;
        end
    end

endmodule
