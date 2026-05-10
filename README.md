# 5-Stage Pipelined MIPS Processor with Multi-Level Cache

Harris & Harris textbook-style pipeline with forwarding, hazard detection, and a 3-level memory hierarchy.

## Architecture

**Pipeline stages**
- IF  - fetch instruction from L1I cache
- ID  - decode, read registers, detect load-use hazards
- EX  - ALU, forwarding muxes, branch resolution
- MEM - read/write L1D cache
- WB  - write result back to register file

**Hazard handling**
- Forwarding unit: bypasses EX/MEM and MEM/WB results to avoid stalls on RAW hazards
- Hazard unit: inserts 1 bubble on load-use hazards (LW followed immediately by a dependent instruction)
- Branch flush: when a branch is taken in EX, IF/ID and ID/EX are cleared (2-cycle penalty)

**Memory hierarchy**
- L1I: direct-mapped, 4 lines x 16 bytes, read-only
- L1D: direct-mapped, 4 lines x 16 bytes, write-through / no write-allocate
- L2: FSM arbiter, L1D has priority over L1I
- DRAM: 4-cycle latency, 128-bit block transfers

**Supported instructions**
- ADDI, ADD, SUB, AND, OR (ORI)
- LW, SW
- BEQ, BNE

---

## How to Run

```bash
# compile
iverilog -g2012 -o mips_sim src/mips_processor.sv src/cache_l1i.sv src/cache_l1d.sv \
  src/cache_l2.sv src/sim_dram.sv src/forwarding_unit.sv src/hazard_unit.sv tb/tb_system.sv

# simulate
vvp mips_sim

# open waveform
gtkwave mips_waveform.vcd
```

---

## Test Program

The demo program hits every pipeline and cache feature in a single run.

```
Address  Instruction           Result    Feature
-------  -------------------   -------   ---------------------------
0x00     ADDI R1, R0,  8       R1 = 8
0x04     ADDI R2, R0,  5       R2 = 5
0x08     ADD  R3, R1, R2       R3 = 13   EX forwarding (R1 still in EX/MEM)
0x0C     SUB  R4, R3, R2       R4 = 8    EX fwd R3, MEM fwd R2

0x10     SW   R4, 0x80(R0)               L1D miss - write-through to DRAM
0x14     LW   R5, 0x80(R0)     R5 = 8    L1D miss - DRAM refill (4 cycles)
0x18     ADD  R6, R5, R3       R6 = 21   Load-use stall (1 bubble inserted)
0x1C     LW   R7, 0x80(R0)     R7 = 8    L1D hit - block already cached

0x20     ADDI R9, R0, 55       R9 = 55   Written BEFORE branch (flush proof)
0x24     BNE  R3, R4, +2       taken     13 != 8, PC jumps to 0x30
0x28     ADDI R9, R0, 111      FLUSHED   wrong path - if R9 = 111, flush broke
0x2C     ADDI R9, R0, 222      FLUSHED   wrong path

0x30     ADD  R8, R6, R7       R8 = 29   Branch target - triggers L1I miss (block 3)
0x34     AND  R9, R8, R3       R9 = 13   AND instruction (29 & 13 = 13)
0x38     NOP
0x3C     NOP
```

**Expected register values at end**

| Reg | Value | Notes |
|-----|-------|-------|
| R1  | 8     | |
| R2  | 5     | |
| R3  | 13    | EX forwarding |
| R4  | 8     | EX + MEM forwarding |
| R5  | 8     | L1D cache miss |
| R6  | 21    | Load-use stall |
| R7  | 8     | L1D cache hit |
| R8  | 29    | Computed at branch target |
| R9  | 13    | AND result; proves flush (not 111/222) |

---

## GTKWave Signals

Open `mips_waveform.vcd` in GTKWave and add these signals to see everything.

**Clock and reset**
```
tb_system.clk
tb_system.rst
```

**Program counter / fetch**
```
tb_system.cpu.pc_reg          -- current PC, should advance every cycle (or freeze on stall)
tb_system.i_req               -- L1I request from CPU
tb_system.i_ready             -- L1I ready (goes high when instruction available)
tb_system.i_addr              -- address being fetched
```

