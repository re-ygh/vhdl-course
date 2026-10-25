# 16×16-bit register file

A 16-entry register array with a validity bit per entry. Commands include insert, delete, search, count, get, reverse, rotate left/right, sort, and clear. The output `Valid` signal marks cycles in which `DataOut` contains a result.

## Files

- `reg_pkg.vhd`: shared types and array operations
- `reg.vhd`: clocked register-file implementation
- `tb_reg.vhd`: self-checking testbench covering the commands
- `reg_TB_runtest.do`: original Active-HDL simulation script

## Run in Active-HDL

Compile `reg_pkg.vhd`, `reg.vhd`, then `tb_reg.vhd`. Set `reg_TB` as the simulation top and run until the testbench reports `ALL TESTS PASSED`. The `.do` file can automate this in the original Active-HDL project context.

The source uses VHDL-93 syntax. The original Active-HDL log shows a later successful compile and two `ALL TESTS PASSED` messages after an earlier compile-order error. The testbench has not been rerun in this prepared copy.
