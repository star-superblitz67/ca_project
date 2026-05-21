# MIPS 5-Stage Pipeline with Cache Hierarchy

A working  MIPS processor written in SystemVerilog.
Built for a computer architecture OSL.

---

## What's inside

**The pipeline** runs 5 stages: IF → ID → EX → MEM → WB.

**Hazard handling:**
- Forwarding unit bypasses ALU results so back-to-back instructions don't stall
- Load-use stall: if a LW result is used immediately, one bubble is inserted
- Branch flush: when a branch is taken in EX, the two wrong-path instructions behind it are discarded

**Memory hierarchy:**
- L1I (instruction cache) — 4 lines, 16 bytes each, read-only
- L1D (data cache) — 4 lines, 16 bytes each, write-through (writes go straight to DRAM)
- L2 arbiter — sits between L1 and DRAM, gives L1D priority over L1I
- DRAM — 4-cycle latency, serves 16-byte blocks

**ALU supports:** ADD, SUB, AND, OR, ADDI, ORI, LW, SW, BEQ, BNE

---

## How to run

```bash
# main demo (all features in one run)
iverilog -g2012 -o mips_sim src/mips_processor.sv src/cache_l1i.sv src/cache_l1d.sv \
  src/cache_l2.sv src/sim_dram.sv src/forwarding_unit.sv src/hazard_unit.sv tb/tb_system.sv
vvp mips_sim
gtkwave mips_waveform.vcd

# forwarding test only
iverilog -g2012 -o tb_fwd_sim src/mips_processor.sv src/cache_l1i.sv src/cache_l1d.sv \
  src/cache_l2.sv src/sim_dram_bare.sv src/forwarding_unit.sv src/hazard_unit.sv tb/tb_forwarding.sv
vvp tb_fwd_sim

# hazards test only (load-use stall + branch flush)
iverilog -g2012 -o tb_haz_sim src/mips_processor.sv src/cache_l1i.sv src/cache_l1d.sv \
  src/cache_l2.sv src/sim_dram_bare.sv src/forwarding_unit.sv src/hazard_unit.sv tb/tb_hazards.sv
vvp tb_haz_sim

# cache hit/miss test only
iverilog -g2012 -o tb_cache_sim src/mips_processor.sv src/cache_l1i.sv src/cache_l1d.sv \
  src/cache_l2.sv src/sim_dram_bare.sv src/forwarding_unit.sv src/hazard_unit.sv tb/tb_cache.sv
vvp tb_cache_sim
```

---

## Testbenches

### tb_system (main demo)
Runs a program that hits every feature in one go.

| Address | Instruction | Result | What it shows |
|---------|-------------|--------|---------------|
| 0x00 | ADDI R1, R0, 8 | R1=8 | baseline |
| 0x04 | ADDI R2, R0, 5 | R2=5 | baseline |
| 0x08 | ADD  R3, R1, R2 | R3=13 | EX forwarding (R1 still in pipeline) |
| 0x0C | SUB  R4, R3, R2 | R4=8  | EX fwd R3, MEM fwd R2 |
| 0x10 | SW   R4, 0x80(R0) | mem[0x80]=8 | L1D miss, write-through to DRAM |
| 0x14 | LW   R5, 0x80(R0) | R5=8  | L1D miss, DRAM refill |
| 0x18 | ADD  R6, R5, R3 | R6=21 | load-use stall on R5 |
| 0x1C | LW   R7, 0x80(R0) | R7=8  | L1D hit (block already cached) |
| 0x20 | ADDI R9, R0, 55 | R9=55 | written before branch (flush proof) |
| 0x24 | BNE  R3, R4, +2 | taken | 13≠8, jumps to 0x30, flushes 0x28+0x2C |
| 0x28 | ADDI R9, R0, 111 | FLUSHED | wrong path |
| 0x2C | ADDI R9, R0, 222 | FLUSHED | wrong path |
| 0x30 | ADD  R8, R6, R7 | R8=29 | branch target, L1I miss (new block) |
| 0x34 | AND  R9, R8, R3 | R9=13 | AND instruction (29 & 13 = 13) |

Expected: R1=8 R2=5 R3=13 R4=8 R5=8 R6=21 R7=8 R8=29 R9=13