**IF/ID register** (what just got fetched)
```
tb_system.cpu.if_id_pc
tb_system.cpu.if_id_instr
```

**ID/EX register** (what is about to execute)
```
tb_system.cpu.id_ex_rs
tb_system.cpu.id_ex_rt
tb_system.cpu.id_ex_rd
tb_system.cpu.id_ex_rs_val
tb_system.cpu.id_ex_rt_val
tb_system.cpu.id_ex_imm
tb_system.cpu.id_ex_aluctrl
tb_system.cpu.id_ex_regwrite
tb_system.cpu.id_ex_memread
tb_system.cpu.id_ex_memwrite
tb_system.cpu.id_ex_branch
```

**EX stage - where forwarding and branch happen**
```
tb_system.cpu.alu_res         -- ALU output
tb_system.cpu.forward_a       -- 00=no fwd, 01=MEM/WB, 10=EX/MEM
tb_system.cpu.forward_b
tb_system.cpu.branch_taken    -- goes high when branch is resolved as taken
tb_system.cpu.branch_target   -- PC value the branch jumps to
```

**EX/MEM register**
```
tb_system.cpu.ex_mem_alu_out
tb_system.cpu.ex_mem_write_reg
tb_system.cpu.ex_mem_regwrite
tb_system.cpu.ex_mem_memread
tb_system.cpu.ex_mem_memwrite
```

**MEM/WB register**
```
tb_system.cpu.mem_wb_alu_out
tb_system.cpu.mem_wb_read_data
tb_system.cpu.mem_wb_write_reg
tb_system.cpu.mem_wb_regwrite
tb_system.cpu.mem_wb_memtoreg
tb_system.cpu.wb_data         -- final value going into register file
```

**Hazard and stall signals** (most useful for viva)
```
tb_system.cpu.stall_haz       -- high for 1 cycle on each load-use hazard
tb_system.cpu.cache_stall     -- high while waiting for L1I or L1D
tb_system.cpu.imem_stall      -- specifically waiting for instruction fetch
tb_system.cpu.dmem_stall      -- specifically waiting for data access
```

**Data memory interface**
```
tb_system.d_req
tb_system.d_we
tb_system.d_addr
tb_system.d_ready
```

**L1I cache internals**
```
tb_system.l1i.state           -- IDLE or REFILL
tb_system.l2i_req             -- L1I asking L2
tb_system.l2i_ready           -- L2 responding to L1I
```

**L1D cache internals**
```
tb_system.l1d.state           -- IDLE, REFILL, or WRITE_THROUGH
tb_system.l2d_req
tb_system.l2d_we
tb_system.l2d_ready
```

**L2 arbiter**
```
tb_system.l2.arb_state        -- IDLE, SERVE_D, or SERVE_I
```

**DRAM**
```
tb_system.dram.cnt            -- counts 1 to 4 during each DRAM transaction
tb_system.dram.busy           -- high while DRAM is serving a request
tb_system.m_req
tb_system.m_ready             -- pulses high on cycle 4 of each transaction
```

**Final register outputs**
```
tb_system.r1
tb_system.r2
tb_system.r3
tb_system.r4
tb_system.r5
tb_system.r6
tb_system.r7
tb_system.r8
tb_system.r9
```

---

## What to look for in GTKWave

- **EX forwarding**: when `forward_a` or `forward_b` goes to `10`, the ALU is using a bypassed value instead of waiting
- **Load-use stall**: `stall_haz` goes high for exactly 1 cycle; PC and IF/ID freeze; a bubble (all-zero control) appears in ID/EX
- **Branch flush**: `branch_taken` pulses high; the next 2 instructions in IF/ID and ID/EX turn to NOPs
- **L1I miss**: `l1i.state` goes to REFILL; `dram.cnt` counts 1-2-3-4; `m_ready` pulses; `l2i_ready` pulses; then `i_ready` goes high
- **L1D miss**: same as above but through `l1d.state`
- **L1D hit**: `l1d.state` stays IDLE; `d_ready` goes high the same cycle as `d_req`
- **DRAM latency**: watch `dram.cnt` — it takes 4 clock edges between req and ready
