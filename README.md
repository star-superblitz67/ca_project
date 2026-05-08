# MIPS 5-Stage Pipeline with Cache Hierarchy

SystemVerilog implementation of a 32-bit MIPS processor with 5-stage pipeline, hazard handling, and 3-level cache hierarchy (L1I, L1D, L2).

## Architecture

- **Processor**: 5-stage pipeline (IF→ID→EX→MEM→WB)
- **L1I Cache**: 1KB, direct-mapped
- **L1D Cache**: 1KB, 2-way LRU, write-back policy
- **L2 Cache**: 16KB, 4-way PLRU, unified
- **DRAM**: 20-cycle latency simulator
- **Hazard Resolution**: Forwarding unit + load-use detection
- **Cache Arbitration**: L1D priority over L1I

## Prerequisites

```bash
# Windows
choco install icarus-verilog gtkwave

# macOS
brew install icarus-verilog gtkwave

# Linux
sudo apt-get install iverilog gtkwave
```

## Quick Start

```bash
# Run full system (Phase 5)
make run

# View waveform
make wave

# Individual Components

```bash
make phase0       # Pipeline only (pipeline_sim)
make phase1       # DRAM simulator (dram_sim)
make phase2       # L2 cache (l2_sim)
make phase3       # L1D cache (l1d_sim)
make phase4       # L1I cache (l1i_sim)
make phase5       # Full system (mips_sim)

# View waveforms
make phase0_wave  # pipeline_waveform.vcd
make phase1_wave  # dram_waveform.vcd
make phase2_wave  # l2_waveform.vcd
make phase3_wave  # l1d_waveform.vcd
make phase4_wave  # l1i_waveform.vcd
make phase5_wave  # mips_waveform.vcd
```

## Manual Compilation

```bash
# Compile
iverilog -g2012 -o mips_sim \
  src/sim_dram.sv src/cache_l2.sv \
  src/cache_l1i.sv src/cache_l1d.sv \
  src/forwarding_unit.sv src/hazard_unit.sv \
  src/mips_processor.sv tb/tb_system.sv

# Run
vvp mips_sim

# View waveform
gtkwave mips_waveform.vcd wave.do
```

## Project Structure

```
ca_project/
├── src/
│   ├── mips_processor.sv      # 5-stage pipeline
│   ├── forwarding_unit.sv     # RAW hazard resolution
│   ├── hazard_unit.sv         # Load-use hazard detection
│   ├── cache_l1i.sv           # L1I cache
│   ├── cache_l1d.sv           # L1D cache (2-way LRU, write-back FSM)
│   ├── cache_l2.sv            # L2 cache (4-way PLRU)
│   └── sim_dram.sv            # DRAM simulator
├── tb/
│   ├── tb_system.sv           # Full system testbench
│   ├── tb_pipeline.sv         # Phase 0
│   ├── tb_sim_dram.sv         # Phase 1
│   ├── tb_cache_l2.sv         # Phase 2
│   ├── tb_cache_l1d.sv        # Phase 3
│   └── tb_cache_l1i.sv        # Phase 4
├── Makefile
├── wave.do
└── README.md
```

## Key Features

- ✅ Forwarding unit for RAW hazard resolution
- ✅ Load-use hazard detection with pipeline stalls
- ✅ Write-back, write-allocate cache policy
- ✅ 3-state FSM in L1D (IDLE, WRITEBACK, ALLOCATE)
- ✅ L1D priority arbitration to L2
- ✅ BEQ branch prediction support
- ✅ 5 verification phases (pipeline → full system)

## Supported Instructions

**R-type**: ADD, SUB, AND, OR, SLT  
**I-type**: ADDI, LW, SW, BEQ

## Signal Naming Convention

| Signal | Meaning |
|--------|---------|
| `if_*` | Instruction Fetch stage |
| `id_*` | Instruction Decode stage |
| `ex_*` | Execute stage |
| `mem_*` | Memory stage |
| `wb_*` | Write-back stage |
| `rf[]` | Register file |
| `*_stall` | Cache miss signal |

## Simulation Output

Running `make run` executes 5 gate checks:
- Cache hits verification
- L1I miss handling
- L1D miss handling
- L1D priority arbitration
- Combined hazards + cache stalls

All tests pass with ✓ verification status.

## Build Artifacts

| File | Purpose |
|------|---------|
| `mips_sim` | Compiled executable |
| `mips_waveform.vcd` | Waveform dump |
| `pipeline_waveform.vcd` - `l1i_waveform.vcd` | Phase waveforms |

## For More Details

See `COMMANDS.txt` for extended command reference and troubleshooting.
