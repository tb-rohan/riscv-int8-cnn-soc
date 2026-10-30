`timescale 1ns/1ps

import riscv_pkg::*;

module hazard_unit (
  input  logic [4:0] rs1_if_id,
  input  logic [4:0] rs2_if_id,
  input  logic       rs1_valid_if_id,
  input  logic       rs2_valid_if_id,
  input  logic [4:0] rd_id_ex,
  input  logic       mem_read_id_ex,
  input  logic       take_branch_ex,
  input  logic       dmem_stall,
  output logic       stall_pc,
  output logic       stall_if_id,
  output logic       stall_id_ex,
  output logic       stall_ex_mem,
  output logic       stall_mem_wb,
  output logic       flush_if_id,
  output logic       flush_id_ex,
  output logic       flush_ex_mem,
  output logic       flush_mem_wb,
  output logic       load_use_hazard_tick,
  output logic       branch_flush_tick,
  output logic       bus_stall_tick
);

  logic load_use_hazard;

  assign load_use_hazard = mem_read_id_ex && (rd_id_ex != 5'd0) &&
                           ((rs1_valid_if_id && (rd_id_ex == rs1_if_id)) ||
                            (rs2_valid_if_id && (rd_id_ex == rs2_if_id)));

  assign load_use_hazard_tick = load_use_hazard;
  assign branch_flush_tick    = take_branch_ex;
  assign bus_stall_tick       = dmem_stall;

  always_comb begin
    stall_pc     = 1'b0;
    stall_if_id  = 1'b0;
    stall_id_ex  = 1'b0;
    stall_ex_mem = 1'b0;
    stall_mem_wb = 1'b0;
    flush_if_id  = 1'b0;
    flush_id_ex  = 1'b0;
    flush_ex_mem = 1'b0;
    flush_mem_wb = 1'b0;

    if (dmem_stall) begin
      stall_pc     = 1'b1;
      stall_if_id  = 1'b1;
      stall_id_ex  = 1'b1;
      stall_ex_mem = 1'b1;
      stall_mem_wb = 1'b0;
      flush_mem_wb = 1'b1;
    end else if (take_branch_ex) begin
      flush_if_id  = 1'b1;
      flush_id_ex  = 1'b1;
    end else if (load_use_hazard) begin
      stall_pc     = 1'b1;
      stall_if_id  = 1'b1;
      flush_id_ex  = 1'b1;
    end
  end

endmodule
