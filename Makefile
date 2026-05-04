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

phase1:
	$(CC) $(FLAGS) -o phase1_out src/sim_dram.sv tb/tb_sim_dram.sv
	$(SIM) phase1_out

phase1_wave:
	$(WAVE) phase1_waveform.vcd

phase2:
	$(CC) $(FLAGS) -o phase2_out src/sim_dram.sv src/cache_l2.sv tb/tb_cache_l2.sv
	$(SIM) phase2_out

phase2_wave:
	$(WAVE) phase2_waveform.vcd

phase3:
	$(CC) $(FLAGS) -o phase3_out src/sim_dram.sv src/cache_l2.sv src/cache_l1d.sv tb/tb_cache_l1d.sv
	$(SIM) phase3_out

phase3_wave:
	$(WAVE) phase3_waveform.vcd

phase4:
	$(CC) $(FLAGS) -o phase4_out src/sim_dram.sv src/cache_l2.sv src/cache_l1i.sv tb/tb_cache_l1i.sv
	$(SIM) phase4_out

phase4_wave:
	$(WAVE) phase4_waveform.vcd

phase5:
	$(CC) $(FLAGS) -o phase5_out src/sim_dram.sv src/cache_l2.sv src/cache_l1i.sv src/cache_l1d.sv src/forwarding_unit.sv src/hazard_unit.sv src/mips_pipeline_integrated.sv tb/tb_integrated.sv
	$(SIM) phase5_out

phase5_wave:
	$(WAVE) phase5_waveform.vcd

clean:
	del /Q *.out *.vcd *.log 2>nul

