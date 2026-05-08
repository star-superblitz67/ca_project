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

    // Logic to determine where ALU input A comes from.
    // It prioritizes the most recent data (from the MEM stage) over slightly older data (from the WB stage).
    always_comb begin
        if (reg_write_MEM && (rd_MEM != 0) && (rd_MEM == rs_EX)) begin
            forward_A = 2'b10; // Grab data from the MEM stage (it's newer)
        end else if (reg_write_WB && (rd_WB != 0) && (rd_WB == rs_EX)) begin
            forward_A = 2'b01; // Grab data from the WB stage
        end else begin
            forward_A = 2'b00; // Just use the normal register file value
        end
    end

    // Logic to determine where ALU input B comes from. Similar logic as above.
    always_comb begin
        if (reg_write_MEM && (rd_MEM != 0) && (rd_MEM == rt_EX)) begin
            forward_B = 2'b10; // Grab data from the MEM stage
        end else if (reg_write_WB && (rd_WB != 0) && (rd_WB == rt_EX)) begin
            forward_B = 2'b01; // Grab data from the WB stage
        end else begin
            forward_B = 2'b00; // Normal register file value
        end
    end

endmodule
