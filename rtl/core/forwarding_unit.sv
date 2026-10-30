`timescale 1ns/1ps

import riscv_pkg::*;

module forwarding_unit (
  input  logic [4:0]  rs1_id_ex,
  input  logic [4:0]  rs2_id_ex,
  input  logic [4:0]  rd_ex_mem,
  input  logic        reg_write_ex_mem,
  input  logic [4:0]  rd_mem_wb,
  input  logic        reg_write_mem_wb,
  output logic [1:0]  fwd_a,
  output logic [1:0]  fwd_b
);

  always_comb begin
    if (reg_write_ex_mem && (rd_ex_mem != 5'd0) && (rd_ex_mem == rs1_id_ex)) begin
      fwd_a = FWD_EX_MEM;
    end else if (reg_write_mem_wb && (rd_mem_wb != 5'd0) && (rd_mem_wb == rs1_id_ex)) begin
      fwd_a = FWD_MEM_WB;
    end else begin
      fwd_a = FWD_NONE;
    end

    if (reg_write_ex_mem && (rd_ex_mem != 5'd0) && (rd_ex_mem == rs2_id_ex)) begin
      fwd_b = FWD_EX_MEM;
    end else if (reg_write_mem_wb && (rd_mem_wb != 5'd0) && (rd_mem_wb == rs2_id_ex)) begin
      fwd_b = FWD_MEM_WB;
    end else begin
      fwd_b = FWD_NONE;
    end
  end

endmodule
