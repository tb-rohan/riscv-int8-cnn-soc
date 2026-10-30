`timescale 1ns/1ps

import riscv_pkg::*;

module rv32i_core (
  input  logic        clk,
  input  logic        rst_n,

  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,

  output logic        dmem_req,
  output logic        dmem_we,
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wdata,
  output logic [3:0]  dmem_wstrb,
  input  logic [31:0] dmem_rdata,
  input  logic        dmem_stall,

  output logic [31:0] debug_wb_pc,
  output logic [4:0]  debug_wb_rd,
  output logic [31:0] debug_wb_data,
  output logic        debug_wb_valid,

  output logic        perf_instret_tick,
  output logic        perf_load_use_tick,
  output logic        perf_branch_flush_tick,
  output logic        perf_bus_stall_tick
);

  logic stall_pc;
  logic stall_if_id;
  logic stall_id_ex;
  logic stall_ex_mem;
  logic stall_mem_wb;
  logic flush_if_id;
  logic flush_id_ex;
  logic flush_ex_mem;
  logic flush_mem_wb;

  logic [31:0] pc_q;
  logic [31:0] next_pc;
  logic [31:0] if_pc_plus4;

  assign if_pc_plus4 = pc_q + 32'd4;
  assign imem_addr   = pc_q;

  logic        take_branch_ex;
  logic [31:0] target_pc_ex;

  always_comb begin
    if (take_branch_ex) begin
      next_pc = target_pc_ex;
    end else if (stall_pc) begin
      next_pc = pc_q;
    end else begin
      next_pc = if_pc_plus4;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_q <= 32'h0;
    end else begin
      pc_q <= next_pc;
    end
  end

  logic [31:0] id_pc;
  logic [31:0] id_pc_plus4;
  logic [31:0] id_inst;
  logic        id_valid;

  pipe_reg_if_id u_pipe_if_id (
    .clk        (clk),
    .rst_n      (rst_n),
    .stall      (stall_if_id),
    .flush      (flush_if_id),
    .if_pc      (pc_q),
    .if_pc_plus4(if_pc_plus4),
    .if_inst    (imem_rdata),
    .id_pc      (id_pc),
    .id_pc_plus4(id_pc_plus4),
    .id_inst    (id_inst),
    .id_valid   (id_valid)
  );

  logic [4:0]  id_rs1;
  logic [4:0]  id_rs2;
  logic [4:0]  id_rd;
  logic [31:0] id_imm;
  logic        id_reg_write;
  logic        id_mem_read;
  logic        id_mem_write;
  logic [2:0]  id_mem_size;
  logic        id_branch;
  logic [2:0]  id_branch_type;
  logic        id_jump;
  logic        id_jalr;
  logic        id_alu_src_a;
  logic        id_alu_src_b;
  logic [3:0]  id_alu_op;
  logic [1:0]  id_wb_src;
  logic        id_is_ecall;
  logic        id_is_ebreak;
  logic        id_is_fence;
  logic        id_is_illegal;

  decoder u_decoder (
    .inst       (id_inst),
    .rs1        (id_rs1),
    .rs2        (id_rs2),
    .rd         (id_rd),
    .imm        (id_imm),
    .reg_write  (id_reg_write),
    .mem_read   (id_mem_read),
    .mem_write  (id_mem_write),
    .mem_size   (id_mem_size),
    .branch     (id_branch),
    .branch_type(id_branch_type),
    .jump       (id_jump),
    .jalr       (id_jalr),
    .alu_src_a  (id_alu_src_a),
    .alu_src_b  (id_alu_src_b),
    .alu_op     (id_alu_op),
    .wb_src     (id_wb_src),
    .is_ecall   (id_is_ecall),
    .is_ebreak  (id_is_ebreak),
    .is_fence   (id_is_fence),
    .is_illegal (id_is_illegal)
  );

  logic [31:0] id_rdata1, id_rdata2;
  logic        wb_reg_write;
  logic [4:0]  wb_rd;
  logic [31:0] wb_final_data;

  regfile u_regfile (
    .clk   (clk),
    .rst_n (rst_n),
    .raddr1(id_rs1),
    .raddr2(id_rs2),
    .rdata1(id_rdata1),
    .rdata2(id_rdata2),
    .we    (wb_reg_write),
    .waddr (wb_rd),
    .wdata (wb_final_data)
  );

  logic        ex_valid;
  logic [31:0] ex_pc, ex_pc_plus4;
  logic [31:0] ex_rdata1, ex_rdata2;
  logic [31:0] ex_imm;
  logic [4:0]  ex_rs1, ex_rs2, ex_rd;
  logic        ex_reg_write;
  logic        ex_mem_read, ex_mem_write;
  logic [2:0]  ex_mem_size;
  logic        ex_branch;
  logic [2:0]  ex_branch_type;
  logic        ex_jump, ex_jalr;
  logic        ex_alu_src_a, ex_alu_src_b;
  logic [3:0]  ex_alu_op;
  logic [1:0]  ex_wb_src;

  pipe_reg_id_ex u_pipe_id_ex (
    .clk           (clk),
    .rst_n         (rst_n),
    .stall         (stall_id_ex),
    .flush         (flush_id_ex),
    .id_valid      (id_valid),
    .id_pc         (id_pc),
    .id_pc_plus4   (id_pc_plus4),
    .id_rdata1     (id_rdata1),
    .id_rdata2     (id_rdata2),
    .id_imm        (id_imm),
    .id_rs1        (id_rs1),
    .id_rs2        (id_rs2),
    .id_rd         (id_rd),
    .id_reg_write  (id_reg_write),
    .id_mem_read   (id_mem_read),
    .id_mem_write  (id_mem_write),
    .id_mem_size   (id_mem_size),
    .id_branch     (id_branch),
    .id_branch_type(id_branch_type),
    .id_jump       (id_jump),
    .id_jalr       (id_jalr),
    .id_alu_src_a  (id_alu_src_a),
    .id_alu_src_b  (id_alu_src_b),
    .id_alu_op     (id_alu_op),
    .id_wb_src     (id_wb_src),

    .ex_valid      (ex_valid),
    .ex_pc         (ex_pc),
    .ex_pc_plus4   (ex_pc_plus4),
    .ex_rdata1     (ex_rdata1),
    .ex_rdata2     (ex_rdata2),
    .ex_imm        (ex_imm),
    .ex_rs1        (ex_rs1),
    .ex_rs2        (ex_rs2),
    .ex_rd         (ex_rd),
    .ex_reg_write  (ex_reg_write),
    .ex_mem_read   (ex_mem_read),
    .ex_mem_write  (ex_mem_write),
    .ex_mem_size   (ex_mem_size),
    .ex_branch     (ex_branch),
    .ex_branch_type(ex_branch_type),
    .ex_jump       (ex_jump),
    .ex_jalr       (ex_jalr),
    .ex_alu_src_a  (ex_alu_src_a),
    .ex_alu_src_b  (ex_alu_src_b),
    .ex_alu_op     (ex_alu_op),
    .ex_wb_src     (ex_wb_src)
  );

  logic [1:0]  fwd_a, fwd_b;
  logic [4:0]  mem_rd;
  logic        mem_reg_write;
  logic [31:0] mem_fwd_data;

  forwarding_unit u_fwd (
    .rs1_id_ex       (ex_rs1),
    .rs2_id_ex       (ex_rs2),
    .rd_ex_mem       (mem_rd),
    .reg_write_ex_mem(mem_reg_write),
    .rd_mem_wb       (wb_rd),
    .reg_write_mem_wb(wb_reg_write),
    .fwd_a           (fwd_a),
    .fwd_b           (fwd_b)
  );

  logic [31:0] ex_op_a_forwarded;
  logic [31:0] ex_op_b_forwarded;

  always_comb begin
    case (fwd_a)
      FWD_EX_MEM: ex_op_a_forwarded = mem_fwd_data;
      FWD_MEM_WB: ex_op_a_forwarded = wb_final_data;
      default:    ex_op_a_forwarded = ex_rdata1;
    endcase

    case (fwd_b)
      FWD_EX_MEM: ex_op_b_forwarded = mem_fwd_data;
      FWD_MEM_WB: ex_op_b_forwarded = wb_final_data;
      default:    ex_op_b_forwarded = ex_rdata2;
    endcase
  end

  logic [31:0] ex_alu_in_a;
  logic [31:0] ex_alu_in_b;

  assign ex_alu_in_a = (ex_alu_src_a == ALU_SRC_A_PC)  ? ex_pc  : ex_op_a_forwarded;
  assign ex_alu_in_b = (ex_alu_src_b == ALU_SRC_B_IMM) ? ex_imm : ex_op_b_forwarded;

  logic [31:0] ex_alu_out;
  logic        ex_alu_zero;

  alu u_alu (
    .alu_op  (ex_alu_op),
    .alu_in_a(ex_alu_in_a),
    .alu_in_b(ex_alu_in_b),
    .alu_out (ex_alu_out),
    .alu_zero(ex_alu_zero)
  );

  branch_unit u_branch_unit (
    .branch     (ex_branch & ex_valid),
    .branch_type(ex_branch_type),
    .jump       (ex_jump & ex_valid),
    .jalr       (ex_jalr & ex_valid),
    .pc         (ex_pc),
    .imm        (ex_imm),
    .op_a       (ex_op_a_forwarded),
    .op_b       (ex_op_b_forwarded),
    .take_branch(take_branch_ex),
    .target_pc  (target_pc_ex)
  );

  logic        mem_valid;
  logic [31:0] mem_pc, mem_pc_plus4;
  logic [31:0] mem_alu_out;
  logic [31:0] mem_wdata;
  logic [31:0] mem_imm;
  logic        mem_mem_read, mem_mem_write;
  logic [2:0]  mem_mem_size;
  logic [1:0]  mem_wb_src;

  pipe_reg_ex_mem u_pipe_ex_mem (
    .clk          (clk),
    .rst_n        (rst_n),
    .stall        (stall_ex_mem),
    .flush        (flush_ex_mem),
    .ex_valid     (ex_valid),
    .ex_pc        (ex_pc),
    .ex_pc_plus4  (ex_pc_plus4),
    .ex_alu_out   (ex_alu_out),
    .ex_wdata     (ex_op_b_forwarded),
    .ex_imm       (ex_imm),
    .ex_rd        (ex_rd),
    .ex_reg_write (ex_reg_write),
    .ex_mem_read  (ex_mem_read),
    .ex_mem_write (ex_mem_write),
    .ex_mem_size  (ex_mem_size),
    .ex_wb_src    (ex_wb_src),

    .mem_valid    (mem_valid),
    .mem_pc       (mem_pc),
    .mem_pc_plus4 (mem_pc_plus4),
    .mem_alu_out  (mem_alu_out),
    .mem_wdata    (mem_wdata),
    .mem_imm      (mem_imm),
    .mem_rd       (mem_rd),
    .mem_reg_write(mem_reg_write),
    .mem_mem_read (mem_mem_read),
    .mem_mem_write(mem_mem_write),
    .mem_mem_size (mem_mem_size),
    .mem_wb_src   (mem_wb_src)
  );

  always_comb begin
    case (mem_wb_src)
      WB_PC_PLUS4: mem_fwd_data = mem_pc_plus4;
      WB_IMM:      mem_fwd_data = mem_imm;
      default:     mem_fwd_data = mem_alu_out;
    endcase
  end

  logic [31:0] mem_lsu_wdata;
  logic [3:0]  mem_lsu_wstrb;
  logic [31:0] mem_lsu_rdata;

  load_store_unit u_lsu (
    .mem_size      (mem_mem_size),
    .byte_offset   (mem_alu_out[1:0]),
    .store_data_in (mem_wdata),
    .store_data_out(mem_lsu_wdata),
    .store_strb    (mem_lsu_wstrb),
    .load_data_in  (dmem_rdata),
    .load_data_out (mem_lsu_rdata)
  );

  assign dmem_req   = mem_valid & (mem_mem_read | mem_mem_write);
  assign dmem_we    = mem_valid & mem_mem_write;
  assign dmem_addr  = mem_alu_out;
  assign dmem_wdata = mem_lsu_wdata;
  assign dmem_wstrb = mem_lsu_wstrb;

  logic        wb_valid;
  logic [31:0] wb_pc, wb_pc_plus4;
  logic [31:0] wb_alu_out;
  logic [31:0] wb_rdata;
  logic [31:0] wb_imm;
  logic [1:0]  wb_wb_src;

  pipe_reg_mem_wb u_pipe_mem_wb (
    .clk          (clk),
    .rst_n        (rst_n),
    .stall        (stall_mem_wb),
    .flush        (flush_mem_wb),
    .mem_valid    (mem_valid),
    .mem_pc       (mem_pc),
    .mem_pc_plus4 (mem_pc_plus4),
    .mem_alu_out  (mem_alu_out),
    .mem_rdata    (mem_lsu_rdata),
    .mem_imm      (mem_imm),
    .mem_rd       (mem_rd),
    .mem_reg_write(mem_reg_write),
    .mem_wb_src   (mem_wb_src),

    .wb_valid     (wb_valid),
    .wb_pc        (wb_pc),
    .wb_pc_plus4  (wb_pc_plus4),
    .wb_alu_out   (wb_alu_out),
    .wb_rdata     (wb_rdata),
    .wb_imm       (wb_imm),
    .wb_rd        (wb_rd),
    .wb_reg_write (wb_reg_write),
    .wb_wb_src    (wb_wb_src)
  );

  always_comb begin
    case (wb_wb_src)
      WB_ALU:      wb_final_data = wb_alu_out;
      WB_MEM:      wb_final_data = wb_rdata;
      WB_PC_PLUS4: wb_final_data = wb_pc_plus4;
      WB_IMM:      wb_final_data = wb_imm;
      default:     wb_final_data = wb_alu_out;
    endcase
  end

  assign debug_wb_pc    = wb_pc;
  assign debug_wb_rd    = wb_rd;
  assign debug_wb_data  = wb_final_data;
  assign debug_wb_valid = wb_valid & wb_reg_write;

  assign perf_instret_tick      = wb_valid;
  assign perf_bus_stall_tick    = dmem_stall;

  logic id_rs1_used, id_rs2_used;
  always_comb begin
    case (id_inst[6:0])
      OPCODE_OP:        begin id_rs1_used = 1'b1; id_rs2_used = 1'b1; end
      OPCODE_OP_IMM:    begin id_rs1_used = 1'b1; id_rs2_used = 1'b0; end
      OPCODE_LOAD:      begin id_rs1_used = 1'b1; id_rs2_used = 1'b0; end
      OPCODE_STORE:     begin id_rs1_used = 1'b1; id_rs2_used = 1'b1; end
      OPCODE_BRANCH:    begin id_rs1_used = 1'b1; id_rs2_used = 1'b1; end
      OPCODE_JALR:      begin id_rs1_used = 1'b1; id_rs2_used = 1'b0; end
      default:          begin id_rs1_used = 1'b0; id_rs2_used = 1'b0; end
    endcase
  end

  hazard_unit u_hazard (
    .rs1_if_id           (id_rs1),
    .rs2_if_id           (id_rs2),
    .rs1_valid_if_id     (id_valid & id_rs1_used),
    .rs2_valid_if_id     (id_valid & id_rs2_used),
    .rd_id_ex            (ex_rd),
    .mem_read_id_ex      (ex_mem_read & ex_valid),
    .take_branch_ex      (take_branch_ex),
    .dmem_stall          (dmem_stall),
    .stall_pc            (stall_pc),
    .stall_if_id         (stall_if_id),
    .stall_id_ex         (stall_id_ex),
    .stall_ex_mem        (stall_ex_mem),
    .stall_mem_wb        (stall_mem_wb),
    .flush_if_id         (flush_if_id),
    .flush_id_ex         (flush_id_ex),
    .flush_ex_mem        (flush_ex_mem),
    .flush_mem_wb        (flush_mem_wb),
    .load_use_hazard_tick(perf_load_use_tick),
    .branch_flush_tick   (perf_branch_flush_tick),
    .bus_stall_tick      ()
  );

endmodule
