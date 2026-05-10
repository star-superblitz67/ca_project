`timescale 1ns/1ps

/**
 * L1 Instruction Cache (Fixed)
 * Features:
 * - 4 Lines, Direct Mapped, 128-bit block size.
 * - Robust Ready Logic for single-cycle pipeline recovery.
 */
module cache_l1i(
    input logic clk,
    input logic rst,
    input logic cpu_req,
    input logic [31:0] cpu_addr,
    output logic [31:0] cpu_rdata,
    output logic cpu_ready,

    output logic l2_req,
    output logic [31:0] l2_addr,
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

    typedef enum logic {IDLE, REFILL} state_t;
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
            end
        end
    end

    always_comb begin
        next_state = state;
        l2_req = 0;
        l2_addr = {tag, index, 4'b0000};
        
        // Assert ready on hit or when refill cycle finishes
        cpu_ready = (state == IDLE && hit) || (state == REFILL && l2_ready);

        case(state)
            IDLE: begin
                if (cpu_req && !hit) begin
                    l2_req = 1;
                    next_state = REFILL;
                end
            end
            REFILL: begin
                l2_req = 1;
                if (l2_ready) next_state = IDLE;
            end
        endcase
    end

endmodule
