# Implementation of a 5-Stage MIPS Pipeline with a Multilevel Cache Hierarchy

This repository details the implementation of a comprehensive 5-stage MIPS processor pipeline, integrated with a multilevel cache hierarchy encompassing split Level 1 (L1) caches and a unified Level 2 (L2) cache, developed in SystemVerilog. The architectural design is primarily focused on the optimization of Average Memory Access Time (AMAT) and the efficient management of memory bandwidth through the deployment of advanced cache policies and pipeline hazard resolution mechanisms.

## Architecture Overview

### 1. MIPS 5-Stage Pipeline

The core processing unit utilizes a quintessential 5-stage Reduced Instruction Set Computer (RISC) pipeline architecture:

* **Instruction Fetch (IF)**: Retrieves instructions from the L1 Instruction Cache.

* **Instruction Decode (ID)**: Decodes fetched instructions, accesses the register file, and executes early branch resolution.

* **Execute (EX)**: Executes arithmetic and logical operations utilizing the Arithmetic Logic Unit (ALU).

* **Memory Access (MEM)**: Interfaces with the L1 Data Cache for requisite memory read or write operations.

* **Write Back (WB)**: Commits execution results back to the architectural register file.

### 2. Hazard & Forwarding Units

To sustain optimal Instructions Per Cycle (IPC) throughput while guaranteeing data integrity, the architecture incorporates the following mechanisms:

* **Forwarding Unit**: Implements data forwarding paths between the EX/MEM and MEM/WB stages to resolve Read-After-Write (RAW) data hazards without necessitating pipeline stalls.

* **Hazard Unit**: Identifies Load-Use structural hazards to insert a localized one-cycle pipeline stall (bubble) and executes complete pipeline flushes upon the detection of taken branches to mitigate control hazards.

### 3. Multilevel Cache Hierarchy

* **L1 Instruction Cache (L1i)**: A direct-mapped, read-only cache engineered for accelerated instruction fetching, managed by a 3-state Finite State Machine (FSM).

* **L1 Data Cache (L1d)**: A direct-mapped cache memory employing a strict Write-Back, Write-Allocate policy to minimize write latency.

* **Unified L2 Cache (L2)**: A higher-capacity, unified cache structure that arbitrates concurrent requests from the L1i and L1d caches, serving as an intermediary buffer prior to main memory access.

* **DRAM Simulator**: A simulated main memory module incorporating artificial latency to facilitate the accurate evaluation of AMAT improvements across the cache hierarchy.

## L1 Data Cache: 4-State FSM (Write-Back, Write-Allocate)

The operational behavior of the L1 Data Cache is governed by a rigorously defined 4-state Finite State Machine, designed specifically to attenuate main memory traffic:

1. **`IDLE`**: The cache remains in a quiescent state pending an active memory request from the central processing unit.

2. **`COMPARE_TAG`**: The system evaluates the requested memory address to determine cache hit or miss status.

   * **Hit**: Data is actively read or written. During a write operation, the respective `dirty` bit is asserted. The FSM subsequently reverts to the `IDLE` state.

   * **Miss**: The state of the currently residing block is evaluated. Should the block be both valid and dirty, the FSM transitions to the `WRITE_BACK` state. Otherwise, it proceeds directly to the `ALLOCATE` state.

3. **`WRITE_BACK`**: The active dirty block is evicted and written back to the L2 cache to ensure data coherence. Upon receiving a ready signal from the L2 cache, the FSM transitions to the `ALLOCATE` state.

4. **`ALLOCATE`**: The required memory block is fetched from the L2 cache and allocated within the L1 cache. Following successful retrieval, the FSM returns to the `COMPARE_TAG` state to fulfill the initial processor request.

## Global Pipeline Stalling

The processor architecture incorporates a robust global stall mechanism to manage memory access latencies. In the event of a cache miss within either the L1i or L1d modules, a global `mem_stall` signal is asserted. This control signal synchronously suspends the Program Counter (`PC`) alongside the `IF/ID`, `ID/EX`, `EX/MEM`, and `MEM/WB` inter-stage registers. This ensures the pipeline remains temporally synchronized while the memory hierarchy resolves the outstanding data request.

## Simulation Procedures

### Prerequisites

* **Icarus Verilog (`iverilog`)**: Required for the compilation of SystemVerilog source code.

* **GTKWave**: Required for the visualization of generated Value Change Dump (`.vcd`) waveform files.

### Compilation & Execution

Execute the following commands within the terminal from the root directory of the project:

1. **Compile the hardware design:**

   ```bash
   iverilog -g2012 -o mips_sim src/*.sv tb/tb_system.sv
2. **Execute simulation:**

   ```bash
   vvp mips_sim
3. **Gtkwave waveform:**

   ```bash
   gtkwave mips_waveform.vcd   
