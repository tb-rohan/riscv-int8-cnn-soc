`timescale 1ns/1ps

module timer (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        req,
  input  logic        we,
  input  logic [31:0] addr,
  input  logic [31:0] wdata,
  output logic [31:0] rdata,
  input  logic        tick_instret,
  input  logic        tick_load_use,
  input  logic        tick_branch_flush,
  input  logic        tick_bus_stall
);

  logic [63:0] cycles;
  logic [31:0] instret;
  logic [31:0] load_use_stalls;
  logic [31:0] branch_flushes;
  logic [31:0] bus_stalls;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycles          <= 64'd0;
      instret         <= 32'd0;
      load_use_stalls <= 32'd0;
      branch_flushes  <= 32'd0;
      bus_stalls      <= 32'd0;
    end else begin
      cycles <= cycles + 64'd1;
      if (tick_instret)
        instret <= instret + 32'd1;
      if (tick_load_use)
        load_use_stalls <= load_use_stalls + 32'd1;
      if (tick_branch_flush)
        branch_flushes <= branch_flushes + 32'd1;
      if (tick_bus_stall)
        bus_stalls <= bus_stalls + 32'd1;

      if (req && we) begin
        case (addr[4:2])
          3'b000: cycles[31:0]    <= wdata;
          3'b001: cycles[63:32]   <= wdata;
          3'b010: instret         <= wdata;
          3'b011: load_use_stalls <= wdata;
          3'b100: branch_flushes  <= wdata;
          3'b101: bus_stalls      <= wdata;
          default: ;
        endcase
      end
    end
  end

  always_comb begin
    case (addr[4:2])
      3'b000:  rdata = cycles[31:0];
      3'b001:  rdata = cycles[63:32];
      3'b010:  rdata = instret;
      3'b011:  rdata = load_use_stalls;
      3'b100:  rdata = branch_flushes;
      3'b101:  rdata = bus_stalls;
      default: rdata = 32'd0;
    endcase
  end

endmodule
