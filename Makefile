# MIPS 5-Stage Pipeline with Multilevel Cache - Makefile
# Uses Icarus Verilog and GTKWave

CC = iverilog
FLAGS = -g2012
SIM = vvp
WAVE = gtkwave

.PHONY: all clean phase0 phase1 phase2 phase3 phase4 phase5

all: phase0

phase0:
	$(CC) $(FLAGS) -o phase0_out src/mips_pipeline.sv src/forwarding_unit.sv src/hazard_unit.sv tb/tb_pipeline.sv
	$(SIM) phase0_out

phase0_wave:
	$(WAVE) phase0_waveform.vcd wave.do

clean:
	del /Q *.out *.vcd *.log 2>nul
