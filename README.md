# 5-Stage Pipelined MIPS Processor with Multi-Level Cache

This project implements a textbook-style (Harris & Harris) 5-stage pipelined MIPS processor integrated with a functional memory hierarchy.

## Architecture Features
1. **5-Stage Pipeline**: 
   - **IF (Fetch)**: Program Counter and Instruction Cache interface.
   - **ID (Decode)**: Instruction decoding, Register File access, and Hazard Detection.
   - **EX (Execute)**: ALU operations, Branch resolution, and Forwarding logic.
   - **MEM (Memory)**: Data Cache interface (Load/Store).
   - **WB (Write-back)**: Register File update.
2. **Hazard Handling**:
   - **Forwarding Unit**: Bypasses data from EX/MEM and MEM/WB stages to resolve RAW hazards without stalling.
   - **Hazard Unit**: Injects stalls (bubbles) for Load-Use hazards.
   - **Branch Flushing**: Flushes the pipeline (converts wrong-path instructions to NOPs) when a branch is taken.
3. **Memory Hierarchy**:
   - **L1I & L1D**: Direct-mapped 4-line caches (128-bit blocks) with Write-Through policy.
   - **L2 Arbiter**: Manages simultaneous requests from L1 caches.
   - **DRAM Model**: Simulates a 4-cycle memory latency.

## How to Run

1. **Compile**:
   ```bash
   iverilog -g2012 -o mips_sim tb/tb_system.sv src/*.sv
   ```

2. **Simulate**:
   ```bash
   vvp mips_sim
   ```

3. **Verify**:
   The testbench will print the final register values. You should see:
   - R1 = 5
   - R2 = 10
   - R3 = 15 (Result of ADD)
   - R4 = 15 (Result of LW)
   - R5 = 20 (Result of ADD R5, R4, R1)
   - R7 = 275 (Result of ORI after Branch)

4. **Waveform**:
   ```bash
   gtkwave mips_waveform.vcd
   ```

## Key Signals to Watch
- `tb_system.cpu.mem_stall`: High during cache misses.
- `tb_system.cpu.stall_haz`: High during Load-Use hazards.
- `tb_system.cpu.flush`: High during Branch flushes.
- `tb_system.cpu.forward_a/b`: Shows bypassing in action.
