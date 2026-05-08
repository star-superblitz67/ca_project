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

### Run Full System Integration (Phase 5 - Main)

**Option 1: Using Make (Recommended)**
```bash
cd ca_project
make run          # Compile Phase 5 (full system) and simulate
make wave         # View waveform in GTKWave
```

**Option 2: Direct Commands**
```bash
cd ca_project

# Compile full system
iverilog -g2012 -o mips_sim \
  src/sim_dram.sv \
  src/cache_l2.sv \
  src/cache_l1i.sv \
  src/cache_l1d.sv \
  src/forwarding_unit.sv \
  src/hazard_unit.sv \
  src/mips_processor.sv \
  tb/tb_system.sv

# Run simulation
vvp mips_sim

# View waveform
gtkwave mips_waveform.vcd wave.do
```

### Run Individual Phases

**Phase 0: Pipeline Only** (Forwarding, Hazards, Branches)
```bash
make phase0
```

**Phase 1: DRAM Simulator** (20-cycle latency model)
```bash
make phase1
```

**Phase 2: L2 Cache** (PLRU replacement, write-back)
```bash
make phase2
```

**Phase 3: L1D Cache** (LRU replacement, data hierarchy)
```bash
make phase3
```

**Phase 4: L1I Cache** (Direct-mapped, instruction hierarchy)
```bash
make phase4
```

**Phase 5: Full Integration** (Complete system with all components)
```bash
make phase5
```

## 📊 Signal Naming Convention

All signals use standard abbreviations:

| Abbreviation | Meaning |
|--------------|---------|
| `if_` | Instruction Fetch stage |
| `id_` | Instruction Decode stage |
| `ex_` | Execute stage |
| `mem_` | Memory stage |
| `wb_` | Write-back stage |
| `rf[]` | Register file (32 registers, 32-bit each) |
| `pc` | Program counter |
| `rs`, `rt`, `rd` | Register addresses (source, target, destination) |
| `imm` | Immediate value |
| `alu_op` | ALU operation selector |

## 🔧 Pipeline Architecture

### 5-Stage Pipeline Flow
```
IF → [IF_ID] → ID → [ID_EX] → EX → [EX_MEM] → MEM → [MEM_WB] → WB
      Register   ↑
      Stage      └─ Forwarded values (resolve RAW hazards)
```

### Pipeline Registers

**IF/ID Pipeline Register** (if_id_*)
- `if_id_instr` – Instruction
- `if_id_pc` – Program counter
- `if_id_write` – Control signal (stall when low)

**ID/EX Pipeline Register** (id_ex_*)
- `id_ex_instr` – Instruction
- `id_ex_pc` – Program counter
- `id_ex_rs_data`, `id_ex_rt_data` – Operand values
- `id_ex_alu_op` – ALU operation
- `id_ex_mem_read`, `id_ex_mem_write` – Memory control
- `id_ex_flush` – Branch flush signal

**EX/MEM Pipeline Register** (ex_mem_*)
- `ex_mem_instr` – Instruction
- `ex_mem_pc` – Program counter
- `ex_mem_alu_out` – ALU result
- `ex_mem_rd` – Destination register
- `ex_mem_rt_data` – Data for memory write

**MEM/WB Pipeline Register** (mem_wb_*)
- `mem_wb_instr` – Instruction
- `mem_wb_pc` – Program counter
- `mem_wb_alu_out` – ALU result
- `mem_wb_mem_rdata` – Loaded data
- `mem_wb_rd` – Destination register

## 📈 Data Flow Examples

### Example 1: RAW Hazard Resolution (Forwarding)
```
Cycle 1: ADD $1, $2, $3    (EX stage)  → ALU generates $1
Cycle 2: ADDI $4, $1, 10   (ID stage)  → Needs $1 (not in RF yet!)

Result: Forwarding unit detects ex_mem_rd matches id_ex_rs
        → forward_a = 2'b10 (select EX/MEM stage output)
        → No stall needed, ADDI receives correct value
```

### Example 2: Load-Use Hazard (Pipeline Stall)
```
Cycle 1: LW $1, 0($2)      (EX stage)  → Address calculation
Cycle 2: ADDI $3, $1, 5    (ID stage)  → Needs $1 (loading from memory!)

Result: Hazard unit detects id_ex_mem_read && (id_ex_rd matches rs)
        → load_use_hazard = 1
        → if_id_write = 0, pc_write = 0 (freeze IF/ID/EX stages)
        → LW waits for MEM stage to complete load
```

