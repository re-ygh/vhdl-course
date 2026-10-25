SetActiveLib -work
comp -include "$dsn\src\reg_pkg.vhd"
comp -include "$dsn\src\reg.vhd"
comp -include "$dsn\src\TestBench\reg_TB.vhd"
asim +access +r TESTBENCH_FOR_reg
wave
wave -noreg Clock
wave -noreg Reset
wave -noreg DataIn
wave -noreg Insert
wave -noreg Delete
wave -noreg Search
wave -noreg Count
wave -noreg Reverse
wave -noreg ShiftLeft
wave -noreg ShiftRight
wave -noreg Clear
wave -noreg Get
wave -noreg Sort
wave -noreg DataOut
wave -noreg Valid
# The following lines can be used for timing simulation
# acom <backannotated_vhdl_file_name>
# comp -include "$dsn\src\TestBench\reg_TB_tim_cfg.vhd"
# asim +access +r TIMING_FOR_reg
