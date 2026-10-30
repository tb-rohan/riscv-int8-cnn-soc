`timescale 1ns/1ps

module tb_cpu_interactive;

  logic clk = 0;
  logic rst_n = 0;

  always #5 clk = ~clk;

  logic        ext_host_req = 0;
  logic [7:0]  ext_host_cmd = 0;
  logic [31:0] ext_host_op_a = 0;
  logic [31:0] ext_host_op_b = 0;
  logic        ext_host_done;
  logic [31:0] ext_host_result;
  logic [31:0] ext_host_result_hi;
  logic [31:0] ext_host_status;

  logic [31:0] debug_wb_pc;
  logic [4:0]  debug_wb_rd;
  logic [31:0] debug_wb_data;
  logic        debug_wb_valid;

  cpu_standalone_top dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .ext_host_req     (ext_host_req),
    .ext_host_cmd     (ext_host_cmd),
    .ext_host_op_a    (ext_host_op_a),
    .ext_host_op_b    (ext_host_op_b),
    .ext_host_done    (ext_host_done),
    .ext_host_result  (ext_host_result),
    .ext_host_result_hi(ext_host_result_hi),
    .ext_host_status  (ext_host_status),
    .ext_imem_we      (1'b0),
    .ext_imem_waddr   (32'h0),
    .ext_imem_wdata   (32'h0),
    .ext_imem_wstrb   (4'h0),
    .debug_wb_pc      (debug_wb_pc),
    .debug_wb_rd      (debug_wb_rd),
    .debug_wb_data    (debug_wb_data),
    .debug_wb_valid   (debug_wb_valid)
  );

  integer cmd_val;
  integer op_a_val;
  integer op_b_val;
  integer timeout_val;
  integer cycle_count;
  string  hex_file;
  string  vcd_file;

  initial begin
    timeout_val = 200000;
    if ($value$plusargs("TIMEOUT=%d", timeout_val)) begin end

    if ($value$plusargs("VCD=%s", vcd_file)) begin
      $dumpfile(vcd_file);
      $dumpvars(0, tb_cpu_interactive);
    end

    if ($value$plusargs("HEX=%s", hex_file)) begin
      $readmemh(hex_file, dut.u_imem.mem);
    end else begin
      $readmemh("software/asm/interactive_cpu.hex", dut.u_imem.mem);
    end

    cmd_val  = 1;
    op_a_val = 0;
    op_b_val = 0;
    if ($value$plusargs("CMD=%d", cmd_val)) begin end
    if ($value$plusargs("OP_A=%d", op_a_val)) begin end
    if ($value$plusargs("OP_B=%d", op_b_val)) begin end

    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (10) @(posedge clk);

    @(posedge clk);
    ext_host_req  <= 1'b1;
    ext_host_cmd  <= cmd_val[7:0];
    ext_host_op_a <= op_a_val;
    ext_host_op_b <= op_b_val;

    @(posedge clk);
    ext_host_req  <= 1'b0;

    cycle_count = 0;
    while (!ext_host_done && cycle_count < timeout_val) begin
      @(posedge clk);
      cycle_count = cycle_count + 1;
    end

    if (cycle_count >= timeout_val) begin
      $display("[TB ERROR] CPU timed out after %0d cycles!", cycle_count);
      $display("LAST_PC=0x%08x", dut.u_core.pc_q);
      $finish(1);
    end

    $display("CPU_RESULT_DEC=%0d", $signed(ext_host_result));
    $display("CPU_RESULT_HEX=0x%08x", ext_host_result);
    $display("CPU_RESULT_HI_DEC=%0d", $signed(ext_host_result_hi));
    $display("CPU_RESULT_HI_HEX=0x%08x", ext_host_result_hi);
    $display("CPU_CYCLES=%0d", ext_host_status);
    $display("CPU_STATUS=PASS");

    for (int r = 0; r < 32; r = r + 1) begin
      if (r == 0)
        $display("REG[0]=0x00000000");
      else
        $display("REG[%0d]=0x%08x", r, dut.u_core.u_regfile.regs[r]);
    end
    $display("FINAL_PC=0x%08x", dut.u_core.pc_q);
    $display("INSTRET=%0d", dut.u_timer.instret);
    $display("LOAD_USE_STALLS=%0d", dut.u_timer.load_use_stalls);
    $display("BRANCH_FLUSHES=%0d", dut.u_timer.branch_flushes);
    $display("BUS_STALLS=%0d", dut.u_timer.bus_stalls);

    repeat (4) @(posedge clk);
    $finish(0);
  end

endmodule
