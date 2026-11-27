create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]

derive_clocks

rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_clean_base/sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_clean_base/sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {video_clk}   -source [get_ports {clk}] -master_clock {clk} [get_pins {u_clean_base/video_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {u_clean_base/video_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {audio_mclk}  -source [get_ports {clk}] -master_clock {clk} [get_pins {u_clean_base/u_audio_pll/pll_inst.clkc[2]}]

set_clock_groups -asynchronous \
    -group [get_clocks {sd_card_clk}] \
    -group [get_clocks {ext_mem_clk}] \
    -group [get_clocks {u_clean_base/sys_pll_m0/pll_inst.clkc[2]}] \
    -group [get_clocks {video_clk hdmi_5x_clk}] \
    -group [get_clocks {audio_mclk}]

set_false_path \
    -from [get_pins {u_clean_base/U3/sdram.dq[*]}] \
    -to   [get_pins {u_clean_base/U3/sdram_syn_*.bpad}]

set_false_path \
    -from [get_pins {u_clean_base/U3/u2_ram/u2_wrrd/sdr_t_reg[*]}] \
    -to   [get_pins {u_clean_base/U3/sdram.dq[*]}]
