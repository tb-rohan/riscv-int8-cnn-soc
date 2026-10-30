`timescale 1ns/1ps

module uart_lite (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        req,
  input  logic        we,
  input  logic [31:0] addr,
  input  logic [31:0] wdata,
  output logic [31:0] rdata,
  output logic        tx_valid,
  output logic [7:0]  tx_char
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_valid <= 1'b0;
      tx_char  <= 8'h0;
    end else begin
      tx_valid <= 1'b0;
      if (req && we && (addr[3:2] == 2'b00)) begin
        tx_valid <= 1'b1;
        tx_char  <= wdata[7:0];
`ifndef SYNTHESIS
        $write("%c", wdata[7:0]);
        $fflush();
`endif
      end
    end
  end

  always_comb begin
    case (addr[3:2])
      2'b00:   rdata = {24'h0, tx_char};
      2'b01:   rdata = 32'h00000001;
      default: rdata = 32'h0;
    endcase
  end

endmodule
