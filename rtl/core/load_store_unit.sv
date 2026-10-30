`timescale 1ns/1ps

import riscv_pkg::*;

module load_store_unit (
  input  logic [2:0]  mem_size,
  input  logic [1:0]  byte_offset,
  input  logic [31:0] store_data_in,
  output logic [31:0] store_data_out,
  output logic [3:0]  store_strb,
  input  logic [31:0] load_data_in,
  output logic [31:0] load_data_out
);

  always_comb begin
    case (mem_size)
      MEM_BYTE: begin
        case (byte_offset)
          2'b00: begin
            store_strb     = 4'b0001;
            store_data_out = {24'h0, store_data_in[7:0]};
          end
          2'b01: begin
            store_strb     = 4'b0010;
            store_data_out = {16'h0, store_data_in[7:0], 8'h0};
          end
          2'b10: begin
            store_strb     = 4'b0100;
            store_data_out = {8'h0, store_data_in[7:0], 16'h0};
          end
          2'b11: begin
            store_strb     = 4'b1000;
            store_data_out = {store_data_in[7:0], 24'h0};
          end
        endcase
      end

      MEM_HALF: begin
        if (byte_offset[1]) begin
          store_strb     = 4'b1100;
          store_data_out = {store_data_in[15:0], 16'h0};
        end else begin
          store_strb     = 4'b0011;
          store_data_out = {16'h0, store_data_in[15:0]};
        end
      end

      MEM_WORD: begin
        store_strb     = 4'b1111;
        store_data_out = store_data_in;
      end

      default: begin
        store_strb     = 4'b0000;
        store_data_out = store_data_in;
      end
    endcase
  end

  logic [7:0]  selected_byte;
  logic [15:0] selected_half;

  always_comb begin
    case (byte_offset)
      2'b00: selected_byte = load_data_in[7:0];
      2'b01: selected_byte = load_data_in[15:8];
      2'b10: selected_byte = load_data_in[23:16];
      2'b11: selected_byte = load_data_in[31:24];
    endcase

    if (byte_offset[1])
      selected_half = load_data_in[31:16];
    else
      selected_half = load_data_in[15:0];

    case (mem_size)
      MEM_BYTE:   load_data_out = {{24{selected_byte[7]}}, selected_byte};
      MEM_BYTE_U: load_data_out = {24'h0, selected_byte};
      MEM_HALF:   load_data_out = {{16{selected_half[15]}}, selected_half};
      MEM_HALF_U: load_data_out = {16'h0, selected_half};
      MEM_WORD:   load_data_out = load_data_in;
      default:    load_data_out = load_data_in;
    endcase
  end

endmodule
