`timescale 1ns/1ps

module cpu_standalone_top #(
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
  output logic        debug_wb_valid
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

  logic        imem_bus_we;
  logic [31:0] imem_bus_waddr;
  logic [31:0] imem_bus_wdata;
  logic [3:0]  imem_bus_wstrb;

  assign imem_bus_we    = ext_imem_we;
  assign imem_bus_waddr = ext_imem_waddr;
  assign imem_bus_wdata = ext_imem_wdata;
  assign imem_bus_wstrb = ext_imem_wstrb;

  imem #(
    .ADDR_WIDTH(14),
    .INIT_FILE(IMEM_INIT_FILE)
  ) u_imem (
    .clk  (clk),
    .rst_n(rst_n),
    .addr (imem_addr),
    .rdata(imem_rdata),
    .we   (imem_bus_we),
    .waddr(imem_bus_waddr),
    .wdata(imem_bus_wdata),
    .wstrb(imem_bus_wstrb)
  );

  logic        bus_imem_req, bus_imem_we;
  logic [31:0] bus_imem_addr, bus_imem_wdata, bus_imem_rdata;
  logic [3:0]  bus_imem_wstrb;

  logic        bus_dmem_req, bus_dmem_we;
  logic [31:0] bus_dmem_addr, bus_dmem_wdata, bus_dmem_rdata;
  logic [3:0]  bus_dmem_wstrb;

  logic        host_req, host_we;
  logic [31:0] host_addr, host_wdata, host_rdata;

  logic        timer_req, timer_we;
  logic [31:0] timer_addr, timer_wdata, timer_rdata;

  logic        uart_req, uart_we;
  logic [31:0] uart_addr, uart_wdata, uart_rdata;

  bus_interconnect u_bus (
    .cpu_req     (dmem_req),
    .cpu_we      (dmem_we),
    .cpu_addr    (dmem_addr),
    .cpu_wdata   (dmem_wdata),
    .cpu_wstrb   (dmem_wstrb),
    .cpu_rdata   (dmem_rdata),
    .cpu_stall   (dmem_stall),

    .imem_req    (bus_imem_req),
    .imem_we     (bus_imem_we),
    .imem_addr   (bus_imem_addr),
    .imem_wdata  (bus_imem_wdata),
    .imem_wstrb  (bus_imem_wstrb),
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

    .accel_req   (),
    .accel_we    (),
    .accel_addr  (),
    .accel_wdata (),
    .accel_wstrb (),
    .accel_rdata (32'h0),
    .accel_stall (1'b0)
  );

  dmem #(
    .ADDR_WIDTH(14),
    .INIT_FILE(DMEM_INIT_FILE)
  ) u_dmem (
    .clk  (clk),
    .rst_n(rst_n),
    .req  (bus_dmem_req),
    .we   (bus_dmem_we),
    .addr (bus_dmem_addr),
    .wdata(bus_dmem_wdata),
    .wstrb(bus_dmem_wstrb),
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

endmodule
