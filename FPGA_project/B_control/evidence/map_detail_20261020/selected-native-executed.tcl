cd {D:/_fpga_package_tools/temperature_single_20261031/B_control_single_native36}
import_device eagle_s20.db -package EG4S20BG256
import_db smart_terminal_gate.db
update_timing -mode basic
set_clock_uncertainty -setup 0.850 [get_clocks ext_mem_clk]
set_param place seed 36
set_param place enable_seed on
place
export_db smart_terminal_place.db
set_param route effort high
set_param route multi_try_route on
route
fix_hold
clear_sdc -user
read_sdc {D:/HX4S20C_temperature_single_20261031/B_control/constraints/timing.sdc}
update_timing -mode final
report_timing_status -file smart_terminal_phy.ts
report_timing_summary -file smart_terminal_pr.timing
report_route_status -drc -file smart_terminal_route_drc.rpt
report_area -io_info -file smart_terminal_phy.area
report_qor -step route -file route.qor
report_timing_exception -file smart_terminal_exception.timing
export_db smart_terminal_pr.db
bitgen -bit smart_terminal.bit -bin smart_terminal.bin