### Example 3: Cache Miss Stall
```
Cycle 1: IF stage requests instruction at address 0x1000
         L1I looks up, tag misses
         
Cycle 2-N: L1I requests from L2, L2 requests from DRAM
           if_stall = 1 (freezes IF/ID stages)
           
Cycle N+1: Data arrives at L1I
           if_stall = 0, IF resumes

Result: Pipeline continues with correct instruction
```

## 🎯 Control Signals

### Stall Control
- **`if_stall`**: 1 = L1I cache miss, freeze IF stage
- **`mem_stall`**: 1 = L1D cache miss, freeze MEM stage
- **`load_use_hazard`**: 1 = Load-use dependency detected
- **`pc_write`**: 1 = Allow PC increment, 0 = Hold PC
- **`if_id_write`**: 1 = Allow IF/ID update, 0 = Stall
- **`id_ex_flush`**: 1 = Clear ID/EX on branch misprediction

### Forwarding Control
- **`forward_a`**: 2'b10=EX, 2'b01=MEM, 2'b00=RF (operand A source)
- **`forward_b`**: 2'b10=EX, 2'b01=MEM, 2'b00=RF (operand B source)

### Cache Interface
- **IF-side**:
  - `if_cpu_read` – Request instruction
  - `if_cpu_addr[31:0]` – Instruction address (PC)
  - `if_cpu_rdata[31:0]` – Instruction from cache
  - `if_stall` – Cache miss signal

- **MEM-side**:
  - `mem_cpu_read` – Read request
  - `mem_cpu_write` – Write request
  - `mem_cpu_addr[31:0]` – Memory address
  - `mem_cpu_wdata[31:0]` – Data to write
  - `mem_cpu_rdata[31:0]` – Data from cache
  - `mem_stall` – Cache miss signal

## 📊 Waveform Analysis (GTKWave)

Open waveform:
```bash
make wave
# or manually:
gtkwave mips_waveform.vcd wave.do
```

### Pre-configured Signals (wave.do)

**🟥 Control Signals**
- `if_stall`, `mem_stall`, `load_use_hazard`, `pc_write`, `if_id_write`, `id_ex_flush`

**📍 Program Counters**
- `pc`, `if_id_pc`, `id_ex_pc`, `ex_mem_pc`, `mem_wb_pc`

**🔗 Cache Requests**
- `if_cpu_read`, `if_cpu_addr`, `mem_cpu_read`, `mem_cpu_write`, `mem_cpu_addr`
- `mem_cpu_wdata`, `mem_cpu_rdata`

**📦 Instructions**
- `if_id_instr`, `id_ex_instr`, `ex_mem_instr`, `mem_wb_instr` (watch propagation)

**➡️ Forwarding & Dependencies**
- `forward_a`, `forward_b`, `ex_mem_rd`, `mem_wb_rd`

**🧮 ALU & Results**
- `id_ex_alu_op`, `ex_mem_alu_out`, `mem_wb_mem_rdata`

**📝 Registers**
- `rf[0]` through `rf[10]` (track values and updates)

### What to Look For

1. **Instruction Progression**: Watch `if_id_instr` → `id_ex_instr` → `ex_mem_instr` → `mem_wb_instr` flow. Each stage should advance every cycle (unless stalled).

2. **Stalls**: When `if_stall` or `mem_stall` go high, pipeline stages freeze. Check corresponding `*_write` control signals go low.

3. **Forwarding**: When `forward_a` or `forward_b` = 2'b10 or 2'b01, forwarding is active. Compare `ex_mem_alu_out` or `mem_wb_mem_rdata` to operand values.

4. **Register Updates**: Watch `rf[n]` values change in WB stage when instruction writes to that register (check `mem_wb_rd`).

5. **Cache Misses**: When `if_stall` = 1, `if_cpu_addr` holds steady (request pending to L2). When data arrives, `if_stall` drops and PC increments.

## 🧪 Compilation & Execution

### Build Outputs

After running simulation, you'll see:

| File | Purpose |
|------|---------|
| `mips_sim` | Compiled Phase 5 executable |
| `pipeline_sim` | Compiled Phase 0 executable |
| `dram_sim` | Compiled Phase 1 executable |
| `l2_sim` | Compiled Phase 2 executable |
| `l1d_sim` | Compiled Phase 3 executable |
| `l1i_sim` | Compiled Phase 4 executable |
| `mips_waveform.vcd` | Waveform dump Phase 5 (open in GTKWave) |
| `pipeline_waveform.vcd` | Waveform dump Phase 0 |
| `dram_waveform.vcd` | Waveform dump Phase 1 |
| `l2_waveform.vcd` | Waveform dump Phase 2 |
| `l1d_waveform.vcd` | Waveform dump Phase 3 |
| `l1i_waveform.vcd` | Waveform dump Phase 4 |

