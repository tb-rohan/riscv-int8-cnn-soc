# Clock constraint for exploratory synthesis and timing analysis
# Port: clk
# Target frequency: 100.0 MHz (Period: 10.000 ns, 50% duty cycle)
# Target Device: xc7a100tcsg324-1
create_clock -period 10.000 -name clk -waveform {0.000 5.000} [get_ports clk]

# Configuration bank voltage properties (resolves CFGBVS-1 DRC warning)
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
