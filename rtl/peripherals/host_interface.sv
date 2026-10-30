`timescale 1ns/1ps

module host_interface (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        req,
  input  logic        we,
  input  logic [31:0] addr,
  input  logic [31:0] wdata,
  output logic [31:0] rdata,

  input  logic        ext_req,
  input  logic [7:0]  ext_cmd,
  input  logic [31:0] ext_op_a,
  input  logic [31:0] ext_op_b,
  output logic        ext_done,
  output logic [31:0] ext_result,
  output logic [31:0] ext_result_hi,
  output logic [31:0] ext_status
);

  logic [31:0] reg_ctrl;
  logic [31:0] reg_op_a;
  logic [31:0] reg_op_b;
  logic [31:0] reg_result;
  logic [31:0] reg_result_hi;
  logic [31:0] reg_status;

  assign ext_done      = reg_ctrl[1];
  assign ext_result    = reg_result;
  assign ext_result_hi = reg_result_hi;
  assign ext_status    = reg_status;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      reg_ctrl      <= 32'h0;
      reg_op_a      <= 32'h0;
      reg_op_b      <= 32'h0;
      reg_result    <= 32'h0;
      reg_result_hi <= 32'h0;
      reg_status    <= 32'h0;
    end else begin
      if (ext_req && !reg_ctrl[0]) begin
        reg_ctrl      <= {16'h0, ext_cmd, 7'h0, 1'b1};
        reg_op_a      <= ext_op_a;
        reg_op_b      <= ext_op_b;
        reg_result    <= 32'h0;
        reg_result_hi <= 32'h0;
        reg_status    <= 32'h0;
      end else if (req && we) begin
        case (addr[4:2])
          3'b000: reg_ctrl      <= wdata;
          3'b001: reg_op_a      <= wdata;
          3'b010: reg_op_b      <= wdata;
          3'b011: reg_result    <= wdata;
          3'b100: reg_result_hi <= wdata;
          3'b101: reg_status    <= wdata;
          default: ;
        endcase
      end
    end
  end

  always_comb begin
    case (addr[4:2])
      3'b000:  rdata = reg_ctrl;
      3'b001:  rdata = reg_op_a;
      3'b010:  rdata = reg_op_b;
      3'b011:  rdata = reg_result;
      3'b100:  rdata = reg_result_hi;
      3'b101:  rdata = reg_status;
      default: rdata = 32'h0;
    endcase
  end

endmodule