### Clean Build
```bash
make clean       # Removes all executables and waveforms
```

## 🎯 Instruction Set Support

The processor supports a subset of MIPS ISA:

| Instruction | Opcode | Format | Operation |
|-------------|--------|--------|-----------|
| `ADD` | 0 | R-type | `$rd = $rs + $rt` |
| `SUB` | 0 | R-type | `$rd = $rs - $rt` |
| `AND` | 0 | R-type | `$rd = $rs & $rt` |
| `OR` | 0 | R-type | `$rd = $rs \| $rt` |
| `SLT` | 0 | R-type | `$rd = ($rs < $rt) ? 1 : 0` |
| `ADDI` | 8 | I-type | `$rt = $rs + sign_extend(imm)` |
| `LW` | 35 | I-type | `$rt = mem[$rs + sign_extend(imm)]` |
| `SW` | 43 | I-type | `mem[$rs + sign_extend(imm)] = $rt` |
| `BEQ` | 4 | I-type | `if ($rs == $rt) PC += 4 + sign_extend(imm)*4` |

### Instruction Encoding

**R-type:**
```
[opcode(6)] [rs(5)] [rt(5)] [rd(5)] [shamt(5)] [funct(6)]
     0                                          (add=0x20, sub=0x22, etc.)
```

**I-type:**
```
[opcode(6)] [rs(5)] [rt(5)] [imm(16)]
  (addi=8, lw=35, sw=43, beq=4)
```

## ✅ Expected Test Results

When you run `make run` (or `vvp mips_sim`), the testbench executes 5 gate checks:

```
TEST 1: CACHE HITS SEQUENCE
  ✓ Multiple instructions and data ops from cache
  ✓ if_stall and mem_stall mostly low
  ✓ Pipeline continues with minimal stalls

TEST 2: L1I MISS + L1D HIT
  ✓ L1I miss detected and served by L2
  ✓ if_stall goes high until instruction arrives
  ✓ Pipeline continues on L1D hits

TEST 3: L1D MISS + L1I HIT
  ✓ L1D miss stalls MEM stage
  ✓ if_stall stays low (L1I hits)
  ✓ IF/ID/EX stages continue normally

TEST 4: SIMULTANEOUS L1I + L1D MISSES
  ✓ L2 arbitration: L1D served first
  ✓ L1I waits for L2 availability
  ✓ Both misses eventually resolved

TEST 5: HAZARDS + CACHE STALLS
  ✓ Load-use hazard + mem_stall combined
  ✓ Pipeline correctly freezes on both conditions
  ✓ Data forwarding works through cache stalls
```

All tests should **PASS** with gate checks verified.

## 🔍 Troubleshooting

### Compilation Error: "constant selects not supported"
This is a known Icarus Verilog limitation with dynamic array indexing in always_* blocks. The provided code uses explicit if-else chains—no action needed.

### "sorry: cannot evaluate constant functions"
Another Icarus Verilog limitation. The code avoids complex bit slicing operations inside combinational blocks.

### Simulation produces unexpected stalls
**Check:**
1. Are load-use hazards being detected? Search waveform for `load_use_hazard=1`
2. Are cache misses occurring? Look for `if_stall=1` or `mem_stall=1`
3. Is forwarding working? Verify `forward_a` and `forward_b` values (2'b10 or 2'b01)

### Waveform won't open
```bash
# Verify GTKWave is installed
gtkwave --version

# Try opening manually
gtkwave mips_waveform.vcd
```

### All signals show 'x' (undefined)
The simulation may not have reset properly. Check:
- `rst_n` signal goes high after clock cycles
- Initialization values in testbench are correct
- Simulation runs long enough to show results (check `$finish` cycle count)

## 📝 File Descriptions

### Source Files (src/)

**mips_processor.sv** (515 lines)
- Core 5-stage pipeline implementation
- Instantiates forwarding_unit and hazard_unit
- Interfaces with L1I and L1D caches
- Registers: IF/ID, ID/EX, EX/MEM, MEM/WB
- Key components: PC logic, instruction decode, register file, ALU, branch logic

**forwarding_unit.sv** (60 lines)
- Detects RAW data hazards across pipeline stages
- Compares destination register (rd) of previous instructions with source registers (rs, rt) of current
- Outputs: `forward_a`, `forward_b` (2-bit selectors: EX=10, MEM=01, RF=00)
- Priority: EX/MEM stage over MEM/WB stage

