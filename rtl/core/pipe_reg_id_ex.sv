`timescale 1ns/1ps

import riscv_pkg::*;

module pipe_reg_id_ex (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        stall,
  input  logic        flush,
  input  logic        id_valid,
  input  logic [31:0] id_pc,
  input  logic [31:0] id_pc_plus4,
  input  logic [31:0] id_rdata1,
  input  logic [31:0] id_rdata2,
  input  logic [31:0] id_imm,
  input  logic [4:0]  id_rs1,
  input  logic [4:0]  id_rs2,
  input  logic [4:0]  id_rd,
  input  logic        id_reg_write,
  input  logic        id_mem_read,
  input  logic        id_mem_write,
  input  logic [2:0]  id_mem_size,
  input  logic        id_branch,
  input  logic [2:0]  id_branch_type,
  input  logic        id_jump,
  input  logic        id_jalr,
  input  logic        id_alu_src_a,
  input  logic        id_alu_src_b,
  input  logic [3:0]  id_alu_op,
  input  logic [1:0]  id_wb_src,
  output logic        ex_valid,
  output logic [31:0] ex_pc,
  output logic [31:0] ex_pc_plus4,
  output logic [31:0] ex_rdata1,
  output logic [31:0] ex_rdata2,
  output logic [31:0] ex_imm,
  output logic [4:0]  ex_rs1,
  output logic [4:0]  ex_rs2,
  output logic [4:0]  ex_rd,
  output logic        ex_reg_write,
  output logic        ex_mem_read,
  output logic        ex_mem_write,
  output logic [2:0]  ex_mem_size,
  output logic        ex_branch,
  output logic [2:0]  ex_branch_type,
  output logic        ex_jump,
  output logic        ex_jalr,
  output logic        ex_alu_src_a,
  output logic        ex_alu_src_b,
  output logic [3:0]  ex_alu_op,
  output logic [1:0]  ex_wb_src
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ex_valid       <= 1'b0;
      ex_pc          <= 32'h0;
      ex_pc_plus4    <= 32'h0;
      ex_rdata1      <= 32'h0;
      ex_rdata2      <= 32'h0;
      ex_imm         <= 32'h0;
      ex_rs1         <= 5'd0;
      ex_rs2         <= 5'd0;
      ex_rd          <= 5'd0;
      ex_reg_write   <= 1'b0;
      ex_mem_read    <= 1'b0;
      ex_mem_write   <= 1'b0;
      ex_mem_size    <= 3'd0;
      ex_branch      <= 1'b0;
      ex_branch_type <= 3'd0;
      ex_jump        <= 1'b0;
      ex_jalr        <= 1'b0;
      ex_alu_src_a   <= 1'b0;
      ex_alu_src_b   <= 1'b0;
      ex_alu_op      <= 4'd0;
      ex_wb_src      <= 2'd0;
    end else if (flush) begin
      ex_valid       <= 1'b0;
      ex_pc          <= 32'h0;
      ex_pc_plus4    <= 32'h0;
      ex_rdata1      <= 32'h0;
      ex_rdata2      <= 32'h0;
      ex_imm         <= 32'h0;
      ex_rs1         <= 5'd0;
      ex_rs2         <= 5'd0;
      ex_rd          <= 5'd0;
      ex_reg_write   <= 1'b0;
      ex_mem_read    <= 1'b0;
      ex_mem_write   <= 1'b0;
      ex_mem_size    <= 3'd0;
      ex_branch      <= 1'b0;
      ex_branch_type <= 3'd0;
      ex_jump        <= 1'b0;
      ex_jalr        <= 1'b0;
      ex_alu_src_a   <= 1'b0;
      ex_alu_src_b   <= 1'b0;
      ex_alu_op      <= 4'd0;
      ex_wb_src      <= 2'd0;
    end else if (!stall) begin
      ex_valid       <= id_valid;
      ex_pc          <= id_pc;
      ex_pc_plus4    <= id_pc_plus4;
      ex_rdata1      <= id_rdata1;
      ex_rdata2      <= id_rdata2;
      ex_imm         <= id_imm;
      ex_rs1         <= id_rs1;
      ex_rs2         <= id_rs2;
      ex_rd          <= id_rd;
      ex_reg_write   <= id_reg_write;
      ex_mem_read    <= id_mem_read;
      ex_mem_write   <= id_mem_write;
      ex_mem_size    <= id_mem_size;
      ex_branch      <= id_branch;
      ex_branch_type <= id_branch_type;
      ex_jump        <= id_jump;
      ex_jalr        <= id_jalr;
      ex_alu_src_a   <= id_alu_src_a;
      ex_alu_src_b   <= id_alu_src_b;
      ex_alu_op      <= id_alu_op;
      ex_wb_src      <= id_wb_src;
    end
  end

endmodule
