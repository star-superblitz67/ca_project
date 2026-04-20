module hazard_unit (
    input  logic        id_ex_mem_read,
    input  logic [4:0]  id_ex_rt,
    input  logic [4:0]  if_id_rs,
    input  logic [4:0]  if_id_rt,
    input  logic        ex_mem_mem_write,
    input  logic [4:0]  id_ex_rs,
    input  logic [4:0]  id_ex_rt_next,
    input  logic        cache_stall,
    output logic        pc_write,
    output logic        if_id_write,
    output logic        id_ex_flush
);

    logic load_use_hazard;
    logic branch_hazard;

    assign load_use_hazard = id_ex_mem_read && (
        (id_ex_rt == if_id_rs) || (id_ex_rt == if_id_rt)
    );

    assign branch_hazard = 1'b0;

    assign pc_write = ~(load_use_hazard || cache_stall);
    assign if_id_write = ~(load_use_hazard || cache_stall);
    assign id_ex_flush = load_use_hazard || cache_stall;

endmodule
