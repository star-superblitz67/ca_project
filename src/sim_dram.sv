`timescale 1ns / 1ps

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

localparam IDLE    = 2'b00;
localparam WAIT    = 2'b01;
localparam RESPOND = 2'b10;

localparam LATENCY = 5;

logic [1:0] state;
logic [1:0] next_state;

logic [127:0] memory [0:4095];

logic [3:0] counter;
logic [31:0] active_addr;

initial begin

    memory[0] = 128'h00612022_00221820_2002000A_20010005;
    memory[1] = 128'hAC060010_00A13025_00642824_00612022;
    memory[2] = 128'h20090063_11060001_00E14020_8C070010;
    memory[3] = 128'h00000000_00000000_340A000F_00000000;

end

always @(posedge clk or posedge rst) begin

    if(rst) begin

        state <= IDLE;
        counter <= 0;
        active_addr <= 0;

    end
    else begin

        state <= next_state;

        if(state == WAIT)
            counter <= counter + 1;
        else
            counter <= 0;

        if(state == IDLE && req)
            active_addr <= addr;

        if(state == RESPOND && we)
            memory[active_addr[13:4]] <= wdata;

    end

end

always @(*) begin

    next_state = state;

    ready = 0;
    rdata = 0;

    case(state)

        IDLE: begin

            if(req)
                next_state = WAIT;

        end

        WAIT: begin

            if(counter >= LATENCY-1)
                next_state = RESPOND;

        end

        RESPOND: begin

            ready = 1;

            if(!we)
                rdata = memory[active_addr[13:4]];

            next_state = IDLE;

        end

        default:
            next_state = IDLE;

    endcase

end

endmodule