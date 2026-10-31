`timescale 1ns/1ps

module bus_interconnect (
  input  logic        cpu_req,
  input  logic        cpu_we,
  input  logic [31:0] cpu_addr,
  input  logic [31:0] cpu_wdata,
  input  logic [3:0]  cpu_wstrb,
  output logic [31:0] cpu_rdata,
  output logic        cpu_stall,

  output logic        imem_req,
  output logic        imem_we,
  output logic [31:0] imem_addr,
  output logic [31:0] imem_wdata,
  output logic [3:0]  imem_wstrb,
  input  logic [31:0] imem_rdata,

  output logic        dmem_req,
  output logic        dmem_we,
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wdata,
  output logic [3:0]  dmem_wstrb,
  input  logic [31:0] dmem_rdata,

  output logic        host_req,
  output logic        host_we,
  output logic [31:0] host_addr,
  output logic [31:0] host_wdata,
  input  logic [31:0] host_rdata,

  output logic        timer_req,
  output logic        timer_we,
  output logic [31:0] timer_addr,
  output logic [31:0] timer_wdata,
  input  logic [31:0] timer_rdata,

  output logic        uart_req,
  output logic        uart_we,
  output logic [31:0] uart_addr,
  output logic [31:0] uart_wdata,
  input  logic [31:0] uart_rdata,

  output logic        dma_req,
  output logic        dma_we,
  output logic [31:0] dma_addr,
  output logic [31:0] dma_wdata,
  input  logic [31:0] dma_rdata,
  input  logic        dma_stall,
  input  logic        dma_busy,

  output logic        accel_req,
  output logic        accel_we,
  output logic [31:0] accel_addr,
  output logic [31:0] accel_wdata,
  output logic [3:0]  accel_wstrb,
  input  logic [31:0] accel_rdata,
  input  logic        accel_stall
);

  typedef enum logic [2:0] {
    SEL_NONE  = 3'd0,
    SEL_IMEM  = 3'd1,
    SEL_DMEM  = 3'd2,
    SEL_HOST  = 3'd3,
    SEL_TIMER = 3'd4,
    SEL_UART  = 3'd5,
    SEL_ACCEL = 3'd6,
    SEL_DMA   = 3'd7
  } slave_sel_e;

  slave_sel_e sel;

  always_comb begin
    if (cpu_addr >= 32'h0000_0000 && cpu_addr <= 32'h0000_3FFF) begin
      sel = SEL_IMEM;
    end else if (cpu_addr >= 32'h0000_4000 && cpu_addr <= 32'h0000_7FFF) begin
      sel = SEL_DMEM;
    end else if (cpu_addr >= 32'h8000_0000 && cpu_addr <= 32'h8000_001F) begin
      sel = SEL_HOST;
    end else if (cpu_addr >= 32'h8000_0020 && cpu_addr <= 32'h8000_003F) begin
      sel = SEL_TIMER;
    end else if (cpu_addr >= 32'h8000_0040 && cpu_addr <= 32'h8000_005F) begin
      sel = SEL_UART;
    end else if (cpu_addr >= 32'h8000_0060 && cpu_addr <= 32'h8000_007F) begin
      sel = SEL_DMA;
    end else if (cpu_addr >= 32'h8000_1000 && cpu_addr <= 32'h8000_10FF) begin
      sel = SEL_ACCEL;
    end else begin
      sel = SEL_NONE;
    end
  end

  assign imem_req   = cpu_req & (sel == SEL_IMEM);
  assign imem_we    = cpu_we;
  assign imem_addr  = cpu_addr;
  assign imem_wdata = cpu_wdata;
  assign imem_wstrb = cpu_wstrb;

  assign dmem_req   = cpu_req & (sel == SEL_DMEM);
  assign dmem_we    = cpu_we;
  assign dmem_addr  = cpu_addr;
  assign dmem_wdata = cpu_wdata;
  assign dmem_wstrb = cpu_wstrb;

  assign host_req   = cpu_req & (sel == SEL_HOST);
  assign host_we    = cpu_we;
  assign host_addr  = cpu_addr;
  assign host_wdata = cpu_wdata;

  assign timer_req   = cpu_req & (sel == SEL_TIMER);
  assign timer_we    = cpu_we;
  assign timer_addr  = cpu_addr;
  assign timer_wdata = cpu_wdata;

  assign uart_req   = cpu_req & (sel == SEL_UART);
  assign uart_we    = cpu_we;
  assign uart_addr  = cpu_addr;
  assign uart_wdata = cpu_wdata;

  assign dma_req    = cpu_req & (sel == SEL_DMA);
  assign dma_we     = cpu_we;
  assign dma_addr   = cpu_addr;
  assign dma_wdata  = cpu_wdata;

  assign accel_req   = cpu_req & (sel == SEL_ACCEL);
  assign accel_we    = cpu_we;
  assign accel_addr  = cpu_addr;
  assign accel_wdata = cpu_wdata;
  assign accel_wstrb = cpu_wstrb;

  always_comb begin
    case (sel)
      SEL_IMEM:  cpu_rdata = imem_rdata;
      SEL_DMEM:  cpu_rdata = dmem_rdata;
      SEL_HOST:  cpu_rdata = host_rdata;
      SEL_TIMER: cpu_rdata = timer_rdata;
      SEL_UART:  cpu_rdata = uart_rdata;
      SEL_DMA:   cpu_rdata = dma_rdata;
      SEL_ACCEL: cpu_rdata = accel_rdata;
      default:   cpu_rdata = 32'h0;
    endcase
  end

  assign cpu_stall = (sel == SEL_ACCEL) ? accel_stall :
                     (sel == SEL_DMA)   ? dma_stall   :
                     (sel == SEL_DMEM && dma_busy) ? 1'b1 : 1'b0;

endmodule
