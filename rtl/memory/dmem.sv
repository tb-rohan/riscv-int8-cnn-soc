`timescale 1ns/1ps

module dmem #(
  parameter int ADDR_WIDTH = 14,
  parameter     INIT_FILE  = ""
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        req,
  input  logic        we,
  input  logic [31:0] addr,
  input  logic [31:0] wdata,
  input  logic [3:0]  wstrb,
  output logic [31:0] rdata
);

  ram_sync #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .INIT_FILE(INIT_FILE)
  ) u_ram (
    .clk  (clk),
    .rst_n(rst_n),
    .req  (req),
    .we   (we),
    .addr (addr),
    .wdata(wdata),
    .wstrb(wstrb),
    .rdata(rdata)
  );

endmodule
