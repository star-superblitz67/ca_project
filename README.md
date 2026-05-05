# MIPS 5-Stage Pipeline with Multilevel Cache Hierarchy

A complete SystemVerilog implementation of a 32-bit MIPS processor with a three-level cache system, featuring forwarding units, hazard detection, and cache arbitration.

## 📋 Overview

This project implements a full microarchitecture with the following components:

### Processor Core
- **5-Stage Pipeline**: Instruction Fetch (IF) → Decode (ID) → Execute (EX) → Memory (MEM) → Write-back (WB)
- **Forwarding Unit**: Resolves Read-After-Write (RAW) data hazards to minimize ALU stalls
- **Hazard Detection Unit**: Detects load-use hazards and stalls the pipeline when necessary
- **Branch Support**: BEQ (branch if equal) instruction with prediction

### Memory Hierarchy
- **L1 Instruction Cache (L1I)**: 1KB, direct-mapped, read-only
- **L1 Data Cache (L1D)**: 1KB, 2-way associative (LRU replacement), read-write
- **L2 Cache**: 16KB, 4-way associative (PLRU replacement), unified (serves both L1I and L1D)
- **DRAM Simulator**: Models main memory with 20-cycle latency

### Cache Arbitration
- L1D requests have priority over L1I requests to L2
- Ensures data consistency when both caches request L2 simultaneously

## 🗂️ Project Structure

```
ca_project/
├── src/                           # Source modules
│   ├── mips_processor.sv          # 5-stage pipeline processor core
│   ├── forwarding_unit.sv         # RAW hazard resolution
│   ├── hazard_unit.sv             # Load-use hazard detection
│   ├── cache_l1i.sv               # L1 Instruction cache
│   ├── cache_l1d.sv               # L1 Data cache
│   ├── cache_l2.sv                # L2 Unified cache
│   └── sim_dram.sv                # DRAM simulator
│
├── tb/                            # Testbenches
│   ├── tb_system.sv               # Full system integration testbench ⭐ (main)
│   ├── tb_pipeline.sv             # Pipeline-only testbench (Phase 0)
│   ├── tb_sim_dram.sv             # DRAM simulator testbench (Phase 1)
│   ├── tb_cache_l2.sv             # L2 cache testbench (Phase 2)
│   ├── tb_cache_l1d.sv            # L1D cache testbench (Phase 3)
│   └── tb_cache_l1i.sv            # L1I cache testbench (Phase 4)
│
├── Makefile                       # Build configuration
├── wave.do                        # GTKWave configuration
├── README.md                      # This file
└── HUMANIZATION_REPORT.md         # Code quality documentation
```

## 🚀 Quick Start

### Prerequisites
- **Icarus Verilog** (v11 or higher)  
  ```bash
  # Windows (with Chocolatey)
  choco install icarus-verilog
  # macOS (with Homebrew)
  brew install icarus-verilog
  # Linux (Ubuntu/Debian)
  sudo apt-get install iverilog
  ```

- **GTKWave** (for waveform visualization)
  ```bash
  # Windows
  choco install gtkwave
  # macOS
  brew install gtkwave
  # Linux
  sudo apt-get install gtkwave
  ```

### Run the Full System (Phase 5)

**Option 1: Using Make (Recommended)**
```bash
cd ca_project
make run          # Compile and simulate full system
make wave         # View waveform in GTKWave
```

**Option 2: Manual Compilation & Simulation**
```bash
cd ca_project

# Compile
iverilog -g2012 -o phase5_out \
  src/sim_dram.sv \
  src/cache_l2.sv \
  src/cache_l1i.sv \
  src/cache_l1d.sv \
  src/forwarding_unit.sv \
  src/hazard_unit.sv \
  src/mips_processor.sv \
  tb/tb_system.sv

# Run simulation
vvp phase5_out

# View waveform
gtkwave phase5_waveform.vcd wave.do
```

## 📚 Understanding the Architecture

### Signal Naming Convention

All signals use standard abbreviations for clarity:

| Abbreviation | Meaning |
|--------------|---------|
| `if_` | Instruction Fetch stage |
| `id_` | Instruction Decode stage |
| `ex_` | Execute stage |
| `mem_` | Memory stage |
| `wb_` | Write-back stage |
| `rf[]` | Register file |
| `pc` | Program counter |
| `rs`, `rt`, `rd` | Register addresses (source, target, destination) |
| `imm` | Immediate value |
| `alu_` | ALU signals |

### Pipeline Register Organization

```
IF → [IF_ID] → ID → [ID_EX] → EX → [EX_MEM] → MEM → [MEM_WB] → WB
      Pipeline   ↑
      Registers  └─ Forwarded values prevent stalls
```

Each pipeline register holds:
- **if_id_**: Instruction, PC, register addresses
- **id_ex_**: Operands, ALU operation code, control signals
- **ex_mem_**: ALU result, memory address, write data
- **mem_wb_**: ALU result, loaded data, destination register

