## ==============================================================================
## Target Board: Digilent Nexys A7-100T
## Target Device: AMD/Xilinx Artix-7 xc7a100tcsg324-1
## Design Top: riscv_cnn_soc_fpga_top
## Description: Physical Master Pinout Constraints & Timing Specification for the
##              Integrated RISC-V RV32I Processor + INT8 CNN Accelerator SoC.
## ==============================================================================

## -----------------------------------------------------------------------------
## 1. Primary Clock Definition (100.0 MHz, 10.000 ns Period, 50% Duty Cycle)
## -----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk_100mhz }];
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0.000 5.000} [get_ports { clk_100mhz }];

## -----------------------------------------------------------------------------
## 2. Active-Low CPU Reset Pushbutton (CPU_RESETN)
## -----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN C12   IOSTANDARD LVCMOS33 } [get_ports { cpu_resetn }];

## -----------------------------------------------------------------------------
## 3. User Pushbuttons
## -----------------------------------------------------------------------------
## Center Button (BTNC) -> Trigger Single Inference / Workload Execution
set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports { btn_trigger }];

## -----------------------------------------------------------------------------
## 4. User Slide Switches (SW[3:0])
## -----------------------------------------------------------------------------
## SW[0]: Mode select (0 = Deterministic 3-Layer Test CMD=2, 1 = Full MNIST Inference CMD=1)
## SW[3:1]: Test sample selector
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports { sw[0] }];
set_property -dict { PACKAGE_PIN L16   IOSTANDARD LVCMOS33 } [get_ports { sw[1] }];
set_property -dict { PACKAGE_PIN M13   IOSTANDARD LVCMOS33 } [get_ports { sw[2] }];
set_property -dict { PACKAGE_PIN R15   IOSTANDARD LVCMOS33 } [get_ports { sw[3] }];

## -----------------------------------------------------------------------------
## 5. User LEDs (LED[15:0])
## -----------------------------------------------------------------------------
## LED[3:0]   : Output Predicted Digit (Binary 0..9)
## LED[4]     : Inference Done Indicator
## LED[5]     : Pass / Verification Success Indicator
## LED[6]     : Hardware Interrupt Active (accel_irq_out)
## LED[7]     : SoC FSM Active / Busy Indicator
## LED[14:8]  : Status / Winning Score Magnitude
## LED[15]    : System Alive Heartbeat (1.49 Hz Blinker)
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN J13   IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { led[3] }];
set_property -dict { PACKAGE_PIN V11   IOSTANDARD LVCMOS33 } [get_ports { led[4] }];
set_property -dict { PACKAGE_PIN R11   IOSTANDARD LVCMOS33 } [get_ports { led[5] }];
set_property -dict { PACKAGE_PIN P11   IOSTANDARD LVCMOS33 } [get_ports { led[6] }];
set_property -dict { PACKAGE_PIN N10   IOSTANDARD LVCMOS33 } [get_ports { led[7] }];
set_property -dict { PACKAGE_PIN H6    IOSTANDARD LVCMOS33 } [get_ports { led[8] }];
set_property -dict { PACKAGE_PIN T6    IOSTANDARD LVCMOS33 } [get_ports { led[9] }];
set_property -dict { PACKAGE_PIN V10   IOSTANDARD LVCMOS33 } [get_ports { led[10] }];
set_property -dict { PACKAGE_PIN U11   IOSTANDARD LVCMOS33 } [get_ports { led[11] }];
set_property -dict { PACKAGE_PIN U12   IOSTANDARD LVCMOS33 } [get_ports { led[12] }];
set_property -dict { PACKAGE_PIN H5    IOSTANDARD LVCMOS33 } [get_ports { led[13] }];
set_property -dict { PACKAGE_PIN T5    IOSTANDARD LVCMOS33 } [get_ports { led[14] }];
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports { led[15] }];

## -----------------------------------------------------------------------------
## 6. USB-UART Serial Interface (115200 Baud, 8-N-1)
## -----------------------------------------------------------------------------
## FPGA TX -> FTDI USB RX (Terminal Display)
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { uart_tx }];
## FPGA RX <- FTDI USB TX (Host Ingest)
set_property -dict { PACKAGE_PIN C4    IOSTANDARD LVCMOS33 } [get_ports { uart_rx }];

## -----------------------------------------------------------------------------
## 7. Device Configuration Properties (Resolves CFGBVS-1 DRC)
## -----------------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
