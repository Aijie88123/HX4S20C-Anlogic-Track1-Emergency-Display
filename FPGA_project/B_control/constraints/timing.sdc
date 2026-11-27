create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]
create_clock -name eth_rx_clock -period 40 [get_ports {eth_rx_clk}]
# Virtual PHY launch edges precede RXC capture edges by 2ns (1..3ns).
# Explicit phase models the next data transition correctly for hold checks.
create_clock -name eth_rx_launch -period 40 -waveform {18 38}
derive_clocks

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

set_clock_groups -asynchronous -group [get_clocks {eth_clk eth_tx_phase eth_txc}] -group [get_clocks {eth_rx_clock eth_rx_launch}]

rename_clock -name sd_card_clk -source [get_ports {clk}] -master_clock clk [get_pins {media_service$u_storage/sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name ext_mem_clk -source [get_ports {clk}] -master_clock clk [get_pins {media_service$u_storage/sys_pll_m0/pll_inst.clkc[1]}]
set_clock_groups -asynchronous -group [get_clocks {sd_card_clk}] -group [get_clocks {ext_mem_clk}] -group [get_clocks {media_service$u_storage/sys_pll_m0/pll_inst.clkc[2]}] -group [get_clocks {eth_clk eth_tx_phase eth_txc}] -group [get_clocks {eth_rx_clock eth_rx_launch}]
set_false_path -from [get_pins {media_service$u_storage/U3/sdram.dq[*]}] -to [get_pins {media_service$u_storage/U3/sdram_syn_*.bpad}]

# New asynchronous UART input feeds only the dedicated rx_meta synchronizer.
# All existing clocks, timing requirements and exceptions above are preserved.
set_false_path -from [get_ports {uart_rx}]
# UART is asynchronous; bound only the new output propagation, not old paths.
set_max_delay 100.0 -to [get_ports {uart_tx}]

# Asynchronous DQ enters the original two-single-bit synchronizer in onewire_slot.
set_false_path -from [get_ports {ds18b20_dq}]
