`timescale 1ns/1ps

import riscv_pkg::*;

module alu (
  input  logic [3:0]  alu_op,
  input  logic [31:0] alu_in_a,
  input  logic [31:0] alu_in_b,
  output logic [31:0] alu_out,
  output logic        alu_zero
);

  logic [4:0] shamt;
  assign shamt = alu_in_b[4:0];

  logic signed [31:0] signed_a;
  logic signed [31:0] signed_b;
  assign signed_a = alu_in_a;
  assign signed_b = alu_in_b;

  always_comb begin
    case (alu_op)
      ALU_ADD:  alu_out = alu_in_a + alu_in_b;
      ALU_SUB:  alu_out = alu_in_a - alu_in_b;
      ALU_SLL:  alu_out = alu_in_a << shamt;
      ALU_SLT:  alu_out = (signed_a < signed_b) ? 32'd1 : 32'd0;
      ALU_SLTU: alu_out = (alu_in_a < alu_in_b) ? 32'd1 : 32'd0;
      ALU_XOR:  alu_out = alu_in_a ^ alu_in_b;
      ALU_SRL:  alu_out = alu_in_a >> shamt;
      ALU_SRA:  alu_out = signed_a >>> shamt;
      ALU_OR:   alu_out = alu_in_a | alu_in_b;
      ALU_AND:  alu_out = alu_in_a & alu_in_b;
      ALU_COPY: alu_out = alu_in_b;
      default:  alu_out = 32'h0;
    endcase
  end

  assign alu_zero = (alu_out == 32'h0);

endmodule
