# ButterflyScape

A university CAD/FPGA game with VGA output, button input, LEDs, and seven-segment display output. This was a group project by **Arad Razpour and Reza Yaghoubi**.

## Files

- `ButterflyScapeGame.vhd`: game state and rendering logic
- `VGA_controller.vhd`: VGA timing and scan coordinates
- `ButterflyScapeTop.vhd`: top-level wiring for the board
- `VGA.ucf`: original FPGA pin mapping
- `ButterflyScape.xise`: original Xilinx ISE project configuration

Open `ButterflyScape.xise` in Xilinx ISE 14.7. Its target is Spartan-6 `xc6slx9`, package `tqg144`. Check that the `.ucf` pin map matches the actual board before programming it. The source was extracted from the original course archive; generated implementation files and report photos are excluded. Hardware behavior and synthesis have not been rerun in this prepared copy.
