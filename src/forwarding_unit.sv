`timescale 1ns / 1ps

module forwarding_unit (
    input  logic [4:0] rs_EX,
    input  logic [4:0] rt_EX,
    input  logic [4:0] rd_MEM,
    input  logic       reg_write_MEM,
    input  logic [4:0] rd_WB,
    input  logic       reg_write_WB,

    output logic [1:0] forward_A,
    output logic [1:0] forward_B
);

    always @* begin
        if (reg_write_MEM && (rd_MEM != 0) && (rd_MEM == rs_EX)) begin
            forward_A = 2'b10;
        end else if (reg_write_WB && (rd_WB != 0) && (rd_WB == rs_EX)) begin
            forward_A = 2'b01;
        end else begin
            forward_A = 2'b00;
        end
    end

    always @* begin
        if (reg_write_MEM && (rd_MEM != 0) && (rd_MEM == rt_EX)) begin
            forward_B = 2'b10;
        end else if (reg_write_WB && (rd_WB != 0) && (rd_WB == rt_EX)) begin
            forward_B = 2'b01;
        end else begin
            forward_B = 2'b00;
        end
    end

endmodule
