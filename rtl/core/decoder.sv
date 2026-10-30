`timescale 1ns/1ps

import riscv_pkg::*;

module decoder (
  input  logic [31:0] inst,
  output logic [4:0]  rs1,
  output logic [4:0]  rs2,
  output logic [4:0]  rd,
  output logic [31:0] imm,
  output logic        reg_write,
  output logic        mem_read,
  output logic        mem_write,
  output logic [2:0]  mem_size,
  output logic        branch,
  output logic [2:0]  branch_type,
  output logic        jump,
  output logic        jalr,
  output logic        alu_src_a,
  output logic        alu_src_b,
  output logic [3:0]  alu_op,
  output logic [1:0]  wb_src,
  output logic        is_ecall,
  output logic        is_ebreak,
  output logic        is_fence,
  output logic        is_illegal
);

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;

  assign opcode = inst[6:0];
  assign rd     = inst[11:7];
  assign funct3 = inst[14:12];
  assign rs1    = inst[19:15];
  assign rs2    = inst[24:20];
  assign funct7 = inst[31:25];

  logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;

  imm_gen u_imm_gen (
    .inst (inst),
    .imm_i(imm_i),
    .imm_s(imm_s),
    .imm_b(imm_b),
    .imm_u(imm_u),
    .imm_j(imm_j)
  );

  always_comb begin
    reg_write   = 1'b0;
    mem_read    = 1'b0;
    mem_write   = 1'b0;
    mem_size    = funct3;
    branch      = 1'b0;
    branch_type = funct3;
    jump        = 1'b0;
    jalr        = 1'b0;
    alu_src_a   = ALU_SRC_A_REG;
    alu_src_b   = ALU_SRC_B_REG;
    alu_op      = ALU_ADD;
    wb_src      = WB_ALU;
    imm         = imm_i;
    is_ecall    = 1'b0;
    is_ebreak   = 1'b0;
    is_fence    = 1'b0;
    is_illegal  = 1'b0;

    case (opcode)
      OPCODE_LUI: begin
        reg_write = 1'b1;
        wb_src    = WB_IMM;
        imm       = imm_u;
      end

      OPCODE_AUIPC: begin
        reg_write = 1'b1;
        alu_src_a = ALU_SRC_A_PC;
        alu_src_b = ALU_SRC_B_IMM;
        alu_op    = ALU_ADD;
        wb_src    = WB_ALU;
        imm       = imm_u;
      end

      OPCODE_JAL: begin
        reg_write = 1'b1;
        jump      = 1'b1;
        wb_src    = WB_PC_PLUS4;
        imm       = imm_j;
      end

      OPCODE_JALR: begin
        reg_write = 1'b1;
        jump      = 1'b1;
        jalr      = 1'b1;
        alu_src_a = ALU_SRC_A_REG;
        alu_src_b = ALU_SRC_B_IMM;
        alu_op    = ALU_ADD;
        wb_src    = WB_PC_PLUS4;
        imm       = imm_i;
      end

      OPCODE_BRANCH: begin
        branch      = 1'b1;
        branch_type = funct3;
        imm         = imm_b;
      end

      OPCODE_LOAD: begin
        reg_write = 1'b1;
        mem_read  = 1'b1;
        alu_src_a = ALU_SRC_A_REG;
        alu_src_b = ALU_SRC_B_IMM;
        alu_op    = ALU_ADD;
        wb_src    = WB_MEM;
        imm       = imm_i;
      end

      OPCODE_STORE: begin
        mem_write = 1'b1;
        alu_src_a = ALU_SRC_A_REG;
        alu_src_b = ALU_SRC_B_IMM;
        alu_op    = ALU_ADD;
        imm       = imm_s;
      end

      OPCODE_OP_IMM: begin
        reg_write = 1'b1;
        alu_src_a = ALU_SRC_A_REG;
        alu_src_b = ALU_SRC_B_IMM;
        wb_src    = WB_ALU;
        imm       = imm_i;
        case (funct3)
          3'b000: alu_op = ALU_ADD;
          3'b010: alu_op = ALU_SLT;
          3'b011: alu_op = ALU_SLTU;
          3'b100: alu_op = ALU_XOR;
          3'b110: alu_op = ALU_OR;
          3'b111: alu_op = ALU_AND;
          3'b001: alu_op = ALU_SLL;
          3'b101: begin
            if (funct7[5])
              alu_op = ALU_SRA;
            else
              alu_op = ALU_SRL;
          end
          default: is_illegal = 1'b1;
        endcase
      end

      OPCODE_OP: begin
        reg_write = 1'b1;
        alu_src_a = ALU_SRC_A_REG;
        alu_src_b = ALU_SRC_B_REG;
        wb_src    = WB_ALU;
        case (funct3)
          3'b000: begin
            if (funct7[5])
              alu_op = ALU_SUB;
            else
              alu_op = ALU_ADD;
          end
          3'b001: alu_op = ALU_SLL;
          3'b010: alu_op = ALU_SLT;
          3'b011: alu_op = ALU_SLTU;
          3'b100: alu_op = ALU_XOR;
          3'b101: begin
            if (funct7[5])
              alu_op = ALU_SRA;
            else
              alu_op = ALU_SRL;
          end
          3'b110: alu_op = ALU_OR;
          3'b111: alu_op = ALU_AND;
          default: is_illegal = 1'b1;
        endcase
      end

      OPCODE_FENCE: begin
        is_fence = 1'b1;
      end

      OPCODE_SYSTEM: begin
        if (funct3 == 3'b000) begin
          if (inst[31:20] == 12'h000)
            is_ecall = 1'b1;
          else if (inst[31:20] == 12'h001)
            is_ebreak = 1'b1;
          else
            is_illegal = 1'b1;
        end else begin
          is_illegal = 1'b1;
        end
      end

      default: begin
        is_illegal = 1'b1;
      end
    endcase
  end

endmodule
