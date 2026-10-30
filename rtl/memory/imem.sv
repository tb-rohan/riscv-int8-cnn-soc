`timescale 1ns/1ps

module imem #(
  parameter int ADDR_WIDTH = 14,
  parameter     INIT_FILE  = ""
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [31:0] addr,
  output logic [31:0] rdata,
  input  logic        we,
  input  logic [31:0] waddr,
  input  logic [31:0] wdata,
  input  logic [3:0]  wstrb
);

  localparam int NUM_WORDS = 1 << (ADDR_WIDTH - 2);
  logic [31:0] mem [0:NUM_WORDS-1];

  wire [ADDR_WIDTH-3:0] r_word_addr;
  assign r_word_addr = addr[ADDR_WIDTH-1:2];

  wire [ADDR_WIDTH-3:0] w_word_addr;
  assign w_word_addr = waddr[ADDR_WIDTH-1:2];

  initial begin
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end
  end

  always_ff @(posedge clk) begin
    if (we) begin
      if (wstrb[0]) mem[w_word_addr][7:0]   <= wdata[7:0];
      if (wstrb[1]) mem[w_word_addr][15:8]  <= wdata[15:8];
      if (wstrb[2]) mem[w_word_addr][23:16] <= wdata[23:16];
      if (wstrb[3]) mem[w_word_addr][31:24] <= wdata[31:24];
    end
  end

  assign rdata = (r_word_addr < NUM_WORDS) ? mem[r_word_addr] : 32'h00000013;

endmodule
