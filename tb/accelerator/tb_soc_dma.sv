`timescale 1ns/1ps

module tb_soc_dma;

  logic clk = 0;
  logic rst_n = 0;

  always #5 clk = ~clk;

  // Slave Port
  logic        s_req = 0;
  logic        s_we = 0;
  logic [7:0]  s_addr = 0;
  logic [31:0] s_wdata = 0;
  logic [31:0] s_rdata;
  logic        s_stall;

  // Master Memory Port
  logic        m_mem_req;
  logic [31:0] m_mem_addr;
  logic [31:0] m_mem_rdata;

  // Master Accel Port
  logic        m_accel_req;
  logic        m_accel_we;
  logic [7:0]  m_accel_addr;
  logic [31:0] m_accel_wdata;
  logic [3:0]  m_accel_wstrb;
  logic        m_accel_stall = 0;

  // Interrupts
  logic        dma_irq;
  logic        dma_busy;

  // Mock DMEM (512 words)
  logic [31:0] mock_dmem [0:511];

  // Mock Accelerator Memory (1024 bytes)
  logic [7:0]  mock_accel_sram [0:1023];
  logic [1:0]  last_wr_sel;
  logic [13:0] mock_accel_addr = 0;
  integer bytes_received = 0;

  soc_dma dut (
    .clk          (clk),
    .rst_n        (rst_n),
    .s_req        (s_req),
    .s_we         (s_we),
    .s_addr       (s_addr),
    .s_wdata      (s_wdata),
    .s_rdata      (s_rdata),
    .s_stall      (s_stall),
    .m_mem_req    (m_mem_req),
    .m_mem_addr   (m_mem_addr),
    .m_mem_rdata  (m_mem_rdata),
    .m_accel_req  (m_accel_req),
    .m_accel_we   (m_accel_we),
    .m_accel_addr (m_accel_addr),
    .m_accel_wdata(m_accel_wdata),
    .m_accel_wstrb(m_accel_wstrb),
    .m_accel_stall(m_accel_stall),
    .dma_irq      (dma_irq),
    .dma_busy     (dma_busy)
  );

  // Combinational DMEM read
  assign m_mem_rdata = m_mem_req ? mock_dmem[(m_mem_addr - 32'h0000_5000) >> 2] : 32'h0;

  // Mock Accelerator logic (reflecting accel_top auto-increment and dma_wr_sel)
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mock_accel_addr <= 14'h0;
      bytes_received  <= 0;
    end else begin
      if (m_accel_req && m_accel_we && !m_accel_stall) begin
        if (m_accel_addr == 8'h10) begin
          mock_accel_addr <= m_accel_wdata[13:0];
        end else if (m_accel_addr == 8'h14) begin
          last_wr_sel <= m_accel_wdata[9:8];
          mock_accel_sram[mock_accel_addr] <= m_accel_wdata[7:0];
          mock_accel_addr <= mock_accel_addr + 1'b1;
          bytes_received  <= bytes_received + 1;
        end
      end
    end
  end

  // Tasks for MMIO
  task mmio_write(input [7:0] addr, input [31:0] data);
    begin
      @(posedge clk);
      s_req   <= 1'b1;
      s_we    <= 1'b1;
      s_addr  <= addr;
      s_wdata <= data;
      @(posedge clk);
      s_req   <= 1'b0;
      s_we    <= 1'b0;
      s_addr  <= 8'h0;
      s_wdata <= 32'h0;
      @(posedge clk);
    end
  endtask

  task mmio_read(input [7:0] addr, output [31:0] data);
    begin
      @(posedge clk);
      s_req   <= 1'b1;
      s_we    <= 1'b0;
      s_addr  <= addr;
      @(posedge clk);
      data    = s_rdata;
      s_req   <= 1'b0;
    end
  endtask

  integer i, cycle_count;
  logic [31:0] rval;
  integer mismatch_count = 0;

  initial begin
    // Initialize mock DMEM with 196 words = 784 bytes (MNIST test vector layout)
    for (i = 0; i < 196; i = i + 1) begin
      mock_dmem[i] = {8'(((4*i + 3) & 8'hFF)), 8'(((4*i + 2) & 8'hFF)), 8'(((4*i + 1) & 8'hFF)), 8'(((4*i + 0) & 8'hFF))};
    end
    for (i = 0; i < 1024; i = i + 1) begin
      mock_accel_sram[i] = 8'h00;
    end

    // Reset
    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);

    $display("=================================================================");
    $display("[TEST 1] Testing DMA Register Read / Write & Default Config");
    $display("=================================================================");

    mmio_read(8'h00, rval);
    if (rval !== 32'h0000_5000) $fatal(1, "FAIL: Default SRC_ADDR mismatch, expected 0x5000, got 0x%08x", rval);

    mmio_read(8'h04, rval);
    if (rval !== 32'h0000_0000) $fatal(1, "FAIL: Default DST_ADDR mismatch, expected 0x0, got 0x%08x", rval);

    mmio_read(8'h08, rval);
    if (rval !== 32'd196) $fatal(1, "FAIL: Default LEN_WORDS mismatch, expected 196, got %0d", rval);

    // Configure for 196 words from 0x5000 to 0x0000, WR_SEL=2'b01 (feature buffer)
    mmio_write(8'h00, 32'h0000_5000);
    mmio_write(8'h04, 32'h0000_0000);
    mmio_write(8'h08, 32'd196);

    $display("PASS: MMIO configuration registers verified successfully.");

    $display("=================================================================");
    $display("[TEST 2] Starting Autonomous Streaming DMA Transfer (196 Words -> 784 Bytes)");
    $display("=================================================================");

    cycle_count = 0;
    // Write START=1, IRQ_EN=1, WR_SEL=01 (feature buffer) -> 0x19
    mmio_write(8'h0C, 32'h0000_0019);

    while (dma_busy && cycle_count < 5000) begin
      @(posedge clk);
      cycle_count = cycle_count + 1;
    end

    if (cycle_count >= 5000) begin
      $fatal(1, "FAIL: DMA transfer timed out after %0d cycles!", cycle_count);
    end

    $display("DMA transfer completed in %0d clock cycles!", cycle_count);
    $display("Total bytes received by accelerator: %0d (Expected: 784)", bytes_received);

    if (bytes_received != 784) begin
      $fatal(1, "FAIL: Expected 784 bytes, but received %0d!", bytes_received);
    end

    if (last_wr_sel !== 2'b01) begin
      $fatal(1, "FAIL: Expected WR_SEL=2'b01 (feature buffer), got %0b!", last_wr_sel);
    end

    // Verify all 784 unpacked bytes match exactly
    for (i = 0; i < 784; i = i + 1) begin
      logic [7:0] exp_byte;
      exp_byte = i & 8'hFF;
      if (mock_accel_sram[i] !== exp_byte) begin
        $display("[MISMATCH] Byte %0d: Expected 0x%02x, Got 0x%02x", i, exp_byte, mock_accel_sram[i]);
        mismatch_count = mismatch_count + 1;
      end
    end

    if (mismatch_count != 0) begin
      $fatal(1, "FAIL: %0d byte mismatches detected!", mismatch_count);
    end

    $display("PASS: 100 percent of 784 unpacked bytes match bit-exact with correct buffer bank selection!");

    $display("=================================================================");
    $display("[TEST 3] Verifying IRQ, Status Register & Clear Handshake");
    $display("=================================================================");

    if (!dma_irq) $fatal(1, "FAIL: dma_irq was not asserted upon completion!");

    mmio_read(8'h0C, rval);
    if ((rval & 32'h0000_0004) == 0) $fatal(1, "FAIL: DONE bit not set in status register! Got 0x%08x", rval);

    // Clear DONE bit
    mmio_write(8'h0C, 32'h0000_0004);
    mmio_read(8'h0C, rval);
    if ((rval & 32'h0000_0004) != 0) $fatal(1, "FAIL: DONE bit failed to clear!");

    $display("PASS: IRQ and DONE clear handshake verified.");
    $display("=================================================================");
    $display("ALL SOC DMA TESTS PASSED CLEANLY! (100 percent SUCCESS)");
    $display("=================================================================");

    repeat (10) @(posedge clk);
    $finish(0);
  end

endmodule
