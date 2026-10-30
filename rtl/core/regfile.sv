`timescale 1ns/1ps

module regfile (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [4:0]  raddr1,
  input  logic [4:0]  raddr2,
  output logic [31:0] rdata1,
  output logic [31:0] rdata2,
  input  logic        we,
  input  logic [4:0]  waddr,
  input  logic [31:0] wdata
);

  logic [31:0] regs [1:31];
  integer i;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 1; i < 32; i = i + 1) begin
        regs[i] <= 32'h0;
      end
    end else begin
      if (we && (waddr != 5'd0)) begin
        regs[waddr] <= wdata;
      end
    end
  end

  always_comb begin
    if (raddr1 == 5'd0) begin
      rdata1 = 32'h0;
    end else if (we && (waddr == raddr1)) begin
      rdata1 = wdata;
    end else begin
      rdata1 = regs[raddr1];
    end

    if (raddr2 == 5'd0) begin
      rdata2 = 32'h0;
    end else if (we && (waddr == raddr2)) begin
      rdata2 = wdata;
    end else begin
      rdata2 = regs[raddr2];
    end
  end

endmodule
