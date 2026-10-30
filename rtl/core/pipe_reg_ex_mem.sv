`timescale 1ns/1ps

import riscv_pkg::*;

module pipe_reg_ex_mem (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        stall,
  input  logic        flush,
  input  logic        ex_valid,
  input  logic [31:0] ex_pc,
  input  logic [31:0] ex_pc_plus4,
  input  logic [31:0] ex_alu_out,
  input  logic [31:0] ex_wdata,
  input  logic [31:0] ex_imm,
  input  logic [4:0]  ex_rd,
  input  logic        ex_reg_write,
  input  logic        ex_mem_read,
  input  logic        ex_mem_write,
  input  logic [2:0]  ex_mem_size,
  input  logic [1:0]  ex_wb_src,
  output logic        mem_valid,
  output logic [31:0] mem_pc,
  output logic [31:0] mem_pc_plus4,
  output logic [31:0] mem_alu_out,
  output logic [31:0] mem_wdata,
  output logic [31:0] mem_imm,
  output logic [4:0]  mem_rd,
  output logic        mem_reg_write,
  output logic        mem_mem_read,
  output logic        mem_mem_write,
  output logic [2:0]  mem_mem_size,
  output logic [1:0]  mem_wb_src
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mem_valid     <= 1'b0;
      mem_pc        <= 32'h0;
      mem_pc_plus4  <= 32'h0;
      mem_alu_out   <= 32'h0;
      mem_wdata     <= 32'h0;
      mem_imm       <= 32'h0;
      mem_rd        <= 5'd0;
      mem_reg_write <= 1'b0;
      mem_mem_read  <= 1'b0;
      mem_mem_write <= 1'b0;
      mem_mem_size  <= 3'd0;
      mem_wb_src    <= 2'd0;
    end else if (flush) begin
      mem_valid     <= 1'b0;
      mem_pc        <= 32'h0;
      mem_pc_plus4  <= 32'h0;
      mem_alu_out   <= 32'h0;
      mem_wdata     <= 32'h0;
      mem_imm       <= 32'h0;
      mem_rd        <= 5'd0;
      mem_reg_write <= 1'b0;
      mem_mem_read  <= 1'b0;
      mem_mem_write <= 1'b0;
      mem_mem_size  <= 3'd0;
      mem_wb_src    <= 2'd0;
    end else if (!stall) begin
      mem_valid     <= ex_valid;
      mem_pc        <= ex_pc;
      mem_pc_plus4  <= ex_pc_plus4;
      mem_alu_out   <= ex_alu_out;
      mem_wdata     <= ex_wdata;
      mem_imm       <= ex_imm;
      mem_rd        <= ex_rd;
      mem_reg_write <= ex_reg_write;
      mem_mem_read  <= ex_mem_read;
      mem_mem_write <= ex_mem_write;
      mem_mem_size  <= ex_mem_size;
      mem_wb_src    <= ex_wb_src;
    end
  end

endmodule
