`timescale 1ns/1ps

module tb_riscv_cnn_soc;

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
  wire         accel_irq_out;

  riscv_cnn_soc_top dut (
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
    .debug_wb_valid   (debug_wb_valid),
    .accel_irq_out    (accel_irq_out)
  );

  logic prev_done = 0;
  always @(posedge clk) begin
    if (dut.u_accel.start_pulse) begin
      $display("[ACCEL] Hardware accelerator started execution @ %0t", $time);
    end
    if (dut.u_accel.done && !prev_done) begin
      $display("[ACCEL] Hardware accelerator finished (done asserted) @ %0t", $time);
    end
    prev_done <= dut.u_accel.done;
    if (dut.u_accel.err) begin
      $display("[ACCEL ERR] Error flag asserted @ %0t", $time);
    end
  end

  integer cmd_val;
  integer timeout_val;
  integer cycle_count;
  string  image_hex_file;
  string  weights_hex_file;
  string  biases_hex_file;
  string  instr_hex_file;
  string  vcd_file;

  logic [31:0]  batch_weights [0:1391];
  logic [127:0] batch_biases [0:6];
  logic [127:0] batch_instructions [0:5];
  logic [31:0]  image_words [0:783];
  integer w_idx, b_idx, i;

  initial begin
    timeout_val = 500000;
    if ($value$plusargs("TIMEOUT=%d", timeout_val)) begin end

    if ($value$plusargs("VCD=%s", vcd_file)) begin
      $dumpfile(vcd_file);
      $dumpvars(0, tb_riscv_cnn_soc);
    end

    $readmemh("software/asm/soc_cnn_inference.hex", dut.u_imem.mem);

    cmd_val = 2;
    if ($value$plusargs("CMD=%d", cmd_val)) begin end

    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (10) @(posedge clk);

    for (i = 0; i < 4096; i = i + 1) begin
      dut.u_accel.memory.weights[i] = 0;
      dut.u_accel.memory.feature_a[i] = 0;
      dut.u_accel.memory.feature_b[i] = 0;
    end
    for (i = 0; i < 256; i = i + 1)
      dut.u_accel.memory.biases[i] = 0;
    for (i = 0; i < 64; i = i + 1)
      dut.u_accel.control.instruction_mem[i] = 0;

    if (cmd_val == 1) begin
      weights_hex_file = "../INT8/vectors/smoke/weights.hex";
      biases_hex_file  = "../INT8/vectors/smoke/biases.hex";
      instr_hex_file   = "../INT8/vectors/smoke/instructions.hex";
      if ($value$plusargs("WEIGHTS_HEX=%s", weights_hex_file)) begin end
      if ($value$plusargs("BIASES_HEX=%s", biases_hex_file)) begin end
      if ($value$plusargs("INSTR_HEX=%s", instr_hex_file)) begin end

      $readmemh(weights_hex_file, batch_weights);
      $readmemh(biases_hex_file, batch_biases);
      $readmemh(instr_hex_file, batch_instructions);

      for (w_idx = 0; w_idx < 1392; w_idx = w_idx + 1) begin
        dut.u_accel.memory.weights[w_idx] = batch_weights[w_idx];
      end

      for (b_idx = 0; b_idx < 7; b_idx = b_idx + 1) begin
        dut.u_accel.memory.biases[b_idx] = batch_biases[b_idx];
      end

      for (i = 0; i < 6; i = i + 1) begin
        dut.u_accel.control.instruction_mem[i] = batch_instructions[i];
      end

      for (i = 0; i < 4096; i = i + 1) begin
        dut.u_dmem.u_ram.mem[i] = 0;
      end

      if ($value$plusargs("IMAGE_HEX=%s", image_hex_file)) begin
        $readmemh(image_hex_file, image_words);
        for (i = 0; i < 784; i = i + 1) begin
          dut.u_dmem.u_ram.mem[((16'h5000 & 16'h3FFF) >> 2) + i] = image_words[i];
        end
      end
    end

    @(posedge clk);
    ext_host_req  <= 1'b1;
    ext_host_cmd  <= cmd_val[7:0];
    ext_host_op_a <= 32'h0;
    ext_host_op_b <= 32'h0;

    @(posedge clk);
    ext_host_req  <= 1'b0;

    cycle_count = 0;
    while (!ext_host_done && cycle_count < timeout_val) begin
      @(posedge clk);
      cycle_count = cycle_count + 1;
    end

    if (cycle_count >= timeout_val) begin
      $display("[TB ERROR] SoC inference timed out after %0d cycles!", cycle_count);
      $display("LAST_PC=0x%08x, ACCEL_BUSY=%b, ACCEL_DONE=%b, ACCEL_ERR=%b",
               dut.u_core.pc_q, dut.u_accel.busy, dut.u_accel.done, dut.u_accel.err);
      $finish(1);
    end

    $display("SOC_RESULT_DEC=%0d", $signed(ext_host_result));
    $display("SOC_RESULT_HEX=0x%08x", ext_host_result);
    $display("SOC_WINNING_SCORE=%0d", $signed(ext_host_result_hi));
    $display("SOC_CYCLES=%0d", ext_host_status);

    if (cmd_val == 2) begin
      if (ext_host_result == 32'h50084607) begin
        $display("SOC_STATUS=PASS");
        $display("PASS: Integrated SoC executed small CNN workload and verified output bytes [7, 70, 8, 80]!");
      end else begin
        $display("SOC_STATUS=FAIL");
        $display("FAIL: Output mismatch, got 0x%08x, expected 0x50084607", ext_host_result);
      end
    end else begin
      $display("SOC_STATUS=PASS");
      $display("PASS: Integrated SoC completed CNN inference! Predicted Class = %0d, Score = %0d",
               ext_host_result, $signed(ext_host_result_hi));
      for (i = 0; i < 10; i = i + 1) begin
        $display("LOGIT[%0d]=%0d", i, $signed(dut.u_dmem.u_ram.mem[((16'h7000 & 16'h3FFF) >> 2) + i]));
      end
    end

    repeat (10) @(posedge clk);
    $finish(0);
  end

endmodule
