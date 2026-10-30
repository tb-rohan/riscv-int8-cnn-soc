`timescale 1ns/1ps

import riscv_pkg::*;

module pipe_reg_if_id (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        stall,
  input  logic        flush,
  input  logic [31:0] if_pc,
  input  logic [31:0] if_pc_plus4,
  input  logic [31:0] if_inst,
  output logic [31:0] id_pc,
  output logic [31:0] id_pc_plus4,
  output logic [31:0] id_inst,
  output logic        id_valid
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      id_pc        <= 32'h0;
      id_pc_plus4  <= 32'h0;
      id_inst      <= 32'h00000013;
      id_valid     <= 1'b0;
    end else if (flush) begin
      id_pc        <= 32'h0;
      id_pc_plus4  <= 32'h0;
      id_inst      <= 32'h00000013;
      id_valid     <= 1'b0;
    end else if (!stall) begin
      id_pc        <= if_pc;
      id_pc_plus4  <= if_pc_plus4;
      id_inst      <= if_inst;
      id_valid     <= 1'b1;
    end
  end

endmodule
