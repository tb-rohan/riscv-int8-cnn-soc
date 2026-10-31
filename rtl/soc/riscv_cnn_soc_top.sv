`timescale 1ns/1ps

module riscv_cnn_soc_top #(
  parameter IMEM_INIT_FILE = "",
  parameter DMEM_INIT_FILE = ""
) (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        ext_host_req,
  input  logic [7:0]  ext_host_cmd,
  input  logic [31:0] ext_host_op_a,
  input  logic [31:0] ext_host_op_b,
  output logic        ext_host_done,
  output logic [31:0] ext_host_result,
  output logic [31:0] ext_host_result_hi,
  output logic [31:0] ext_host_status,

  input  logic        ext_imem_we,
  input  logic [31:0] ext_imem_waddr,
  input  logic [31:0] ext_imem_wdata,
  input  logic [3:0]  ext_imem_wstrb,

  output logic [31:0] debug_wb_pc,
  output logic [4:0]  debug_wb_rd,
  output logic [31:0] debug_wb_data,
  output logic        debug_wb_valid,
  output logic        accel_irq_out
);

  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;

  logic        dmem_req;
  logic        dmem_we;
  logic [31:0] dmem_addr;
  logic [31:0] dmem_wdata;
  logic [3:0]  dmem_wstrb;
  logic [31:0] dmem_rdata;
  logic        dmem_stall;

  logic        perf_instret_tick;
  logic        perf_load_use_tick;
  logic        perf_branch_flush_tick;
  logic        perf_bus_stall_tick;

  rv32i_core u_core (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .imem_addr             (imem_addr),
    .imem_rdata            (imem_rdata),
    .dmem_req              (dmem_req),
    .dmem_we               (dmem_we),
    .dmem_addr             (dmem_addr),
    .dmem_wdata            (dmem_wdata),
    .dmem_wstrb            (dmem_wstrb),
    .dmem_rdata            (dmem_rdata),
    .dmem_stall            (dmem_stall),
    .debug_wb_pc           (debug_wb_pc),
    .debug_wb_rd           (debug_wb_rd),
    .debug_wb_data         (debug_wb_data),
    .debug_wb_valid        (debug_wb_valid),
    .perf_instret_tick     (perf_instret_tick),
    .perf_load_use_tick    (perf_load_use_tick),
    .perf_branch_flush_tick(perf_branch_flush_tick),
    .perf_bus_stall_tick   (perf_bus_stall_tick)
  );

  imem #(
    .ADDR_WIDTH(14),
    .INIT_FILE(IMEM_INIT_FILE)
  ) u_imem (
    .clk  (clk),
    .rst_n(rst_n),
    .addr (imem_addr),
    .rdata(imem_rdata),
    .we   (ext_imem_we),
    .waddr(ext_imem_waddr),
    .wdata(ext_imem_wdata),
    .wstrb(ext_imem_wstrb)
  );

  logic        bus_dmem_req, bus_dmem_we;
  logic [31:0] bus_dmem_addr, bus_dmem_wdata, bus_dmem_rdata;
  logic [3:0]  bus_dmem_wstrb;

  logic        host_req, host_we;
  logic [31:0] host_addr, host_wdata, host_rdata;

  logic        timer_req, timer_we;
  logic [31:0] timer_addr, timer_wdata, timer_rdata;

  logic        uart_req, uart_we;
  logic [31:0] uart_addr, uart_wdata, uart_rdata;

  logic        accel_req, accel_we;
  logic [31:0] accel_addr, accel_wdata, accel_rdata;
  logic [3:0]  accel_wstrb;
  logic        accel_stall;

  bus_interconnect u_bus (
    .cpu_req     (dmem_req),
    .cpu_we      (dmem_we),
    .cpu_addr    (dmem_addr),
    .cpu_wdata   (dmem_wdata),
    .cpu_wstrb   (dmem_wstrb),
    .cpu_rdata   (dmem_rdata),
    .cpu_stall   (dmem_stall),

    .imem_req    (),
    .imem_we     (),
    .imem_addr   (),
    .imem_wdata  (),
    .imem_wstrb  (),
    .imem_rdata  (32'h0),

    .dmem_req    (bus_dmem_req),
    .dmem_we     (bus_dmem_we),
    .dmem_addr   (bus_dmem_addr),
    .dmem_wdata  (bus_dmem_wdata),
    .dmem_wstrb  (bus_dmem_wstrb),
    .dmem_rdata  (bus_dmem_rdata),

    .host_req    (host_req),
    .host_we     (host_we),
    .host_addr   (host_addr),
    .host_wdata  (host_wdata),
    .host_rdata  (host_rdata),

    .timer_req   (timer_req),
    .timer_we    (timer_we),
    .timer_addr  (timer_addr),
    .timer_wdata (timer_wdata),
    .timer_rdata (timer_rdata),

    .uart_req    (uart_req),
    .uart_we     (uart_we),
    .uart_addr   (uart_addr),
    .uart_wdata  (uart_wdata),
    .uart_rdata  (uart_rdata),

    .dma_req     (dma_req),
    .dma_we      (dma_we),
    .dma_addr    (dma_addr),
    .dma_wdata   (dma_wdata),
    .dma_rdata   (dma_rdata),
    .dma_stall   (dma_stall),
    .dma_busy    (dma_busy),

    .accel_req   (accel_req),
    .accel_we    (accel_we),
    .accel_addr  (accel_addr),
    .accel_wdata (accel_wdata),
    .accel_wstrb (accel_wstrb),
    .accel_rdata (accel_rdata),
    .accel_stall (accel_stall)
  );

  // ---------------------------------------------------------------------------
  // Autonomous Streaming DMA Controller
  // ---------------------------------------------------------------------------
  logic        dma_req;
  logic        dma_we;
  logic [31:0] dma_addr;
  logic [31:0] dma_wdata;
  logic [31:0] dma_rdata;
  logic        dma_stall;

  logic        dma_m_mem_req;
  logic [31:0] dma_m_mem_addr;
  logic        dma_m_accel_req;
  logic        dma_m_accel_we;
  logic [7:0]  dma_m_accel_addr;
  logic [31:0] dma_m_accel_wdata;
  logic [3:0]  dma_m_accel_wstrb;
  logic        dma_busy;
  logic        dma_irq;

  soc_dma u_dma (
    .clk          (clk),
    .rst_n        (rst_n),
    .s_req        (dma_req),
    .s_we         (dma_we),
    .s_addr       (dma_addr[7:0]),
    .s_wdata      (dma_wdata),
    .s_rdata      (dma_rdata),
    .s_stall      (dma_stall),
    .m_mem_req    (dma_m_mem_req),
    .m_mem_addr   (dma_m_mem_addr),
    .m_mem_rdata  (bus_dmem_rdata),
    .m_accel_req  (dma_m_accel_req),
    .m_accel_we   (dma_m_accel_we),
    .m_accel_addr (dma_m_accel_addr),
    .m_accel_wdata(dma_m_accel_wdata),
    .m_accel_wstrb(dma_m_accel_wstrb),
    .m_accel_stall(accel_stall),
    .dma_irq      (dma_irq),
    .dma_busy     (dma_busy)
  );

  // Multiplexed DMEM Interface (CPU vs DMA)
  logic        dmem_mux_req;
  logic        dmem_mux_we;
  logic [31:0] dmem_mux_addr;
  logic [31:0] dmem_mux_wdata;
  logic [3:0]  dmem_mux_wstrb;

  always_comb begin
    if (dma_busy) begin
      dmem_mux_req   = dma_m_mem_req;
      dmem_mux_we    = 1'b0;
      dmem_mux_addr  = dma_m_mem_addr;
      dmem_mux_wdata = 32'h0;
      dmem_mux_wstrb = 4'h0;
    end else begin
      dmem_mux_req   = bus_dmem_req;
      dmem_mux_we    = bus_dmem_we;
      dmem_mux_addr  = bus_dmem_addr;
      dmem_mux_wdata = bus_dmem_wdata;
      dmem_mux_wstrb = bus_dmem_wstrb;
    end
  end

  dmem #(
    .ADDR_WIDTH(14),
    .INIT_FILE(DMEM_INIT_FILE)
  ) u_dmem (
    .clk  (clk),
    .rst_n(rst_n),
    .req  (dmem_mux_req),
    .we   (dmem_mux_we),
    .addr (dmem_mux_addr),
    .wdata(dmem_mux_wdata),
    .wstrb(dmem_mux_wstrb),
    .rdata(bus_dmem_rdata)
  );

  host_interface u_host (
    .clk          (clk),
    .rst_n        (rst_n),
    .req          (host_req),
    .we           (host_we),
    .addr         (host_addr),
    .wdata        (host_wdata),
    .rdata        (host_rdata),
    .ext_req      (ext_host_req),
    .ext_cmd      (ext_host_cmd),
    .ext_op_a     (ext_host_op_a),
    .ext_op_b     (ext_host_op_b),
    .ext_done     (ext_host_done),
    .ext_result   (ext_host_result),
    .ext_result_hi(ext_host_result_hi),
    .ext_status   (ext_host_status)
  );

  timer u_timer (
    .clk              (clk),
    .rst_n            (rst_n),
    .req              (timer_req),
    .we               (timer_we),
    .addr             (timer_addr),
    .wdata            (timer_wdata),
    .rdata            (timer_rdata),
    .tick_instret     (perf_instret_tick),
    .tick_load_use    (perf_load_use_tick),
    .tick_branch_flush(perf_branch_flush_tick),
    .tick_bus_stall   (perf_bus_stall_tick)
  );

  uart_lite u_uart (
    .clk     (clk),
    .rst_n   (rst_n),
    .req     (uart_req),
    .we      (uart_we),
    .addr    (uart_addr),
    .wdata   (uart_wdata),
    .rdata   (uart_rdata),
    .tx_valid(),
    .tx_char ()
  );

  logic [7:0]  axil_awaddr;
  logic        axil_awvalid;
  logic        axil_awready;
  logic [31:0] axil_wdata;
  logic [3:0]  axil_wstrb;
  logic        axil_wvalid;
  logic        axil_wready;
  logic [1:0]  axil_bresp;
  logic        axil_bvalid;
  logic        axil_bready;

  logic [7:0]  axil_araddr;
  logic        axil_arvalid;
  logic        axil_arready;
  logic [31:0] axil_rdata;
  logic [1:0]  axil_rresp;
  logic        axil_rvalid;
  logic        axil_rready;

  logic        accel_irq;

  // Multiplexed Accelerator Adapter Interface (CPU vs DMA)
  logic        adapter_req;
  logic        adapter_we;
  logic [31:0] adapter_addr;
  logic [31:0] adapter_wdata;
  logic [3:0]  adapter_wstrb;

  always_comb begin
    if (dma_busy) begin
      adapter_req   = dma_m_accel_req;
      adapter_we    = dma_m_accel_we;
      adapter_addr  = {24'h8000_10, dma_m_accel_addr};
      adapter_wdata = dma_m_accel_wdata;
      adapter_wstrb = dma_m_accel_wstrb;
    end else begin
      adapter_req   = accel_req;
      adapter_we    = accel_we;
      adapter_addr  = accel_addr;
      adapter_wdata = accel_wdata;
      adapter_wstrb = accel_wstrb;
    end
  end

  accel_adapter u_adapter (
    .clk           (clk),
    .rst_n         (rst_n),
    .req           (adapter_req),
    .we            (adapter_we),
    .addr          (adapter_addr),
    .wdata         (adapter_wdata),
    .wstrb         (adapter_wstrb),
    .rdata         (accel_rdata),
    .stall         (accel_stall),
    .m_axil_awaddr (axil_awaddr),
    .m_axil_awvalid(axil_awvalid),
    .m_axil_awready(axil_awready),
    .m_axil_wdata  (axil_wdata),
    .m_axil_wstrb  (axil_wstrb),
    .m_axil_wvalid (axil_wvalid),
    .m_axil_wready (axil_wready),
    .m_axil_bresp  (axil_bresp),
    .m_axil_bvalid (axil_bvalid),
    .m_axil_bready (axil_bready),
    .m_axil_araddr (axil_araddr),
    .m_axil_arvalid(axil_arvalid),
    .m_axil_arready(axil_arready),
    .m_axil_rdata  (axil_rdata),
    .m_axil_rresp  (axil_rresp),
    .m_axil_rvalid (axil_rvalid),
    .m_axil_rready (axil_rready),
    .accel_irq     (accel_irq),
    .irq_status    ()
  );

  assign accel_irq_out = accel_irq | dma_irq;

  accel_top u_accel (
    .clk          (clk),
    .rst_n        (rst_n),
    .s_axil_awaddr(axil_awaddr),
    .s_axil_awvalid(axil_awvalid),
    .s_axil_awready(axil_awready),
    .s_axil_wdata (axil_wdata),
    .s_axil_wstrb (axil_wstrb),
    .s_axil_wvalid(axil_wvalid),
    .s_axil_wready(axil_wready),
    .s_axil_bresp (axil_bresp),
    .s_axil_bvalid(axil_bvalid),
    .s_axil_bready(axil_bready),
    .s_axil_araddr(axil_araddr),
    .s_axil_arvalid(axil_arvalid),
    .s_axil_arready(axil_arready),
    .s_axil_rdata (axil_rdata),
    .s_axil_rresp (axil_rresp),
    .s_axil_rvalid(axil_rvalid),
    .s_axil_rready(axil_rready),
    .irq          (accel_irq)
  );

endmodule
