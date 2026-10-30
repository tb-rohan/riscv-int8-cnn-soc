`timescale 1ns/1ps

import riscv_pkg::*;

module branch_unit (
  input  logic        branch,
  input  logic [2:0]  branch_type,
  input  logic        jump,
  input  logic        jalr,
  input  logic [31:0] pc,
  input  logic [31:0] imm,
  input  logic [31:0] op_a,
  input  logic [31:0] op_b,
  output logic        take_branch,
  output logic [31:0] target_pc
);

  logic signed [31:0] signed_a;
  logic signed [31:0] signed_b;
  assign signed_a = op_a;
  assign signed_b = op_b;

  logic cond_met;

  always_comb begin
    case (branch_type)
      BR_BEQ:  cond_met = (op_a == op_b);
      BR_BNE:  cond_met = (op_a != op_b);
      BR_BLT:  cond_met = (signed_a < signed_b);
      BR_BGE:  cond_met = (signed_a >= signed_b);
      BR_BLTU: cond_met = (op_a < op_b);
      BR_BGEU: cond_met = (op_a >= op_b);
      default: cond_met = 1'b0;
    endcase
  end

  assign take_branch = jump | (branch & cond_met);

  always_comb begin
    if (jalr) begin
      target_pc = (op_a + imm) & ~32'd1;
    end else begin
      target_pc = pc + imm;
    end
  end

endmodule
