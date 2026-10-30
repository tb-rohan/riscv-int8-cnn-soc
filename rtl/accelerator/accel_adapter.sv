`timescale 1ns/1ps

module accel_adapter #(
  parameter logic [31:0] ADAPTER_VERSION = 32'h01040408,
  parameter int          WATCHDOG_LIMIT  = 65535
) (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        req,
  input  logic        we,
  input  logic [31:0] addr,
  input  logic [31:0] wdata,
  input  logic [3:0]  wstrb,
  output logic [31:0] rdata,
  output logic        stall,

  output logic [7:0]  m_axil_awaddr,
  output logic        m_axil_awvalid,
  input  logic        m_axil_awready,
  output logic [31:0] m_axil_wdata,
  output logic [3:0]  m_axil_wstrb,
  output logic        m_axil_wvalid,
  input  logic        m_axil_wready,
  input  logic [1:0]  m_axil_bresp,
  input  logic        m_axil_bvalid,
  output logic        m_axil_bready,

  output logic [7:0]  m_axil_araddr,
  output logic        m_axil_arvalid,
  input  logic        m_axil_arready,
  input  logic [31:0] m_axil_rdata,
  input  logic [1:0]  m_axil_rresp,
  input  logic        m_axil_rvalid,
  output logic        m_axil_rready,

  input  logic        accel_irq,
  output logic        irq_status
);

  typedef enum logic [1:0] {
    ST_IDLE  = 2'd0,
    ST_WRITE = 2'd1,
    ST_READ  = 2'd2,
    ST_DONE  = 2'd3
  } state_e;

  state_e state;
  logic [31:0] rdata_latched;
  logic [15:0] watchdog_cnt;
  logic        timeout_err;

  assign irq_status = accel_irq;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state          <= ST_IDLE;
      m_axil_awvalid <= 1'b0;
      m_axil_wvalid  <= 1'b0;
      m_axil_bready  <= 1'b0;
      m_axil_arvalid <= 1'b0;
      m_axil_rready  <= 1'b0;
      m_axil_awaddr  <= 8'h0;
      m_axil_wdata   <= 32'h0;
      m_axil_wstrb   <= 4'h0;
      m_axil_araddr  <= 8'h0;
      rdata_latched  <= 32'h0;
      watchdog_cnt   <= 16'd0;
      timeout_err    <= 1'b0;
    end else begin
      case (state)
        ST_IDLE: begin
          watchdog_cnt <= 16'd0;
          if (req) begin
            if (addr[7:0] == 8'h08 && !we) begin
              rdata_latched <= ADAPTER_VERSION;
              state         <= ST_DONE;
            end else if (addr[7:0] == 8'h0C) begin
              if (we) begin
                if (wdata[0]) timeout_err <= 1'b0;
              end else begin
                rdata_latched <= {watchdog_cnt, 13'h0, accel_irq, 1'b0, timeout_err};
              end
              state <= ST_DONE;
            end else if (we) begin
              state          <= ST_WRITE;
              m_axil_awvalid <= 1'b1;
              m_axil_wvalid  <= 1'b1;
              m_axil_awaddr  <= addr[7:0];
              m_axil_wdata   <= wdata;
              m_axil_wstrb   <= wstrb;
              m_axil_bready  <= 1'b1;
            end else begin
              state          <= ST_READ;
              m_axil_arvalid <= 1'b1;
              m_axil_araddr  <= addr[7:0];
              m_axil_rready  <= 1'b1;
            end
          end
        end

        ST_WRITE: begin
          watchdog_cnt <= watchdog_cnt + 16'd1;
          if (m_axil_awvalid && m_axil_awready)
            m_axil_awvalid <= 1'b0;
          if (m_axil_wvalid && m_axil_wready)
            m_axil_wvalid <= 1'b0;
          if (m_axil_bvalid && m_axil_bready) begin
            m_axil_bready <= 1'b0;
            state         <= ST_DONE;
          end else if (watchdog_cnt >= WATCHDOG_LIMIT) begin
            m_axil_awvalid <= 1'b0;
            m_axil_wvalid  <= 1'b0;
            m_axil_bready  <= 1'b0;
            timeout_err    <= 1'b1;
            state          <= ST_DONE;
          end
        end

        ST_READ: begin
          watchdog_cnt <= watchdog_cnt + 16'd1;
          if (m_axil_arvalid && m_axil_arready)
            m_axil_arvalid <= 1'b0;
          if (m_axil_rvalid && m_axil_rready) begin
            rdata_latched <= m_axil_rdata;
            m_axil_rready <= 1'b0;
            state         <= ST_DONE;
          end else if (watchdog_cnt >= WATCHDOG_LIMIT) begin
            m_axil_arvalid <= 1'b0;
            m_axil_rready  <= 1'b0;
            rdata_latched  <= 32'hDEAD_DEAD;
            timeout_err    <= 1'b1;
            state          <= ST_DONE;
          end
        end

        ST_DONE: begin
          state <= ST_IDLE;
        end
      endcase
    end
  end

  assign stall = (state == ST_IDLE) ? req :
                 (state == ST_WRITE) ? 1'b1 :
                 (state == ST_READ)  ? 1'b1 :
                 1'b0;

  assign rdata = (state == ST_READ && m_axil_rvalid) ? m_axil_rdata : rdata_latched;

endmodule
