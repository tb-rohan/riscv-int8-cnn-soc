`timescale 1ns/1ps

import riscv_pkg::*;

module imm_gen (
  input  logic [31:0] inst,
  output logic [31:0] imm_i,
  output logic [31:0] imm_s,
  output logic [31:0] imm_b,
  output logic [31:0] imm_u,
  output logic [31:0] imm_j
);

  assign imm_i = {{20{inst[31]}}, inst[31:20]};
  assign imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
  assign imm_b = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
  assign imm_u = {inst[31:12], 12'h0};
  assign imm_j = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};

endmodule
