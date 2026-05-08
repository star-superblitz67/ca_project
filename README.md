Multilevel Cache Hierarchy with 5-Stage MIPS Pipeline

This project implements a fully functional 5-stage MIPS processor pipeline integrated with a multilevel cache hierarchy (Split L1 + Unified L2) in SystemVerilog. The architecture is designed to optimize Average Memory Access Time (AMAT) and efficiently manage memory bandwidth using advanced cache policies and pipeline hazard resolutions.

Architecture Overview

1. MIPS 5-Stage Pipeline

The core is a classic 5-stage RISC pipeline:

IF (Instruction Fetch): Fetches instructions from the L1 Instruction Cache.

ID (Instruction Decode): Decodes instructions, reads registers, and resolves branches early.

EX (Execute): Performs ALU operations.

MEM (Memory Access): Reads from or writes to the L1 Data Cache.

WB (Write Back): Writes results back to the Register File.

2. Hazard & Forwarding Units

To maintain a high Instructions Per Cycle (IPC) without data corruption:

Forwarding Unit: Implements EX/MEM and MEM/WB forwarding to resolve Read-After-Write (RAW) hazards without stalling.

Hazard Unit: Detects Load-Use hazards to insert a 1-cycle pipeline bubble and flushes the pipeline upon taken branches.

3. Multilevel Cache Hierarchy

L1 Instruction Cache (L1i): Direct-mapped, read-only cache optimized for rapid instruction fetching (3-State FSM).

L1 Data Cache (L1d): Direct-mapped data cache implementing a Write-Back, Write-Allocate policy.

Unified L2 Cache (L2): A larger, unified cache that arbitrates requests between the L1i and L1d caches, backing them up before querying main memory.

DRAM Simulator: Simulates main memory with an artificial latency penalty to accurately test the cache hierarchy's AMAT improvements.

L1 Data Cache: 4-State FSM (Write-Back, Write-Allocate)

The L1 Data Cache is governed by a precise 4-state Finite State Machine to minimize main memory traffic:

IDLE: The cache waits for a memory request from the CPU.

COMPARE_TAG: The cache checks if the requested address is a hit.

If Hit: The data is read/written. On a write, the dirty bit is set. Transitions back to IDLE.

If Miss: Checks the state of the current block. If the block is valid and dirty, transitions to WRITE_BACK. Otherwise, transitions to ALLOCATE.

WRITE_BACK: Evicts the current dirty block to the L2 cache to preserve data integrity. Once L2 is ready, transitions to ALLOCATE.

ALLOCATE: Fetches the newly requested block from the L2 cache into the L1 cache. Once fetched, transitions back to COMPARE_TAG to successfully resolve the CPU's request.

Global Pipeline Stalling

The processor features a robust global stall mechanism. If either the L1i or L1d cache experiences a miss, a global mem_stall signal is asserted. This cleanly freezes the PC, IF/ID, ID/EX, EX/MEM, and MEM/WB registers, preventing the pipeline from drifting out of sync until the memory hierarchy resolves the request.

Running the Simulation

Prerequisites

Icarus Verilog (iverilog): For compiling the SystemVerilog source files.

GTKWave: For viewing the generated .vcd waveform files.

Compilation & Execution

Run the following commands in your terminal from the project root:

Compile the design:

iverilog -g2012 -o mips_sim src/*.sv tb/tb_system.sv


Run the simulation:

vvp mips_sim


This will run the testbench and generate a mips_waveform.vcd file.

View the Waveforms:

gtkwave mips_waveform.vcd


Use the GTKWave GUI to inspect the pipeline registers, hazard signals, and the L1 Data Cache's 4-state FSM transitions.