**hazard_unit.sv** (20 lines)
- Detects load-use hazards
- Signals when load destination matches next instruction operand
- Causes pipeline stall (1 cycle) to allow load to complete
- Output: `load_use_hazard` (1 = stall, 0 = no hazard)

**cache_l1i.sv** (180 lines)
- 1KB direct-mapped instruction cache
- 64 sets, 1 way (each set has 1 line)
- Read-only (fetches instructions only)
- Interfaces with IF stage and L2 cache
- Misses sent to L2 cache

**cache_l1d.sv** (220 lines)
- 1KB 2-way associative data cache with LRU replacement
- 32 sets, 2 ways (each set has 2 lines)
- Supports both read and write operations
- Interfaces with MEM stage and L2 cache
- Misses sent to L2 cache with priority arbitration

**cache_l2.sv** (280 lines)
- 16KB 4-way associative unified cache with PLRU replacement
- 128 sets, 4 ways (each set has 4 lines)
- Serves both L1I and L1D caches
- Arbitration: L1D priority over L1I
- Interfaces with DRAM simulator
- Line replacement using Pseudo-LRU (PLRU)

**sim_dram.sv** (100 lines)
- Models main memory behavior
- 20-cycle latency for read/write operations
- Simulates DRAM response delay
- Interfaces with L2 cache
- Maintains queue of pending requests

### Testbench Files (tb/)

**tb_system.sv** (240 lines) ⭐ **Phase 5 - Main Integration**
- Instantiates complete system: processor + L1I + L1D + L2 + DRAM
- Tests cache hierarchy interaction and control signal coordination
- Executes 5 gate checks verifying cache hits, misses, arbitration, and combined hazards
- Generates `mips_waveform.vcd` for waveform analysis

**tb_pipeline.sv** (Phase 0)
- Tests 5-stage pipeline in isolation (no cache)
- Verifies instruction sequencing, branch prediction
- Tests forwarding unit behavior
- Tests hazard detection unit (load-use)

**tb_sim_dram.sv** (Phase 1)
- Tests DRAM simulator alone
- Verifies 20-cycle latency model
- Tests request queueing

**tb_cache_l2.sv** (Phase 2)
- Tests L2 cache with DRAM backend
- Verifies cache hits and misses
- Tests line replacement (PLRU algorithm)
- Tests write-back behavior

**tb_cache_l1d.sv** (Phase 3)
- Tests L1D cache with L2 backend
- Verifies 2-way LRU replacement
- Tests read and write operations
- Tests data forwarding through cache misses

**tb_cache_l1i.sv** (Phase 4)
- Tests L1I cache with L2 backend
- Verifies direct-mapped behavior
- Tests instruction fetch on hits and misses

## 📚 Additional Resources

- **wave.do**: GTKWave configuration file (signal hierarchy, highlighting, zoom level)
- **Makefile**: Build automation with targets for all phases

## 🔨 Development Tips

### Extending the Processor

1. **Add new instructions**: Modify instruction decode in mips_processor.sv
2. **Change cache policies**: Edit replacement logic in cache_*.sv files
3. **Add more registers**: Increase register file size in mips_processor.sv
4. **Modify latencies**: Adjust DRAM cycles in sim_dram.sv

### Performance Analysis

Monitor these signals to analyze performance:
- `if_stall`, `mem_stall` – Count stall cycles
- `load_use_hazard` – Track hazard frequency
- `forward_a`, `forward_b` – Count forwarding operations

### Debugging Tips

- Start with Phase 0 (pipeline only) to isolate processor logic
- Add $display statements in testbench for printf-style debugging
- Use GTKWave search feature to find specific signal transitions
- Check waveform for unexpected signal values or timing

## 📝 License

Educational project - modify and distribute freely for academic purposes.

---

**Last Updated**: May 5, 2026  
**System Status**: ✅ All phases compiled, verified, and fully functional

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
iverilog -g2012 -o mips_sim \
  src/sim_dram.sv \
  src/cache_l2.sv \
  src/cache_l1i.sv \
  src/cache_l1d.sv \
  src/forwarding_unit.sv \
  src/hazard_unit.sv \
  src/mips_processor.sv \
  tb/tb_system.sv

# Run simulation
vvp mips_sim

# View waveform
gtkwave mips_waveform.vcd wave.do
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
make wave              # Opens mips_waveform.vcd
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
| `mips_sim` | Compiled simulation executable |
| `mips_waveform.vcd` | Waveform dump Phase 5 (open in GTKWave) |
| Output messages | Gate check results and verification status |

## 📖 Additional Documentation

- **wave.do**: GTKWave configuration for signal highlighting and hierarchy setup
- **Makefile**: Build automation with targets for all phases

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
