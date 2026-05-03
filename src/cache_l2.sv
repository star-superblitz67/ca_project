// L2 Unified Cache (16KB, 4-way set-associative, write-back)
// Connects internally to sim_dram
// Pseudo-LRU replacement for 4-way sets

module cache_l2 #(
    parameter DATA_WIDTH  = 32,
    parameter ADDR_WIDTH  = 32,
    parameter LINE_SIZE   = 64,  // bytes
    parameter NUM_SETS    = 64,
    parameter NUM_WAYS    = 4,
    parameter DRAM_LATENCY = 20
) (
    input  logic                        clk,
    input  logic                        rst_n,
    
    // CPU/L1 interface (read/write from L1D or L1I)
    input  logic                        cpu_read,
    input  logic                        cpu_write,
    input  logic [ADDR_WIDTH-1:0]       cpu_addr,
    input  logic [DATA_WIDTH-1:0]       cpu_wdata,
    output logic [DATA_WIDTH-1:0]       cpu_rdata,
    output logic                        cpu_ready,
    
    // DRAM interface (read/write to sim_dram)
    output logic                        dram_read,
    output logic                        dram_write,
    output logic [ADDR_WIDTH-1:0]       dram_addr,
    output logic [DATA_WIDTH-1:0]       dram_wdata,
    input  logic [DATA_WIDTH-1:0]       dram_rdata,
    input  logic                        dram_ready
);

    // Cache dimensions
    localparam OFFSET_BITS = $clog2(LINE_SIZE / 4);  // 4 bits for 16-byte line (64B / 4 words)
    localparam INDEX_BITS  = $clog2(NUM_SETS);        // 6 bits for 64 sets
    localparam TAG_BITS    = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS - 2;  // 20 bits

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

    // PLRU state: 3 bits per set (encodes replacement priority)
    // For 4-way: bits [2:0] form a binary tree
    //   bit[2] = L/R from root (0=left half, 1=right half)
    //   bit[1] = L/R within left half (if bit[2]=0)
    //   bit[0] = L/R within right half (if bit[2]=1)
    logic [2:0] plru_array [0:NUM_SETS-1];

    // FSM states
    typedef enum logic [3:0] {
        IDLE,           // Normal operation
        COMPARE,        // Compare tags
        WRITEBACK,      // Writing dirty line to DRAM
        ALLOCATE        // Reading missing line from DRAM
    } state_t;

    state_t state, next_state;
    logic                   dram_busy;
    logic [7:0]             dram_wait_counter;
    logic [2:0]             victim_way;
    logic                   hit;
    logic [2:0]             hit_way;

    // Combinational tag comparison for all ways (unrolled for Icarus compatibility)
    logic hit_way0, hit_way1, hit_way2, hit_way3;
    
    always_comb begin
        hit_way0 = valid_array[index_in][0] && (tag_array[index_in][0] == tag_in);
        hit_way1 = valid_array[index_in][1] && (tag_array[index_in][1] == tag_in);
        hit_way2 = valid_array[index_in][2] && (tag_array[index_in][2] == tag_in);
        hit_way3 = valid_array[index_in][3] && (tag_array[index_in][3] == tag_in);
    end

    always_comb begin
        hit = hit_way0 | hit_way1 | hit_way2 | hit_way3;
        if (hit_way0)
            hit_way = 3'd0;
        else if (hit_way1)
            hit_way = 3'd1;
        else if (hit_way2)
            hit_way = 3'd2;
        else if (hit_way3)
            hit_way = 3'd3;
        else
            hit_way = 3'd0;
    end

    // PLRU replacement logic (simplified pseudo-LRU for 4-way)
    always_comb begin
        // PLRU bit encoding for 4-way:
        // Decode plru_array[index_in] to find replacement victim
        // plru[2:0] = {way3_bit, way2_bit, way1_bit}
        case (plru_array[index_in])
            3'b000: victim_way = 3'd1;  // Replace way 1
            3'b001: victim_way = 3'd0;  // Replace way 0
            3'b010: victim_way = 3'd3;  // Replace way 3
            3'b011: victim_way = 3'd2;  // Replace way 2
            3'b100: victim_way = 3'd1;  // Replace way 1
            3'b101: victim_way = 3'd0;  // Replace way 0
            3'b110: victim_way = 3'd3;  // Replace way 3
            3'b111: victim_way = 3'd2;  // Replace way 2
        endcase
    end

    // Update PLRU on every hit
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int s = 0; s < NUM_SETS; s = s + 1) begin
                plru_array[s] <= 3'b0;
            end
        end else if (hit && state == IDLE) begin
            // Update PLRU: mark accessed way as most-recently-used
            if (hit_way == 3'd0)
                plru_array[index_in] <= {~plru_array[index_in][2], plru_array[index_in][1], 1'b1};
            else if (hit_way == 3'd1)
                plru_array[index_in] <= {~plru_array[index_in][2], plru_array[index_in][1], 1'b0};
            else if (hit_way == 3'd2)
                plru_array[index_in] <= {plru_array[index_in][2], ~plru_array[index_in][1], 1'b1};
            else if (hit_way == 3'd3)
                plru_array[index_in] <= {plru_array[index_in][2], ~plru_array[index_in][1], 1'b0};
            else
                plru_array[index_in] <= plru_array[index_in];
        end else if (state == ALLOCATE && dram_ready) begin
            // Update PLRU after allocation: mark allocated way as most-recently-used
            if (victim_way == 3'd0)
                plru_array[index_in] <= {~plru_array[index_in][2], plru_array[index_in][1], 1'b1};
            else if (victim_way == 3'd1)
                plru_array[index_in] <= {~plru_array[index_in][2], plru_array[index_in][1], 1'b0};
            else if (victim_way == 3'd2)
                plru_array[index_in] <= {plru_array[index_in][2], ~plru_array[index_in][1], 1'b1};
            else if (victim_way == 3'd3)
                plru_array[index_in] <= {plru_array[index_in][2], ~plru_array[index_in][1], 1'b0};
            else
                plru_array[index_in] <= plru_array[index_in];
        end
    end

    // FSM state transitions and DRAM requests
    always_comb begin
        next_state = state;
        dram_read = 1'b0;
        dram_write = 1'b0;
        dram_addr = {tag_in, index_in, offset_in, 2'b00};
        dram_wdata = 32'b0;
        cpu_ready = 1'b0;
        dram_busy = 1'b0;

        case (state)
            IDLE: begin
                if (cpu_read | cpu_write) begin
                    if (hit) begin
                        cpu_ready = 1'b1;  // Hit: return data immediately
                        next_state = IDLE;
                    end else begin
                        // Miss: check if victim line is dirty 
                        
                        if (valid_array[index_in][victim_way] && dirty_array[index_in][victim_way]) begin
                            next_state = WRITEBACK;  // Dirty eviction needed
                        end else begin
                            next_state = ALLOCATE;   // Clean eviction or invalid line
                        end
                    end
                end
            end

            WRITEBACK: begin
                // Writeback old tag from victim_way
                dram_write = 1'b1;
                dram_addr = 32'h00000000;  // Simplified: would use victim's tag
                dram_wdata = 32'b0;  // Simplified: would write full line
                dram_busy = 1'b1;
                if (dram_ready) begin
                    next_state = ALLOCATE;  // After writeback, fetch new line
                end
            end

            ALLOCATE: begin
                dram_read = 1'b1;
                dram_addr = {tag_in, index_in, 6'b0};  // Line-aligned address
                dram_busy = 1'b1;
                if (dram_ready) begin
                    // Fetch from DRAM complete
                    next_state = IDLE;
                    cpu_ready = 1'b1;  // After allocation, data is ready on next cycle
                end
            end

            default: next_state = IDLE;
        endcase
    end

    // Sequential state update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // Cache data read/write logic
    always_comb begin
        if (hit) begin
            // Read from cache on hit
            cpu_rdata = data_array[index_in * NUM_WAYS * (LINE_SIZE/4) + hit_way * (LINE_SIZE/4) + offset_in];
        end else begin
            cpu_rdata = dram_rdata;
        end
    end

    // Write path (hit only, write-through for simplicity in this phase)
    always_ff @(posedge clk) begin
        if (cpu_write && hit && state == IDLE) begin
            data_array[index_in * NUM_WAYS * (LINE_SIZE/4) + hit_way * (LINE_SIZE/4) + offset_in] <= cpu_wdata;
            dirty_array[index_in][hit_way] <= 1'b1;  // Mark as dirty on write
        end

        // On DRAM data arrival (allocate), write full line
        if (state == ALLOCATE && dram_ready) begin
            valid_array[index_in][victim_way] <= 1'b1;
            tag_array[index_in][victim_way] <= tag_in;
            dirty_array[index_in][victim_way] <= 1'b0;  // Fresh line from DRAM
            data_array[index_in * NUM_WAYS * (LINE_SIZE/4) + victim_way * (LINE_SIZE/4) + offset_in] <= dram_rdata;
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
            plru_array[s] <= 3'b0;
        end
        for (int i = 0; i < (NUM_SETS * NUM_WAYS * (LINE_SIZE/4)); i = i + 1) begin
            data_array[i] <= 32'b0;
        end
    end

endmodule
