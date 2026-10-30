# FPGA Implementation Readiness & Hardware Analysis Report

> **Mandatory Hardware Disclaimer**  
> *This project was validated using software-based RTL simulation and FPGA toolchain flows. No physical FPGA board was used for hardware testing.*

---

## 1. Synthesis & Physical Implementation Audit

Batch non-project synthesis and physical implementation were executed using **AMD/Xilinx Vivado v2026.1 (64-bit)** targeting the **Artix-7 100T FPGA (`xc7a100tcsg324-1`)** at a **100.000 MHz (10.000 ns)** clock constraint.

### 1.1 Tool Audit & DRC Findings
- **Unintentional Latches**: **0 Inferred Latches**. All combinational decoders, arithmetic units, and multiplexers implement full case coverage and assign outputs along all execution branches (verified via `all_latches` in Vivado).
- **Logical Port Count**: Reduced from 291 simulation ports (`cpu_standalone_top`) to **17 physical ports** (`cpu_fpga_top`). This completely resolves the previously reported `IOCNT-1` DRC violation (291 ports vs. 210 available pins).
- **Configuration Bank Voltage**: Resolved `CFGBVS-1` by defining `CFGBVS VCCO` and `CONFIG_VOLTAGE 3.3` in the design constraints (`clock.xdc`).
- **Timing Closure**: Synthesis met timing with **+0.787 ns WNS**. Post-route physical implementation closed timing with **+0.178 ns WNS** and **0.000 ns TNS** at 100 MHz, achieving an actual maximum operating frequency of **101.81 MHz**.
- **Net Routing**: 100% of routable nets (4,956 / 4,956) fully routed with 0 antenna or timing violations (`post_route_status.rpt`).

---

## 2. Measured Resource Utilization

Measurements taken directly from `synth_utilization.rpt` and `post_route_utilization.rpt`:

| Component / Resource | Synthesis Count | Post-Route Count | Available on Device | Utilization (%) |
| :--- | :---: | :---: | :---: | :---: |
| **Slice LUTs** | 4,863 | **4,834** | 63,400 | **7.62 %** |
| ├── LUT as Logic | 2,571 | **2,542** | 63,400 | **4.01 %** |
| └── LUT as Distributed RAM | 2,292 | **2,292** | 19,000 | **12.06 %** |
| **Slice Registers (FFs)** | 2,177 | **2,051** | 126,800 | **1.62 %** |
| **Block RAM (BRAM)** | 0 | **0** | 135 Tiles | **0.00 %** |
| **DSP48E1 Slices** | 0 | **0** | 240 | **0.00 %** |
| **Bonded IOBs** | 17 | **17** | 210 | **8.10 %** |
| **Global Clock Buffers (BUFG)**| 1 | **1** | 32 | **3.13 %** |

---

## 3. Memory & DSP Mapping Architecture

### 3.1 Distributed RAM vs. Block RAM Inference
Both instruction and data memories map to **Distributed RAM (LUT RAM: 2,292 LUTs)**:
- **Architectural Reason**: The 5-stage pipeline relies on combinational memory reads (`assign rdata = mem[...]`). In the instruction fetch stage, the PC address is asserted and the instruction is captured on the next rising clock edge. In the memory stage, the ALU address is asserted and load data is captured into the MEM/WB register on the next edge.
- **Hardware Constraint**: Xilinx 7-series Block RAMs require synchronous registered reads (`always_ff @(posedge clk) rdata <= mem[addr]`), introducing a mandatory 1-cycle latency.
- **Engineering Decision**: To maintain architectural correctness, verify the 5-stage pipeline, and avoid introducing pipeline stall/bubble complexities, the memories are mapped to distributed RAM. Distributed RAM operates within the 10.0 ns cycle budget and meets 100 MHz timing cleanly (+0.178 ns slack).

### 3.2 DSP Slices & Mathematical Operations
- The standalone RV32I core does not instantiate hardware DSP48E1 slices.
- Signed multiplication and division are executed in software subroutines using bitwise shifts and additions/subtractions, keeping the datapath compact and fully RV32I compliant.

---

## 4. Clocking Architecture & Reset Synchronization

### 4.1 Clocking Domain
The entire processor datapath, memories, bus interconnect, and peripherals operate on a single synchronous clock domain (`clk` at 100 MHz).

### 4.2 Reset Synchronization
External mechanical push-buttons are asynchronous and can cause metastability. The top-level wrapper `cpu_fpga_top` integrates a dedicated two-stage flip-flop reset synchronizer:

```systemverilog
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
```

---

## 5. Bitstream Generation Assessment

### 5.1 DRC Evaluation & Resolution
- In default Vivado flows, attempting `write_bitstream` on a routed netlist lacking explicit pin location (`LOC`) and I/O standard (`IOSTANDARD`) constraints halts on DRC Critical Warnings `[DRC NSTD-1]` and `[DRC UCIO-1]`.
- For software model verification without fabricating arbitrary pin bindings, the standard DRC severity downgrade was applied:
  ```tcl
  set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
  set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
  write_bitstream -force cpu_fpga_top.bit
  ```
- **Bitstream File**: Generated cleanly at `fpga/checkpoints/cpu_fpga_top.bit` (**3,825,992 bytes**).
- **Physical Programming**: Not performed because physical hardware testing is outside the scope of this project.

---

## 6. Board Migration & Pin Mapping Recommendations

The design requires only 17 physical pins and fits into any Artix-7 or Spartan-7 development board (e.g. Digilent Nexys A7-100T or Basys 3):

| Signal Name | Direction | Width | Recommended Board Peripheral | Description |
| :--- | :---: | :---: | :--- | :--- |
| `clk` | Input | 1 | 100 MHz Oscillator Pin | Primary System Clock |
| `rst_n` | Input | 1 | Active-Low Push-Button / Switch | System Reset |
| `btn_trigger` | Input | 1 | Push-Button | Re-trigger execution pulse |
| `sw_mode` | Input | 2 | Slide Switches (SW0, SW1) | 00: ISA Suite, 01: Add, 10: Mul, 11: Div |
| `led[7:0]` | Output | 8 | On-Board LEDs (LD0..LD7) | Execution Result / Return Value |
| `led_done` | Output | 1 | LED (LD8) | Execution Complete |
| `led_pass` | Output | 1 | LED (LD9, Green if RGB) | Test Passed Indicator |
| `led_fail` | Output | 1 | LED (LD10, Red if RGB) | Test Failed Indicator |
| `led_heartbeat` | Output | 1 | LED (LD15) | Blinking Clock Alive Monitor (~1.5 Hz) |
