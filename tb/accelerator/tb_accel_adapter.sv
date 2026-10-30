`timescale 1ns/1ps

module tb_accel_adapter;

  logic clk = 0;
  logic rst_n = 0;

  always #5 clk = ~clk;

  logic        req = 0;
  logic        we = 0;
  logic [31:0] addr = 0;
  logic [31:0] wdata = 0;
  logic [3:0]  wstrb = 0;
  logic [31:0] rdata;
  logic        stall;

  logic [7:0]  awaddr;
  logic        awvalid, awready;
  logic [31:0] wdata_axi;
  logic [3:0]  wstrb_axi;
  logic        wvalid, wready;
  logic [1:0]  bresp;
  logic        bvalid, bready;

  logic [7:0]  araddr;
  logic        arvalid, arready;
  logic [31:0] rdata_axi;
  logic [1:0]  rresp;
  logic        rvalid, rready;
  wire         accel_irq;

  // Intercept signals for watchdog fault injection
  logic force_slave_hang = 0;
  logic slave_awready, slave_wready, slave_arready, slave_rvalid, slave_bvalid;

  assign awready = force_slave_hang ? 1'b0 : slave_awready;
  assign wready  = force_slave_hang ? 1'b0 : slave_wready;
  assign arready = force_slave_hang ? 1'b0 : slave_arready;
  assign rvalid  = force_slave_hang ? 1'b0 : slave_rvalid;
  assign bvalid  = force_slave_hang ? 1'b0 : slave_bvalid;

  accel_adapter #(
    .WATCHDOG_LIMIT(50)
  ) u_adapter (
    .clk           (clk),
    .rst_n         (rst_n),
    .req           (req),
    .we            (we),
    .addr          (addr),
    .wdata         (wdata),
    .wstrb         (wstrb),
    .rdata         (rdata),
    .stall         (stall),

    .m_axil_awaddr (awaddr),
    .m_axil_awvalid(awvalid),
    .m_axil_awready(awready),
    .m_axil_wdata  (wdata_axi),
    .m_axil_wstrb  (wstrb_axi),
    .m_axil_wvalid (wvalid),
    .m_axil_wready (wready),
    .m_axil_bresp  (bresp),
    .m_axil_bvalid (bvalid),
    .m_axil_bready (bready),

    .m_axil_araddr (araddr),
    .m_axil_arvalid(arvalid),
    .m_axil_arready(arready),
    .m_axil_rdata  (rdata_axi),
    .m_axil_rresp  (rresp),
    .m_axil_rvalid (rvalid),
    .m_axil_rready (rready),

    .accel_irq     (accel_irq),
    .irq_status    ()
  );

  accel_top u_accel (
    .clk           (clk),
    .rst_n         (rst_n),
    .s_axil_awaddr (awaddr),
    .s_axil_awvalid(awvalid),
    .s_axil_awready(slave_awready),
    .s_axil_wdata  (wdata_axi),
    .s_axil_wstrb  (wstrb_axi),
    .s_axil_wvalid (wvalid),
    .s_axil_wready (slave_wready),
    .s_axil_bresp  (bresp),
    .s_axil_bvalid (slave_bvalid),
    .s_axil_bready (bready),

    .s_axil_araddr (araddr),
    .s_axil_arvalid(arvalid),
    .s_axil_arready(slave_arready),
    .s_axil_rdata  (rdata_axi),
    .s_axil_rresp  (rresp),
    .s_axil_rvalid (slave_rvalid),
    .s_axil_rready (rready),
    .irq           (accel_irq)
  );

  task automatic bus_write(input logic [31:0] write_addr, input logic [31:0] write_val);
    begin
      @(posedge clk);
      req   <= 1'b1;
      we    <= 1'b1;
      addr  <= write_addr;
      wdata <= write_val;
      wstrb <= 4'hF;
      @(posedge clk);
      while (stall) @(posedge clk);
      req   <= 1'b0;
      we    <= 1'b0;
      wstrb <= 4'h0;
    end
  endtask

  task automatic bus_read(input logic [31:0] read_addr, output logic [31:0] read_val);
    begin
      @(posedge clk);
      req   <= 1'b1;
      we    <= 1'b0;
      addr  <= read_addr;
      @(posedge clk);
      while (stall) @(posedge clk);
      read_val = rdata;
      req   <= 1'b0;
    end
  endtask

  logic [31:0] read_val;

  initial begin
    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);

    // 1. Verify CTRL register
    bus_write(32'h8000_1000, 32'h0000_0002);
    bus_read(32'h8000_1000, read_val);
    if (read_val[1] !== 1'b1) $fatal(1, "CTRL register readback failed: 0x%08x", read_val);

    // 2. Verify Capability Register 0x08
    bus_read(32'h8000_1008, read_val);
    if (read_val !== 32'h01040408) $fatal(1, "Capability register 0x08 failed: got 0x%08x expected 0x01040408", read_val);

    // 3. Verify Adapter Status Register 0x0C Initial Reset State
    bus_read(32'h8000_100C, read_val);
    if (read_val[0] !== 1'b0) $fatal(1, "ADAPTER_STATUS timeout_err bit should reset to 0: 0x%08x", read_val);

    // 4. Verify DMA address and autoincrement
    bus_write(32'h8000_1010, 32'h0000_0055);
    bus_read(32'h8000_1010, read_val);
    if (read_val[13:0] !== 14'h0055) $fatal(1, "DMA_ADDR readback failed: 0x%08x", read_val);

    bus_write(32'h8000_1014, 32'h0000_01AA);
    bus_read(32'h8000_1010, read_val);
    if (read_val[13:0] !== 14'h0056) $fatal(1, "DMA_ADDR autoincrement failed: 0x%08x", read_val);

    // 5. Verify Instruction registers
    bus_write(32'h8000_1020, 32'h11223344);
    bus_write(32'h8000_1024, 32'h55667788);
    bus_write(32'h8000_1028, 32'h99AABBCC);
    bus_write(32'h8000_102C, 32'hDDEEFF00);
    bus_read(32'h8000_1020, read_val);
    if (read_val !== 32'h11223344) $fatal(1, "INSTR_W0 mismatch: 0x%08x", read_val);
    bus_read(32'h8000_1024, read_val);
    if (read_val !== 32'h55667788) $fatal(1, "INSTR_W1 mismatch: 0x%08x", read_val);

    // 6. Watchdog Timeout & Abort Test (Fault Injection)
    force_slave_hang = 1'b1;
    bus_read(32'h8000_1000, read_val);
    if (read_val !== 32'hDEAD_DEAD) $fatal(1, "Watchdog timeout abort expected 0xDEAD_DEAD, got 0x%08x", read_val);
    force_slave_hang = 1'b0;

    // 7. Verify ADAPTER_STATUS reports timeout_err = 1
    bus_read(32'h8000_100C, read_val);
    if (read_val[0] !== 1'b1) $fatal(1, "ADAPTER_STATUS should reflect timeout_err=1 after watchdog trip: 0x%08x", read_val);

    // 8. Test Write-1-to-Clear (W1C) on ADAPTER_STATUS
    bus_write(32'h8000_100C, 32'h0000_0001);
    bus_read(32'h8000_100C, read_val);
    if (read_val[0] !== 1'b0) $fatal(1, "ADAPTER_STATUS W1C failed, timeout_err still high: 0x%08x", read_val);

    $display("PASS: Accelerator Adapter AXI4-Lite translation, capability register, watchdog timeout abort, and W1C status verified!");
    $finish(0);
  end

endmodule
