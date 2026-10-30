`timescale 1ns/1ps

package riscv_pkg;

  typedef enum logic [6:0] {
    OPCODE_LUI      = 7'b0110111,
    OPCODE_AUIPC    = 7'b0010111,
    OPCODE_JAL      = 7'b1101111,
    OPCODE_JALR     = 7'b1100111,
    OPCODE_BRANCH   = 7'b1100011,
    OPCODE_LOAD     = 7'b0000011,
    OPCODE_STORE    = 7'b0100011,
    OPCODE_OP_IMM   = 7'b0010011,
    OPCODE_OP       = 7'b0110011,
    OPCODE_SYSTEM   = 7'b1110011,
    OPCODE_FENCE    = 7'b0001111
  } opcode_e;

  typedef enum logic [3:0] {
    ALU_ADD  = 4'b0000,
    ALU_SUB  = 4'b1000,
    ALU_SLL  = 4'b0001,
    ALU_SLT  = 4'b0010,
    ALU_SLTU = 4'b0011,
    ALU_XOR  = 4'b0100,
    ALU_SRL  = 4'b0101,
    ALU_SRA  = 4'b1101,
    ALU_OR   = 4'b0110,
    ALU_AND  = 4'b0111,
    ALU_COPY = 4'b1111
  } alu_op_e;

  typedef enum logic [2:0] {
    BR_BEQ  = 3'b000,
    BR_BNE  = 3'b001,
    BR_BLT  = 3'b100,
    BR_BGE  = 3'b101,
    BR_BLTU = 3'b110,
    BR_BGEU = 3'b111
  } branch_type_e;

  typedef enum logic [2:0] {
    MEM_BYTE    = 3'b000,
    MEM_HALF    = 3'b001,
    MEM_WORD    = 3'b010,
    MEM_BYTE_U  = 3'b100,
    MEM_HALF_U  = 3'b101
  } mem_size_e;

  typedef enum logic [1:0] {
    WB_ALU      = 2'b00,
    WB_MEM      = 2'b01,
    WB_PC_PLUS4 = 2'b10,
    WB_IMM      = 2'b11
  } wb_src_e;

  typedef enum logic {
    ALU_SRC_A_REG = 1'b0,
    ALU_SRC_A_PC  = 1'b1
  } alu_src_a_e;

  typedef enum logic {
    ALU_SRC_B_REG = 1'b0,
    ALU_SRC_B_IMM = 1'b1
  } alu_src_b_e;

  typedef enum logic [1:0] {
    FWD_NONE   = 2'b00,
    FWD_EX_MEM = 2'b01,
    FWD_MEM_WB = 2'b10
  } fwd_sel_e;

endpackage: riscv_pkg