### Data Flow Examples

#### Example 1: ADD → ADDI (Forwarding)
```
Cycle 1: ADD $1, $2, $3     (EX stage)  → generates $1 value
Cycle 2: ADDI $4, $1, 10    (ID stage)  → needs $1 (forwarded from EX)
Result: No stall (forwarding unit resolves RAW hazard)
```

#### Example 2: LW → ADDI (Load-Use Hazard)
```
Cycle 1: LW $1, 0($2)       (EX stage)  → address calculation
Cycle 2: ADDI $4, $1, 10    (ID stage)  → needs $1 (not ready yet!)
Result: Pipeline stalls for 1 cycle (hazard unit detects load-use)
```

#### Example 3: Cache Miss
```
Cycle N: IF stage requests instruction from L1I cache
L1I Miss: Fetches from L2 cache (10+ cycles)
Result: if_stall=1, freezes IF/ID stages until instruction arrives
```

## 🔧 Signal Reference

### Top-Level Interface (mips_processor.sv)

**Instruction Cache Interface:**
```verilog
output if_cpu_read           // Request instruction from cache
output [31:0] if_cpu_addr    // Instruction address (PC)
input  [31:0] if_cpu_rdata   // Instruction data from cache
input  if_stall              // Cache miss (freeze IF stage)
```

**Data Cache Interface:**
```verilog
output mem_cpu_read          // Read request
output mem_cpu_write         // Write request
output [31:0] mem_cpu_addr   // Memory address
output [31:0] mem_cpu_wdata  // Data to write
input  [31:0] mem_cpu_rdata  // Data from cache
input  mem_stall             // Cache miss (freeze MEM stage)
```

### Key Internal Signals

| Signal | Width | Purpose |
|--------|-------|---------|
| `pc` | 32 | Current program counter |
| `if_id_instr` | 32 | Instruction in IF/ID register |
| `id_ex_alu_op` | 4 | ALU operation selector |
| `forward_a`, `forward_b` | 2 | Forwarding multiplexer controls |
| `load_use_hazard` | 1 | Load-use stall signal |
| `rf[]` | 32×32 | Register file (32 registers, 32-bit each) |

## 🧪 Testing Phases

The project includes individual testbenches for each component:

### Phase 0: Pipeline Only
```bash
make phase0          # Basic 5-stage pipeline test
```
Tests: Instruction sequences, forwarding, branch prediction

### Phase 1: DRAM Simulator
```bash
make phase1          # DRAM latency model test
```
Tests: 20-cycle memory access latency

### Phase 2: L2 Cache
```bash
make phase2          # L2 cache with DRAM backend
```
Tests: Cache hits/misses, line replacement (PLRU), write-back

### Phase 3: L1D Cache
```bash
make phase3          # L1D + L2 + DRAM
```
Tests: Data cache behavior, 2-way LRU, data forwarding through cache

### Phase 4: L1I Cache
```bash
make phase4          # L1I + L2 + DRAM
```
Tests: Instruction cache behavior, direct-mapped replacement

### Phase 5: Full Integration ⭐
```bash
make phase5          # Complete system test
```
Tests: Both caches with processor, arbitration, combined hazards

## 📊 Expected Behavior

### Gate Checks (Validation Points)

When you run `make run`, the simulation verifies:

✅ **Cache Hits**: Minimal stalls when data is in cache  
✅ **L1I Miss Handling**: `if_stall` controls instruction fetch  
✅ **L1D Miss Handling**: `mem_stall` stalls memory stage  
✅ **Cache Arbitration**: L1D requests served before L1I  
✅ **Hazards + Cache Stalls**: Load-use hazard + cache miss handled correctly  

### Example Output
```
TEST 1: CACHE HITS SEQUENCE
  Multiple instructions and data ops from cache
  Expected: Minimal stalls (only register hazards)
  ✓ Executed 50 cycles with cache hits
  ✓ if_stall and mem_stall mostly low

TEST 2: L1I MISS + L1D HIT
  Instruction fetch from L2 while data stays in L1D
  Expected: if_stall=1, mem_stall=0, L1I misses
  ✓ L1I miss detected and served by L2
  ✓ Pipeline continues on L1D hits
```

## 📈 Waveform Analysis

Open the generated waveform in GTKWave:
```bash
make wave              # Opens phase5_waveform.vcd
```

### Key Signals to Monitor

