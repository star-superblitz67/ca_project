# MIPS 5-Stage Pipeline with Multilevel Cache - Makefile
# Uses Icarus Verilog and GTKWave

CC = iverilog
FLAGS = -g2012
SIM = vvp
WAVE = gtkwave

.PHONY: all clean phase0 phase1 phase2 phase3 phase4 phase5 run wave
CLEAN_FILES = pipeline_sim dram_sim l2_sim l1d_sim l1i_sim mips_sim

all: phase5

phase0:
	$(CC) $(FLAGS) -o pipeline_sim src/mips_processor.sv src/forwarding_unit.sv src/hazard_unit.sv tb/tb_pipeline.sv
	$(SIM) pipeline_sim

phase0_wave:
	$(WAVE) pipeline_waveform.vcd wave.do

phase1:
	$(CC) $(FLAGS) -o dram_sim src/sim_dram.sv tb/tb_sim_dram.sv
	$(SIM) dram_sim

phase1_wave:
	$(WAVE) dram_waveform.vcd

phase2:
	$(CC) $(FLAGS) -o l2_sim src/sim_dram.sv src/cache_l2.sv tb/tb_cache_l2.sv
	$(SIM) l2_sim

phase2_wave:
	$(WAVE) l2_waveform.vcd

phase3:
	$(CC) $(FLAGS) -o l1d_sim src/sim_dram.sv src/cache_l2.sv src/cache_l1d.sv tb/tb_cache_l1d.sv
	$(SIM) l1d_sim

phase3_wave:
	$(WAVE) l1d_waveform.vcd

phase4:
	$(CC) $(FLAGS) -o l1i_sim src/sim_dram.sv src/cache_l2.sv src/cache_l1i.sv tb/tb_cache_l1i.sv
	$(SIM) l1i_sim

phase4_wave:
	$(WAVE) l1i_waveform.vcd

phase5: 
	$(CC) $(FLAGS) -o mips_sim src/sim_dram.sv src/cache_l2.sv src/cache_l1i.sv src/cache_l1d.sv src/forwarding_unit.sv src/hazard_unit.sv src/mips_processor.sv tb/tb_system.sv
	$(SIM) mips_sim

phase5_wave:
	$(WAVE) mips_waveform.vcd wave.do

run: phase5

wave: phase5_wave

clean:
	del /Q *_sim *.vcd *.log 2>nul

