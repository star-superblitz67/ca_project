module cache_l2(
    input logic clk, rst, l1i_req, l1d_req, l1d_we,
    input logic [31:0] l1i_addr, l1d_addr,
    input logic [127:0] l1d_wdata,
    output logic [127:0] l1i_rdata, l1d_rdata,
    output logic l1i_ready, l1d_ready, mem_req, mem_we,
    output logic [31:0] mem_addr,
    output logic [127:0] mem_wdata,
    input logic [127:0] mem_rdata,
    input logic mem_ready
);
    logic d_turn;
    always_ff @(posedge clk) if(rst) d_turn <= 0; else if(l1i_ready || l1d_ready) d_turn <= !d_turn;
    assign mem_req = l1d_req || l1i_req;
    assign mem_we = l1d_req && l1d_we;
    assign mem_addr = (l1d_req) ? l1d_addr : l1i_addr;
    assign mem_wdata = l1d_wdata;
    assign l1d_ready = l1d_req && mem_ready;
    assign l1i_ready = !l1d_req && l1i_req && mem_ready;
    assign {l1i_rdata, l1d_rdata} = {mem_rdata, mem_rdata};
endmodule