1. **Program Counter Progression**
   - `if_id_pc`: Shows instruction addresses flowing through pipeline
   - Look for stalls (pc doesn't increment) during cache misses

2. **Cache Control Signals**
   - `if_stall`: 1 = instruction cache miss, 0 = hit
   - `mem_stall`: 1 = data cache miss, 0 = hit

3. **Register File Operations**
   - `rf[1]` through `rf[31]`: Track register values
   - Watch for correct data forwarding

4. **ALU Operations**
   - `alu_out`: ALU result
   - `id_ex_alu_op`: Current operation (0=add, 1=sub, 2=and, 3=or, etc.)

5. **Forwarding Status**
   - `forward_a`, `forward_b`: Indicate which values are forwarded
   - 2'b10 = forwarded from EX stage, 2'b01 = from MEM stage, 2'b00 = from register file

## 🎯 Instruction Set Support

The processor supports a subset of MIPS ISA:

| Instruction | Format | Operation |
|-------------|--------|-----------|
| `ADD` | R-type | `$rd = $rs + $rt` |
| `SUB` | R-type | `$rd = $rs - $rt` |
| `AND` | R-type | `$rd = $rs & $rt` |
| `OR` | R-type | `$rd = $rs \| $rt` |
| `SLT` | R-type | `$rd = ($rs < $rt) ? 1 : 0` |
| `ADDI` | I-type | `$rt = $rs + imm` |
| `LW` | I-type | `$rt = mem[$rs + imm]` |
| `SW` | I-type | `mem[$rs + imm] = $rt` |
| `BEQ` | I-type | `if ($rs == $rt) PC += imm*4` |

## 🔍 Troubleshooting

### Compilation Error: "sorry: constant selects not supported"
This is a known Icarus Verilog limitation. The code uses if-else chains instead of array indexing with dynamic indices—this is already handled in the provided code.

### Waveform shows unusual stalls
Check:
1. Are load-use hazards detected? Look for `load_use_hazard` signal
2. Are cache misses occurring? Check `if_stall` and `mem_stall`
3. Is forwarding working? Verify `forward_a` and `forward_b` values

### Simulation runs but shows errors
1. Verify all .sv files are in the correct directories
2. Check file permissions
3. Ensure iverilog version is 11 or higher: `iverilog --version`

## 📝 File Descriptions

### Source Files

**mips_processor.sv** (515 lines)
- Main 5-stage pipeline implementation
- Combines all stages: IF, ID, EX, MEM, WB
- Instantiates forwarding and hazard units
- Interfaces with L1I and L1D caches

**forwarding_unit.sv** (60 lines)
- Detects RAW data hazards
- Selects correct operand source (register file or forwarded value)
- Outputs: `forward_a`, `forward_b` (2-bit selectors)

**hazard_unit.sv** (20 lines)
- Detects load-use hazards
- Stalls pipeline when necessary
- Output: `load_use_hazard` signal

**cache_l1i.sv** (180 lines)
- Direct-mapped L1 instruction cache
- Read-only (no write operations)
- Interfaces with pipeline IF stage and L2 cache

**cache_l1d.sv** (220 lines)
- 2-way associative L1 data cache with LRU replacement
- Supports both read and write operations
- Interfaces with pipeline MEM stage and L2 cache

**cache_l2.sv** (280 lines)
- 4-way associative L2 cache with PLRU replacement
- Unified cache (serves both L1I and L1D)
- Arbitration logic (L1D priority)
- Interfaces with DRAM simulator

**sim_dram.sv** (100 lines)
- Models main memory behavior
- Implements 20-cycle latency
- Responds to read/write requests from L2 cache

### Testbench Files

**tb_system.sv** (240 lines) ⭐ **Main Integration Testbench**
- Instantiates complete system: processor + L1I + L1D + L2 + DRAM
- Tests cache hierarchy interaction
- Verifies signal flow between all components
- Generates comprehensive gate checks

**tb_pipeline.sv** (Phase 0)
- Tests 5-stage pipeline in isolation
- Verifies forwarding and hazard detection
- No cache interactions

**tb_sim_dram.sv** (Phase 1)
- Tests DRAM simulator alone
- Verifies 20-cycle latency model

**tb_cache_l2.sv** (Phase 2)
- Tests L2 cache with DRAM backend
- Verifies line replacement and write-back

**tb_cache_l1d.sv** (Phase 3)
- Tests L1D cache with L2 backend
- Verifies LRU replacement

**tb_cache_l1i.sv** (Phase 4)
- Tests L1I cache with L2 backend
- Verifies direct-mapped behavior

## 💾 Build Artifacts

After running `make run`, you'll see:

| File | Purpose |
|------|---------|
| `phase5_out` | Compiled simulation executable |
| `phase5_waveform.vcd` | Waveform dump (open in GTKWave) |
| Output messages | Gate check results and verification status |

## 📖 Additional Documentation

- **HUMANIZATION_REPORT.md**: Details on code quality improvements, bug fixes, and variable naming conventions
- **wave.do**: GTKWave configuration for signal highlighting and hierarchy setup

## 🤝 Contributing

To extend this implementation:

1. **Add new instructions**: Edit decode logic in mips_processor.sv
2. **Modify cache policies**: Update replacement logic in cache_*.sv files
3. **Add performance counters**: Extend testbenches to track metrics
4. **Optimize for FPGA**: Synthesize with Vivado or Quartus

## 📝 License

Educational project - modify and distribute freely for academic purposes.

---

**Last Updated**: May 5, 2026  
**System Status**: ✅ All phases verified and fully functional
