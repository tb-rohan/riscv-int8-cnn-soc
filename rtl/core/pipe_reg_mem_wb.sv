`timescale 1ns/1ps

import riscv_pkg::*;

module pipe_reg_mem_wb (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        stall,
  input  logic        flush,
  input  logic        mem_valid,
  input  logic [31:0] mem_pc,
  input  logic [31:0] mem_pc_plus4,
  input  logic [31:0] mem_alu_out,
  input  logic [31:0] mem_rdata,
  input  logic [31:0] mem_imm,
  input  logic [4:0]  mem_rd,
  input  logic        mem_reg_write,
  input  logic [1:0]  mem_wb_src,
  output logic        wb_valid,
  output logic [31:0] wb_pc,
  output logic [31:0] wb_pc_plus4,
  output logic [31:0] wb_alu_out,
  output logic [31:0] wb_rdata,
  output logic [31:0] wb_imm,
  output logic [4:0]  wb_rd,
  output logic        wb_reg_write,
  output logic [1:0]  wb_wb_src
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wb_valid     <= 1'b0;
      wb_pc        <= 32'h0;
      wb_pc_plus4  <= 32'h0;
      wb_alu_out   <= 32'h0;
      wb_rdata     <= 32'h0;
      wb_imm       <= 32'h0;
      wb_rd        <= 5'd0;
      wb_reg_write <= 1'b0;
      wb_wb_src    <= 2'd0;
    end else if (flush) begin
      wb_valid     <= 1'b0;
      wb_pc        <= 32'h0;
      wb_pc_plus4  <= 32'h0;
      wb_alu_out   <= 32'h0;
      wb_rdata     <= 32'h0;
      wb_imm       <= 32'h0;
      wb_rd        <= 5'd0;
      wb_reg_write <= 1'b0;
      wb_wb_src    <= 2'd0;
    end else if (!stall) begin
      wb_valid     <= mem_valid;
      wb_pc        <= mem_pc;
      wb_pc_plus4  <= mem_pc_plus4;
      wb_alu_out   <= mem_alu_out;
      wb_rdata     <= mem_rdata;
      wb_imm       <= mem_imm;
      wb_rd        <= mem_rd;
      wb_reg_write <= mem_reg_write;
      wb_wb_src    <= mem_wb_src;
    end
  end

endmodule