---

### tb_forwarding
5 instructions in a chain, every one uses the result of the previous.
No loads, so load-use stall count should be 0.
Forwarding unit is active on almost every cycle.

Expected: R1=10 R2=20 R3=30 R4=50 R5=20

---

### tb_hazards
Isolates load-use stall (LW → ADD, 1 bubble expected) and branch flush (BEQ taken).
R5 should be 42, not 99 — if flush broke, R5 would be 99.

Expected: R1=5 R2=5 R3=5 R4=10 R5=42

---

### tb_cache
Writes to two addresses in the same 16-byte block, then reads them back.
First LW is a miss (DRAM refill), second and third are hits (block already in L1D).

Expected: R1=7 R2=3 R3=7 R4=3 R5=7
L1D hit count should be 2, load-use stalls should be 0.

---

## Signals to watch in GTKWave

for whichever testbench,  add these signals.

**tb_system:**
```
tb_system.clk
tb_system.cpu.pc_reg          -- current PC, freezes during stalls
tb_system.cpu.stall_haz       -- pulses HIGH for each load-use bubble
tb_system.cpu.cache_stall     -- HIGH while waiting for L1I or L1D
tb_system.cpu.branch_taken    -- HIGH when branch resolves as taken
tb_system.cpu.forward_a       -- 00=no fwd, 01=MEM/WB, 10=EX/MEM
tb_system.cpu.forward_b
tb_system.dram.cnt            -- counts 1→2→3→4 for every DRAM access
tb_system.dram.busy
tb_system.m_ready             -- pulses HIGH on cycle 4 of each DRAM transaction
```

**Pipeline registers (shows what's in each stage):**
```
tb_system.cpu.if_id_instr     -- instruction just fetched
tb_system.cpu.id_ex_rs        -- source registers going into EX
tb_system.cpu.id_ex_rt
tb_system.cpu.id_ex_aluctrl   -- what operation EX will do
tb_system.cpu.id_ex_memread   -- set when a LW is in EX
tb_system.cpu.ex_mem_alu_out  -- ALU result passing to MEM stage
tb_system.cpu.ex_mem_regwrite
tb_system.cpu.mem_wb_read_data -- data read from L1D (loads)
tb_system.cpu.mem_wb_regwrite
tb_system.cpu.wb_data         -- final value written into register file
```

**Cache internals:**
```
tb_system.l1i.state           -- IDLE or REFILL
tb_system.l1d.state           -- IDLE, REFILL, or WRITE_THROUGH
tb_system.l2.arb_state        -- IDLE, SERVE_D, or SERVE_I
tb_system.i_ready             -- L1I giving the CPU an instruction
tb_system.d_ready             -- L1D completing a load/store
```

**Register outputs (watch values settle as instructions complete WB):**
```
tb_system.r1  tb_system.r2  tb_system.r3
tb_system.r4  tb_system.r5  tb_system.r6
tb_system.r7  tb_system.r8  tb_system.r9
```

---

## in the waveform

**Forwarding in action** — when `forward_a` or `forward_b` is `10`, the ALU is getting its input from `ex_mem_alu_out` instead of the register file. No stall, just a wire bypass.

**Load-use stall** — `stall_haz` goes HIGH for exactly 1 cycle. PC stops, IF/ID freezes, a bubble (all zeros in ID/EX) flows into EX. After 1 cycle, the load result is in MEM/WB and forwarding takes over.

**Branch flush** — `branch_taken` pulses HIGH. The very next cycle, IF/ID and ID/EX both show zeroed control signals (the wrong-path instructions become NOPs).

**Cache miss** — `l1d.state` (or `l1i.state`) goes to REFILL. `dram.cnt` starts counting 1-2-3-4. On cycle 4, `m_ready` pulses, `l2.arb_state` returns to IDLE, and `d_ready` goes HIGH. `cache_stall` is HIGH throughout.

**Cache hit** — `l1d.state` stays IDLE, `d_ready` is HIGH the same cycle as `d_req`. No stall at all.

**DRAM latency** — just watch `dram.cnt` go from 0 → 1 → 2 → 3 → 4 → 0. The pipeline is frozen the whole time.
