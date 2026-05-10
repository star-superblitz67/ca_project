`timescale 1ns/1ps

/**
 * L1 Data Cache (Fixed)
 * Features:
 * - 4 Lines, Direct Mapped, 128-bit block size.
 * - Write-Through Policy.
 * - Robust Ready Logic to break pipeline stalls during memory ops.
 */
module cache_l1d(
    input logic clk,
    input logic rst,
    input logic cpu_req,
    input logic cpu_we,
    input logic [31:0] cpu_addr,
    input logic [31:0] cpu_wdata,
    output logic [31:0] cpu_rdata,
    output logic cpu_ready,

    output logic l2_req,
    output logic l2_we,
    output logic [31:0] l2_addr,
    output logic [127:0] l2_wdata,
    input logic [127:0] l2_rdata,
    input logic l2_ready
);

    logic valid [0:3];
    logic [25:0] tags [0:3];
    logic [127:0] data [0:3];

    logic [1:0] index = cpu_addr[5:4];
    logic [25:0] tag = cpu_addr[31:6];
    logic [1:0] word_offset = cpu_addr[3:2];

    logic hit;
    assign hit = valid[index] && (tags[index] == tag);

    assign cpu_rdata = (word_offset == 2'b00) ? data[index][31:0] :
                       (word_offset == 2'b01) ? data[index][63:32] :
                       (word_offset == 2'b10) ? data[index][95:64] :
                                                data[index][127:96];

    typedef enum logic [1:0] {IDLE, REFILL, WRITE_THROUGH} state_t;
    state_t state, next_state;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            for(int i=0; i<4; i++) valid[i] <= 0;
        end else begin
            state <= next_state;
            if (state == REFILL && l2_ready) begin
                valid[index] <= 1;
                tags[index] <= tag;
                data[index] <= l2_rdata;
            end else if (state == WRITE_THROUGH && l2_ready) begin
                if (hit) begin
                    // Update cache as well (Write-through)
                    case(word_offset)
                        2'b00: data[index][31:0]   <= cpu_wdata;
                        2'b01: data[index][63:32]  <= cpu_wdata;
                        2'b10: data[index][95:64]  <= cpu_wdata;
                        2'b11: data[index][127:96] <= cpu_wdata;
                    endcase
                end
            end
        end
    end

    always_comb begin
        next_state = state;
        l2_req = 0;
        l2_we = 0;
        l2_addr = {tag, index, 4'b0000};
        l2_wdata = {4{cpu_wdata}}; // Broadcaster

        // CRITICAL: Assert cpu_ready when the cycle finishes to let pipeline advance
        cpu_ready = (state == IDLE && hit && !cpu_we) || 
                    (state == WRITE_THROUGH && l2_ready) ||
                    (state == REFILL && l2_ready);

        case(state)
            IDLE: begin
                if (cpu_req) begin
                    if (cpu_we) begin
                        l2_req = 1;
                        l2_we = 1;
                        l2_addr = cpu_addr;
                        next_state = WRITE_THROUGH;
                    end else if (!hit) begin
                        l2_req = 1;
                        next_state = REFILL;
                    end
                end
            end
            REFILL: begin
                l2_req = 1;
                if (l2_ready) next_state = IDLE;
            end
            WRITE_THROUGH: begin
                l2_req = 1;
                l2_we = 1;
                l2_addr = cpu_addr;
                if (l2_ready) next_state = IDLE;
            end
        endcase
    end

endmodule
