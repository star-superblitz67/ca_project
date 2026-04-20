module forwarding_unit (
    input  logic [31:0] ex_mem_rd,
    input  logic [31:0] mem_wb_rd,
    input  logic        ex_mem_reg_write,
    input  logic        mem_wb_reg_write,
    input  logic [4:0]  id_ex_rs,
    input  logic [4:0]  id_ex_rt,
    input  logic [4:0]  ex_mem_rd_addr,
    input  logic [4:0]  mem_wb_rd_addr,
    input  logic        id_ex_mem_read,
    output logic [1:0]  forward_a,
    output logic [1:0]  forward_b,
    output logic        stall_forward
);

    logic ex_forward_a, mem_forward_a;
    logic ex_forward_b, mem_forward_b;

    always_comb begin
        ex_forward_a = ex_mem_reg_write && (ex_mem_rd_addr != 5'd0) && (ex_mem_rd_addr == id_ex_rs);
        mem_forward_a = mem_wb_reg_write && (mem_wb_rd_addr != 5'd0) && (mem_wb_rd_addr == id_ex_rs) && !ex_forward_a;
        
        ex_forward_b = ex_mem_reg_write && (ex_mem_rd_addr != 5'd0) && (ex_mem_rd_addr == id_ex_rt);
        mem_forward_b = mem_wb_reg_write && (mem_wb_rd_addr != 5'd0) && (mem_wb_rd_addr == id_ex_rt) && !ex_forward_b;
    end

    always_comb begin
        if (ex_forward_a)
            forward_a = 2'b10;
        else if (mem_forward_a)
            forward_a = 2'b01;
        else
            forward_a = 2'b00;

        if (ex_forward_b)
            forward_b = 2'b10;
        else if (mem_forward_b)
            forward_b = 2'b01;
        else
            forward_b = 2'b00;
    end

    assign stall_forward = 1'b0;

endmodule
