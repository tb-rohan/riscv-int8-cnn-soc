`timescale 1ns/1ps

module cpu_fpga_top #(
  parameter IMEM_INIT_FILE = "software/asm/interactive_cpu.hex",
  parameter DMEM_INIT_FILE = ""
) (
  input  logic        clk,
  input  logic        rst_n,

  // User input controls (debounced push-button and mode switches)
  input  logic        btn_trigger,
  input  logic [1:0]  sw_mode,

  // Status and diagnostic outputs
  output logic [7:0]  led,
  output logic        led_done,
  output logic        led_pass,
  output logic        led_fail,
  output logic        led_heartbeat
);

  // ---------------------------------------------------------------------------
  // 1. Two-Stage Reset Synchronizer (Meta-stability Hardening)
  // ---------------------------------------------------------------------------
  logic rst_sync_m, sync_rst_n;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rst_sync_m <= 1'b0;
      sync_rst_n <= 1'b0;
    end else begin
      rst_sync_m <= 1'b1;
      sync_rst_n <= rst_sync_m;
    end
  end

  // ---------------------------------------------------------------------------
  // 2. Heartbeat Indicator (Blinks at ~1.5 Hz @ 100 MHz clock)
  // ---------------------------------------------------------------------------
  logic [25:0] heartbeat_cnt;

  always_ff @(posedge clk or negedge sync_rst_n) begin
    if (!sync_rst_n) begin
      heartbeat_cnt <= 26'd0;
    end else begin
      heartbeat_cnt <= heartbeat_cnt + 26'd1;
    end
  end

  assign led_heartbeat = heartbeat_cnt[25];

  // ---------------------------------------------------------------------------
  // 3. Button Edge Detector for Re-triggering
  // ---------------------------------------------------------------------------
  logic btn_sync_0, btn_sync_1, btn_prev;
  wire  btn_pulse;

  always_ff @(posedge clk or negedge sync_rst_n) begin
    if (!sync_rst_n) begin
      btn_sync_0 <= 1'b0;
      btn_sync_1 <= 1'b0;
      btn_prev   <= 1'b0;
    end else begin
      btn_sync_0 <= btn_trigger;
      btn_sync_1 <= btn_sync_0;
      btn_prev   <= btn_sync_1;
    end
  end

  assign btn_pulse = btn_sync_1 && !btn_prev;

  // ---------------------------------------------------------------------------
  // 4. Standalone Host Controller FSM
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    ST_INIT_WAIT = 3'd0,
    ST_REQ       = 3'd1,
    ST_WAIT_ACK  = 3'd2,
    ST_WAIT_DONE = 3'd3,
    ST_EVAL      = 3'd4,
    ST_IDLE      = 3'd5
  } state_e;

  state_e state;
  logic [5:0]  init_delay_cnt;

  logic        host_req;
  logic [7:0]  host_cmd;
  logic [31:0] host_op_a;
  logic [31:0] host_op_b;
  wire         host_done;
  wire  [31:0] host_result;
  wire  [31:0] host_result_hi;
  wire  [31:0] host_status;

  logic [7:0]  reg_led;
  logic        reg_done;
  logic        reg_pass;
  logic        reg_fail;

  always_ff @(posedge clk or negedge sync_rst_n) begin
    if (!sync_rst_n) begin
      state          <= ST_INIT_WAIT;
      init_delay_cnt <= 6'd0;
      host_req       <= 1'b0;
      host_cmd       <= 8'd0;
      host_op_a      <= 32'd0;
      host_op_b      <= 32'd0;
      reg_led        <= 8'd0;
      reg_done       <= 1'b0;
      reg_pass       <= 1'b0;
      reg_fail       <= 1'b0;
    end else begin
      case (state)
        ST_INIT_WAIT: begin
          // Wait 32 cycles after reset deassertion to ensure clean pipeline startup
          if (init_delay_cnt == 6'd32) begin
            state <= ST_REQ;
          end else begin
            init_delay_cnt <= init_delay_cnt + 6'd1;
          end
        end

        ST_REQ: begin
          host_req <= 1'b1;
          case (sw_mode)
            2'b00: begin
              // Mode 0: Full 37-Instruction RV32I ISA Self-Test
              host_cmd  <= 8'd14;
              host_op_a <= 32'd0;
              host_op_b <= 32'd0;
            end
            2'b01: begin
              // Mode 1: Addition (25 + 17 = 42)
              host_cmd  <= 8'd1;
              host_op_a <= 32'd25;
              host_op_b <= 32'd17;
            end
            2'b10: begin
              // Mode 2: Multiplication (15 * 20 = 300)
              host_cmd  <= 8'd3;
              host_op_a <= 32'd15;
              host_op_b <= 32'd20;
            end
            2'b11: begin
              // Mode 3: Division (100 / 7 -> Q:14, R:2)
              host_cmd  <= 8'd4;
              host_op_a <= 32'd100;
              host_op_b <= 32'd7;
            end
          endcase
          reg_done <= 1'b0;
          reg_pass <= 1'b0;
          reg_fail <= 1'b0;
          state    <= ST_WAIT_ACK;
        end

        ST_WAIT_ACK: begin
          // Hold request for 1 cycle to guarantee host_interface samples ext_req
          // and drops host_done to 0
          host_req <= 1'b0;
          if (!host_done) begin
            state <= ST_WAIT_DONE;
          end
        end

        ST_WAIT_DONE: begin
          if (host_done) begin
            state <= ST_EVAL;
          end
        end

        ST_EVAL: begin
          reg_done <= 1'b1;
          reg_led  <= host_result[7:0];

          case (host_cmd)
            8'd14: begin
              // Full 37-instruction ISA test expected result:
              // Result = 37, Result_HI = 0x50415353 ("PASS")
              if ((host_result == 32'd37) && (host_result_hi == 32'h50415353)) begin
                reg_pass <= 1'b1;
                reg_fail <= 1'b0;
              end else begin
                reg_pass <= 1'b0;
                reg_fail <= 1'b1;
              end
            end

            8'd1: begin
              // Addition expected result: 42
              if (host_result == 32'd42) begin
                reg_pass <= 1'b1;
                reg_fail <= 1'b0;
              end else begin
                reg_pass <= 1'b0;
                reg_fail <= 1'b1;
              end
            end

            8'd3: begin
              // Multiplication expected result: 300
              if (host_result == 32'd300) begin
                reg_pass <= 1'b1;
                reg_fail <= 1'b0;
              end else begin
                reg_pass <= 1'b0;
                reg_fail <= 1'b1;
              end
            end

            8'd4: begin
              // Division expected result: Q=14, R=2
              if ((host_result == 32'd14) && (host_result_hi == 32'd2)) begin
                reg_pass <= 1'b1;
                reg_fail <= 1'b0;
              end else begin
                reg_pass <= 1'b0;
                reg_fail <= 1'b1;
              end
            end

            default: begin
              // For autonomous programs like standalone_boot:
              // Check if Result_HI == 0x50415353 ("PASS")
              if (host_result_hi == 32'h50415353) begin
                reg_pass <= 1'b1;
                reg_fail <= 1'b0;
              end else begin
                reg_pass <= 1'b0;
                reg_fail <= 1'b1;
              end
            end
          endcase

          state <= ST_IDLE;
        end

        ST_IDLE: begin
          // Allow re-trigger via button push
          if (btn_pulse) begin
            state <= ST_REQ;
          end
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

  assign led      = reg_led;
  assign led_done = reg_done;
  assign led_pass = reg_pass;
  assign led_fail = reg_fail;

  // ---------------------------------------------------------------------------
  // 5. Standalone RV32I CPU Core Top Instantiation
  // ---------------------------------------------------------------------------
  wire [31:0] debug_wb_pc;
  wire [4:0]  debug_wb_rd;
  wire [31:0] debug_wb_data;
  wire        debug_wb_valid;

  (* keep = "true" *) logic [31:0] reg_last_wb_pc;
  (* keep = "true" *) logic [31:0] reg_last_wb_data;

  always_ff @(posedge clk or negedge sync_rst_n) begin
    if (!sync_rst_n) begin
      reg_last_wb_pc   <= 32'h0;
      reg_last_wb_data <= 32'h0;
    end else if (debug_wb_valid) begin
      reg_last_wb_pc   <= debug_wb_pc;
      reg_last_wb_data <= debug_wb_data;
    end
  end

  cpu_standalone_top #(
    .IMEM_INIT_FILE(IMEM_INIT_FILE),
    .DMEM_INIT_FILE(DMEM_INIT_FILE)
  ) u_cpu_top (
    .clk               (clk),
    .rst_n             (sync_rst_n),
    .ext_host_req      (host_req),
    .ext_host_cmd      (host_cmd),
    .ext_host_op_a     (host_op_a),
    .ext_host_op_b     (host_op_b),
    .ext_host_done     (host_done),
    .ext_host_result   (host_result),
    .ext_host_result_hi(host_result_hi),
    .ext_host_status   (host_status),
    .ext_imem_we       (1'b0),
    .ext_imem_waddr    (32'h0),
    .ext_imem_wdata    (32'h0),
    .ext_imem_wstrb    (4'h0),
    .debug_wb_pc       (debug_wb_pc),
    .debug_wb_rd       (debug_wb_rd),
    .debug_wb_data     (debug_wb_data),
    .debug_wb_valid    (debug_wb_valid)
  );

endmodule
