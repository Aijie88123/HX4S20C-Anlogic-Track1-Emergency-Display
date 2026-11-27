create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]

create_clock -name eth_rx_clock -period 40 [get_ports {eth_rx_clk}]
# Virtual PHY launch edges precede RXC capture edges by 2ns (1..3ns).
# Explicit phase models the next data transition correctly for hold checks.
create_clock -name eth_rx_launch -period 40 -waveform {18 38}

derive_clocks

rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {video_clk}   -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {audio_mclk}  -source [get_ports {clk}] -master_clock {clk} [get_pins {u_audio_pll/pll_inst.clkc[2]}]


rename_clock -name {eth_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_ethernet_pll/pll_inst.clkc[0]}]
rename_clock -name {eth_tx_phase} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_ethernet_pll/pll_inst.clkc[1]}]
create_generated_clock -name eth_txc -source [get_pins {u_ethernet_pll/pll_inst.clkc[1]}] -divide_by 1 [get_ports {eth_tx_clk}]
# The PHY is explicitly configured for internal RX clock delay; allow 1..3ns skew.
set_input_delay -clock eth_rx_launch -max 1.0 [get_ports {eth_rxd[*] eth_rx_ctl}]
set_input_delay -clock eth_rx_launch -min -1.0 [get_ports {eth_rxd[*] eth_rx_ctl}]
set_input_delay -clock eth_rx_launch -clock_fall -add_delay -max 1.0 [get_ports {eth_rxd[*] eth_rx_ctl}]
set_input_delay -clock eth_rx_launch -clock_fall -add_delay -min -1.0 [get_ports {eth_rxd[*] eth_rx_ctl}]
# TXC is delayed 90 degrees (10ns) and the PHY TX internal delay is disabled.
set_output_delay -clock eth_txc -max 1.0 [get_ports {eth_txd[*] eth_tx_ctl}]
set_output_delay -clock eth_txc -min -1.0 [get_ports {eth_txd[*] eth_tx_ctl}]
set_output_delay -clock eth_txc -clock_fall -add_delay -max 1.0 [get_ports {eth_txd[*] eth_tx_ctl}]
set_output_delay -clock eth_txc -clock_fall -add_delay -min -1.0 [get_ports {eth_txd[*] eth_tx_ctl}]
# Only MDIO enters a dedicated two-register synchronizer; its slow protocol is simulated.
set_false_path -from [get_ports {eth_mdio}]

set_clock_groups -asynchronous \
    -group [get_clocks {sd_card_clk}] \
    -group [get_clocks {ext_mem_clk}] \
    -group [get_clocks {sys_pll_m0/pll_inst.clkc[2]}] \
    -group [get_clocks {video_clk hdmi_5x_clk}] \
    -group [get_clocks {audio_mclk}] \
    -group [get_clocks {eth_clk eth_tx_phase eth_txc}] \
    -group [get_clocks {eth_rx_clock eth_rx_launch}]

# EG4S20 embedded SDRAM hard macro. The DQ input pins are driven by the
# hard macro and are not ordinary user-register launch points. Exclude only
# this internal hard-macro feedback from the user timing graph.
set_false_path \
    -from [get_pins {U3/sdram.dq[*]}] \
    -to   [get_pins {U3/sdram_syn_*.bpad}]

# Wrapper-based bring-up projects place the same hard macro under u_top.
# Apply the identical exception to the wrapped hierarchy.
set_false_path \
    -from [get_pins {u_top/U3/sdram.dq[*]}] \
    -to   [get_pins {u_top/U3/sdram_syn_*.bpad}]

# audio_fft uses registered MAC stages and ordinary single-cycle timing.
