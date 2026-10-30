`timescale 1ns/1ps

/**
 * ============================================================================
 * Module: riscv_cnn_soc_fpga_top
 * Description: Physical FPGA Board-Level Top Wrapper for the Integrated
 *              RISC-V RV32I Processor + INT8 CNN Accelerator SoC.
 * Target Platform: Digilent Nexys A7-100T (AMD/Xilinx Artix-7 xc7a100tcsg324-1)
 * ============================================================================
 * Hardware Features:
 *   - 100 MHz oscillator input with 2-stage meta-stability reset synchronizer.
 *   - Push-button debouncing & single-cycle trigger generation (BTNC).
 *   - Slide switch configuration (SW[0]: 0=Deterministic 3-Layer Test, 1=MNIST).
 *   - Diagnostic LED status panel:
 *       * LED[3:0]   : Predicted Class / Result Nibble (Digits 0 - 9)
 *       * LED[4]     : Inference Done flag
 *       * LED[5]     : Evaluation Pass / Success flag
 *       * LED[6]     : Accelerator / DMA IRQ flag (accel_irq_out)
 *       * LED[7]     : SoC FSM Active / Busy flag
 *       * LED[14:8]  : Status / Winning Score lower bits
 *       * LED[15]    : 1.49 Hz Heartbeat Blink
 *   - Hardware UART Serializer (115200 baud, 8-N-1) streaming results to USB-UART.
 * ============================================================================
 */

module riscv_cnn_soc_fpga_top #(
  parameter IMEM_INIT_FILE = "software/asm/soc_cnn_inference.hex",
  parameter DMEM_INIT_FILE = ""
) (
  input  logic        clk_100mhz,
  input  logic        cpu_resetn,

  // User Interactive Controls
  input  logic        btn_trigger,    // Center button (BTNC)
  input  logic [3:0]  sw,             // Slide switches SW[3:0]

  // Status and Diagnostic LEDs
  output logic [15:0] led,

  // Serial UART Interface (Connected to FTDI USB-UART Bridge)
  input  logic        uart_rx,        // FPGA RX (FTDI TX)
  output logic        uart_tx         // FPGA TX (FTDI RX)
);

  // ---------------------------------------------------------------------------
  // 1. Two-Stage Reset Synchronizer (Active-Low rst_n)
  // ---------------------------------------------------------------------------
  logic rst_sync_0, sync_rst_n;

  always_ff @(posedge clk_100mhz or negedge cpu_resetn) begin
    if (!cpu_resetn) begin
      rst_sync_0 <= 1'b0;
      sync_rst_n <= 1'b0;
    end else begin
      rst_sync_0 <= 1'b1;
      sync_rst_n <= rst_sync_0;
    end
  end

  // ---------------------------------------------------------------------------
  // 2. Heartbeat Indicator (~1.49 Hz at 100 MHz clock)
  // ---------------------------------------------------------------------------
  logic [25:0] heartbeat_cnt;

  always_ff @(posedge clk_100mhz or negedge sync_rst_n) begin
    if (!sync_rst_n) begin
      heartbeat_cnt <= 26'd0;
    end else begin
      heartbeat_cnt <= heartbeat_cnt + 26'd1;
    end
  end

  wire heartbeat = heartbeat_cnt[25];

  // ---------------------------------------------------------------------------
  // 3. Pushbutton Synchronizer & Edge Detector (BTNC)
  // ---------------------------------------------------------------------------
  logic btn_sync_0, btn_sync_1, btn_prev;
  wire  btn_pulse;

  always_ff @(posedge clk_100mhz or negedge sync_rst_n) begin
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
  // 4. Host Interface Controller FSM
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    ST_BOOT_WAIT = 3'd0,
    ST_IDLE      = 3'd1,
    ST_REQ       = 3'd2,
    ST_WAIT_ACK  = 3'd3,
    ST_WAIT_DONE = 3'd4,
    ST_EVAL      = 3'd5,
    ST_SEND_UART = 3'd6
  } host_state_e;

  host_state_e state;
  logic [6:0]  boot_timer;

  logic        ext_host_req;
  logic [7:0]  ext_host_cmd;
  logic [31:0] ext_host_op_a;
  logic [31:0] ext_host_op_b;
  wire         ext_host_done;
  wire  [31:0] ext_host_result;
  wire  [31:0] ext_host_result_hi;
  wire  [31:0] ext_host_status;
  wire         accel_irq_out;

  logic [31:0] reg_result;
  logic [31:0] reg_status;
  logic        reg_done;
  logic        reg_pass;
  logic        reg_busy;
  logic        uart_start;

  always_ff @(posedge clk_100mhz or negedge sync_rst_n) begin
    if (!sync_rst_n) begin
      state         <= ST_BOOT_WAIT;
      boot_timer    <= 7'd0;
      ext_host_req  <= 1'b0;
      ext_host_cmd  <= 8'd0;
      ext_host_op_a <= 32'd0;
      ext_host_op_b <= 32'd0;
      reg_result    <= 32'd0;
      reg_status    <= 32'd0;
      reg_done      <= 1'b0;
      reg_pass      <= 1'b0;
      reg_busy      <= 1'b0;
      uart_start    <= 1'b0;
    end else begin
      uart_start <= 1'b0;

      case (state)
        ST_BOOT_WAIT: begin
          // Wait 64 cycles after reset release for clean pipeline initialization
          if (boot_timer == 7'd64) begin
            state <= ST_IDLE;
          end else begin
            boot_timer <= boot_timer + 7'd1;
          end
        end

        ST_IDLE: begin
          reg_busy <= 1'b0;
          if (btn_pulse) begin
            reg_busy <= 1'b1;
            reg_done <= 1'b0;
            reg_pass <= 1'b0;
            state    <= ST_REQ;
          end
        end

        ST_REQ: begin
          ext_host_req <= 1'b1;
          // SW[0] selects mode: 0 = Small 3-Layer Workload (CMD=2), 1 = MNIST Inference (CMD=1)
          ext_host_cmd  <= sw[0] ? 8'd1 : 8'd2;
          ext_host_op_a <= {28'd0, sw};
          ext_host_op_b <= 32'd0;
          state         <= ST_WAIT_ACK;
        end

        ST_WAIT_ACK: begin
          ext_host_req <= 1'b0;
          if (!ext_host_done) begin
            state <= ST_WAIT_DONE;
          end
        end

        ST_WAIT_DONE: begin
          if (ext_host_done) begin
            state <= ST_EVAL;
          end
        end

        ST_EVAL: begin
          reg_done   <= 1'b1;
          reg_result <= ext_host_result;
          reg_status <= ext_host_status;

          if (ext_host_cmd == 8'd2) begin
            // Deterministic 3-layer test returns 0x50084607
            reg_pass <= (ext_host_result == 32'h50084607);
          end else begin
            // MNIST inference returns winning class in [0, 9] with positive score
            reg_pass <= (ext_host_result <= 32'd9) && (ext_host_status > 32'd0);
          end

          uart_start <= 1'b1;
          state      <= ST_SEND_UART;
        end

        ST_SEND_UART: begin
          state <= ST_IDLE;
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // 5. LED Output Mapping
  // ---------------------------------------------------------------------------
  assign led[3:0]   = reg_result[3:0];       // Predicted class (0-9)
  assign led[4]     = reg_done;              // Completed flag
  assign led[5]     = reg_pass;              // Success / pass flag
  assign led[6]     = accel_irq_out;         // Combined Accel + DMA interrupt
  assign led[7]     = reg_busy;              // Active inference flag
  assign led[14:8]  = reg_status[6:0];       // Lower 7 bits of winning score
  assign led[15]    = heartbeat;             // Blinking alive signal

  // ---------------------------------------------------------------------------
  // 6. Integrated RISC-V + INT8 CNN SoC Core Instance
  // ---------------------------------------------------------------------------
  riscv_cnn_soc_top #(
    .IMEM_INIT_FILE(IMEM_INIT_FILE),
    .DMEM_INIT_FILE(DMEM_INIT_FILE)
  ) u_soc_top (
    .clk              (clk_100mhz),
    .rst_n            (sync_rst_n),

    .ext_host_req     (ext_host_req),
    .ext_host_cmd     (ext_host_cmd),
    .ext_host_op_a    (ext_host_op_a),
    .ext_host_op_b    (ext_host_op_b),
    .ext_host_done    (ext_host_done),
    .ext_host_result  (ext_host_result),
    .ext_host_result_hi(ext_host_result_hi),
    .ext_host_status  (ext_host_status),

    .ext_imem_we      (1'b0),
    .ext_imem_waddr   (32'd0),
    .ext_imem_wdata   (32'd0),
    .ext_imem_wstrb   (4'd0),

    .debug_wb_pc      (),
    .debug_wb_rd      (),
    .debug_wb_data    (),
    .debug_wb_valid   (),
    .accel_irq_out    (accel_irq_out)
  );

  // ---------------------------------------------------------------------------
  // 7. Hardware UART Transmitter (115200 Baud @ 100 MHz, 8-N-1)
  // ---------------------------------------------------------------------------
  // 100,000,000 Hz / 115,200 baud = 868 clock cycles per bit
  localparam int BAUD_DIV = 868;

  logic [9:0]  baud_cnt;
  logic        baud_tick;
  logic [3:0]  tx_bit_idx;
  logic [9:0]  tx_shift_reg;
  logic        tx_busy;

  // Formatted ASCII message: "CLASS: X\r\n"
  logic [7:0]  current_char;
  logic [3:0]  msg_idx;
  logic        msg_active;

  always_comb begin
    case (msg_idx)
      4'd0: current_char = "C";
      4'd1: current_char = "L";
      4'd2: current_char = "A";
      4'd3: current_char = "S";
      4'd4: current_char = "S";
      4'd5: current_char = ":";
      4'd6: current_char = " ";
      4'd7: current_char = 8'h30 + {4'd0, reg_result[3:0]};
      4'd8: current_char = 8'h0D;
      4'd9: current_char = 8'h0A;
      default: current_char = 8'h20;
    endcase
  end

  // Baud rate generator
  always_ff @(posedge clk_100mhz or negedge sync_rst_n) begin
    if (!sync_rst_n) begin
      baud_cnt  <= 10'd0;
      baud_tick <= 1'b0;
    end else begin
      if (baud_cnt == (BAUD_DIV - 1)) begin
        baud_cnt  <= 10'd0;
        baud_tick <= 1'b1;
      end else begin
        baud_cnt  <= baud_cnt + 10'd1;
        baud_tick <= 1'b0;
      end
    end
  end

  // Byte serializer state machine
  always_ff @(posedge clk_100mhz or negedge sync_rst_n) begin
    if (!sync_rst_n) begin
      tx_shift_reg <= 10'b1111111111;
      tx_bit_idx   <= 4'd0;
      tx_busy      <= 1'b0;
      msg_idx      <= 4'd0;
      msg_active   <= 1'b0;
    end else begin
      if (uart_start && !msg_active) begin
        msg_active <= 1'b1;
        msg_idx    <= 4'd0;
      end

      if (msg_active && !tx_busy) begin
        // Load next character: 1 start bit (0), 8 data bits, 1 stop bit (1)
        tx_shift_reg <= {1'b1, current_char, 1'b0};
        tx_bit_idx   <= 4'd10;
        tx_busy      <= 1'b1;

        if (msg_idx == 4'd9) begin
          msg_active <= 1'b0;
        end else begin
          msg_idx <= msg_idx + 4'd1;
        end
      end else if (tx_busy && baud_tick) begin
        tx_shift_reg <= {1'b1, tx_shift_reg[9:1]};
        tx_bit_idx   <= tx_bit_idx - 4'd1;
        if (tx_bit_idx == 4'd1) begin
          tx_busy <= 1'b0;
        end
      end
    end
  end

  assign uart_tx = tx_shift_reg[0];

endmodule
