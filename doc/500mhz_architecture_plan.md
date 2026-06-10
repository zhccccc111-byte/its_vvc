# ITS VVC 500MHz 双时钟架构计划

## 1. 目标

**外部接口低速，内部 ITS compute core 跑 500MHz。**

| 域 | 时钟 | 频率 | 说明 |
|----|------|------|------|
| `clk_if` | 接口时钟 | 100MHz (10ns) | 赛题外部接口，I/O pad 友好 |
| `clk_core` | 核心时钟 | 500MHz (2ns) | 内部计算引擎，OOC 综合验证 |

核心思路：把 OBUF (2.398ns) + BRAM read (1.846ns) + 时钟偏斜 (3.920ns) = 8.164ns 从关键路径上彻底移除。核心只看寄存器→寄存器逻辑，2ns 目标在 28nm ASIC 可行，在 Artix-7 OOC 综合可量化差距。

---

## 2. 当前架构分析

### 2.1 现有模块

| 模块 | 行数 | 职责 | 实例数 |
|------|------|------|--------|
| `its_top` | 607 | 顶层 FSM + 内存管理 + I/O | 1 |
| `its_transform_engine` | 398 | 1D 行/列变换 (4 MAC 并行) | 2 (row + col) |
| `its_mac` | 49 | 流水线乘累加 (2 级) | 9 (4+4+1) |
| `its_rom` | 27 | 变换核 ROM (8176×16) | 2 (row + col) |
| `its_lfnst` | 358 | LFNST 变换 | 1 |
| `its_lfnst_rom` | 27 | LFNST ROM (8192×16) | 1 |

### 2.2 现有状态流

```
S_IDLE → S_CLEAR → S_LOAD → [S_LFNST] → S_ROW_START → S_ROW_RUN
  → S_COL_START → S_COL_RUN → S_OUT → S_DONE → S_IDLE
```

### 2.3 关键路径瓶颈 (FPGA Artix-7 -3)

| 路径 | 延迟 | 说明 |
|------|------|------|
| OBUF | 2.398ns | I/O pad，物理不可优化 |
| BRAM read (out_mem) | 1.846ns | 同步读延迟 |
| 时钟偏斜 (BUFG→BRAM) | 3.920ns | 物理距离 |
| 布线 | 1.886ns | IOB 约束后 |
| **合计** | **~8.2ns** | 对应 ~122MHz (仅输出路径) |

内部逻辑路径（synthesis 级）：`tu_width_reg → coeff_buf (DistRAM) → DSP48E1` = 5.483ns (6 级逻辑)。移除 I/O 和 BRAM 后，纯逻辑路径在 28nm 下估算 ~1.0ns。

---

## 3. 双时钟架构

### 3.1 顶层框图

```
                     clk_if (100MHz)
                         │
    ┌────────────────────┴────────────────────┐
    │           its_top_500_wrapper            │
    │                                         │
    │  it_info ──→ cmd_fifo ──────────────┐   │
    │  it_data_in ──→ input_fifo ─────────┤   │
    │  it_data_addr                        │   │
    │  it_data_in_vld                      │   │
    │  it_data_end ──→ cmd_fifo            │   │
    │                                      │   │
    │  it_data_in_req ←── input_fifo level │   │
    │                                      │   │
    │              ┌───────────────────────┤   │
    │              │  CDC FIFO boundary    │   │
    │              └───────────────────────┤   │
    │                         clk_core (500MHz)
    │                         │             │   │
    │              ┌──────────┴──────────┐  │   │
    │              │    its_core_500     │  │   │
    │              │                     │  │   │
    │              │  cmd_decode         │  │   │
    │              │  in_mem (sync read) │  │   │
    │              │  LFNST engine       │  │   │
    │              │  row_engine (4 MAC) │  │   │
    │              │  tp_buf (sync read) │  │   │
    │              │  col_engine (4 MAC) │  │   │
    │              │  out_mem (sync read)│  │   │
    │              │                     │  │   │
    │              └──────────┬──────────┘  │   │
    │                         │             │   │
    │              ┌──────────┴──────────┐  │   │
    │              │  output_fifo (CDC)  │  │   │
    │              └──────────┬──────────┘  │   │
    │                         │             │   │
    │  it_data_out ←── output_fifo rd      │   │
    │  it_data_out_vld                      │   │
    │  it_data_out_req ──→ output_fifo      │   │
    │  it_done ←── done_sync                │   │
    └─────────────────────────────────────────┘
```

### 3.2 模块清单

| 新模块 | 职责 | 时钟域 |
|--------|------|--------|
| `its_top_500_wrapper` | 顶层 wrapper，实例化 FIFO + core | clk_if + clk_core |
| `async_fifo` | 异步 FIFO (Gray code) | clk_if wr / clk_core rd |
| `its_core_500` | 计算核心，替代原 its_top 的核心逻辑 | clk_core |
| `cmd_fifo` | 传递 it_info + it_data_end + 参数 | clk_if → clk_core |
| `input_fifo` | 传递稀疏输入数据 (addr + coeff) | clk_if → clk_core |
| `output_fifo` | 传递 40-bit 输出结果 | clk_core → clk_if |

### 3.3 FIFO 协议

#### cmd_fifo (clk_if → clk_core)

| 字段 | 位宽 | 说明 |
|------|------|------|
| `it_info[21:0]` | 22 | TU 参数 |
| `it_data_end` | 1 | 输入结束标志 |
| **总计** | **23 bit** | |

写入条件：`it_info_vld` 脉冲时写入 info；`it_data_end` 脉冲时写入 info + end 标志。
深度：4 条目（支持连续 TU 缓冲）。

#### input_fifo (clk_if → clk_core)

| 字段 | 位宽 | 说明 |
|------|------|------|
| `it_data_addr[11:0]` | 12 | 稀疏地址 |
| `it_data_in[15:0]` | 16 | 系数值 |
| **总计** | **28 bit** | |

写入条件：`it_data_in_vld && it_data_in_req`。
深度：16 条目（典型 TU 非零点数 < 16）。
反压：`it_data_in_req = (input_fifo_count < threshold)`。

#### output_fifo (clk_core → clk_if)

| 字段 | 位宽 | 说明 |
|------|------|------|
| `it_data_out[39:0]` | 40 | 4×10-bit 输出 |
| **总计** | **40 bit** | |

写入条件：core 输出阶段产生数据时。
深度：16 条目（64×64 TU 最多 1024 个输出 beat，但 FIFO 只需缓冲到下游消费）。
反压：core 输出阶段检查 `output_fifo_full`，暂停输出。

### 3.4 CDC 规则

1. **异步时钟组**：`clk_if` 和 `clk_core` 之间设置 `set_clock_groups -asynchronous`
2. **CDC 只通过 FIFO**：所有跨域数据必须经过 Gray code 异步 FIFO
3. **禁止跨域直接采样**：控制信号（start、done、状态）必须经过同步器或 FIFO
4. **复位同步**：`rst_n` 分别同步到两个时钟域（异步释放、同步断言）

---

## 4. 核心重构 (`its_core_500`)

### 4.1 与原 `its_top` 的差异

| 项目 | 原 `its_top` | 新 `its_core_500` |
|------|-------------|-------------------|
| 时钟 | 100MHz (含 I/O) | 500MHz (纯内部) |
| 输入接口 | 直接端口 | 从 cmd_fifo/input_fifo 读取 |
| 输出接口 | 直接端口 + OBUF | 写入 output_fifo |
| `in_mem` 读 | 异步 (组合逻辑) | **同步读** (1 拍延迟) |
| `tp_buf` 读 | 异步 (组合逻辑) | **同步读** (1 拍延迟) |
| MAC 流水线 | 2 级 (乘+累加) | **4 级** (输入寄存+乘+累加+round/clip) |
| 地址计算 | 组合逻辑 (row*width+col) | **递推计数器** (prev + step) |
| `out_mem` | 写入 + 同步读 + OBUF | 写入 + 同步读 + 写入 output_fifo |
| I/O pad | 含 OBUF/IOB | 无 |

### 4.2 RAM 改造详情

#### 4.2.1 `in_mem` 改同步读

```verilog
// 原: 异步读 (组合逻辑)
// assign rd_data = in_mem[rd_addr];  // 同拍出数据

// 新: 同步读 (1 拍延迟)
always @(posedge clk_core) begin
    rd_data <= in_mem[rd_addr];  // 下一拍出数据
end
```

影响：引擎读取 `in_mem` 需要提前 1 拍给地址。状态机需增加 1 拍预取。

#### 4.2.2 `tp_buf` 改同步读

同理，列引擎读 `tp_buf` 改同步读。列引擎的 `S_COL_START` 需增加预取周期。

#### 4.2.3 ROM 已是同步读

`u_row_rom`、`u_col_rom`、`u_lfnst_rom` 已经是同步读，无需改造。但 500MHz 下 BRAM 读延迟仍为 1 拍，需要确认 BRAM 在 500MHz 下能否工作（28nm SRAM 编译器典型 500ps，可行；Artix-7 BRAM Tco 1.846ns，不可行）。

### 4.3 MAC 流水线深化

#### 当前 2 级流水线

```
Stage 1: product = a * b          (16×16 → 32-bit)
Stage 2: result += sign_extend(product)  (40-bit accumulate)
```

#### 目标 4 级流水线

```
Stage 1: a_reg <= a; b_reg <= b; en_reg <= en; clr_reg <= clr
Stage 2: product <= a_reg * b_reg    (16×16 → 32-bit)
Stage 3: if (valid_s2) result <= result + sign_extend(product)
         // round/shift 可在此级
Stage 4: clip <= clip3(-512, 511, result[9:0])  // 10-bit 输出
         valid <= valid_s3
```

在 28nm 下，16×16 乘法 ~0.5ns，40-bit 加法 ~0.3ns，每级 < 1ns，500MHz 可行。

在 Artix-7 下，DSP48E1 内部流水线已固定（1 级乘 + 1 级累加），额外寄存器级在 DSP 外部实现。OOC 综合可量化实际延迟。

### 4.4 地址计算优化

#### 当前：组合逻辑乘法

```verilog
// its_top.v 中
assign row_eng_rd_addr = col_idx + row_idx * tu_width;  // 乘法
assign col_eng_rd_addr = row_idx + col_idx * tu_height;  // 乘法
```

#### 目标：递推计数器

```verilog
// 行引擎地址: base + col_idx, 每行结束 base += tu_width
reg [11:0] in_mem_base;
reg [11:0] in_mem_addr;

always @(posedge clk_core) begin
    if (state == S_ROW_START) begin
        in_mem_base <= in_mem_base_init;  // row_idx * tu_width (预计算)
        in_mem_addr <= in_mem_base_init;
    end else if (state == S_ROW_RUN && advance) begin
        in_mem_addr <= in_mem_addr + 1'b1;
    end
end

// base 更新: 每行结束时
if (row_done) in_mem_base <= in_mem_base + tu_width;
```

消除乘法器，地址计算变成简单的加法器 + 寄存器。

### 4.5 输出路径重构

原路径：`col_engine → out_mem (写) → out_mem (同步读) → data_out_r → OBUF → it_data_out`

新路径：`col_engine → out_mem (写) → out_mem (同步读) → output_fifo (写) → [CDC] → it_data_out`

关键改变：
- `out_mem` 写和读都在 `clk_core` 域
- 读出数据写入 `output_fifo`，不再直接驱动 OBUF
- `it_data_out` 从 `output_fifo` 在 `clk_if` 域读出
- 核心路径上无 OBUF，`out_mem` 读 → `output_fifo` 写可在 2ns 内完成

### 4.6 LFNST 流水线

当前 LFNST 单 MAC 串行处理。在 500MHz 下需要确保：

1. LFNST ROM 地址 → 系数读取 → MAC → 写回 每步不超过 2ns
2. ROM 已同步读（1 拍），MAC 需要在 1 拍内完成乘法（DSP48E1 可行）
3. 累加器流水化：每拍一个乘累加，4 级流水后每拍出一个结果

---

## 5. Wrapper 设计 (`its_top_500_wrapper`)

### 5.1 端口列表

```verilog
module its_top_500_wrapper (
    // 接口时钟域
    input  wire        clk_if,
    input  wire        rst_n,

    // 赛题接口 (clk_if 域)
    input  wire [21:0] it_info,
    input  wire        it_info_vld,
    input  wire [15:0] it_data_in,
    input  wire [11:0] it_data_addr,
    input  wire        it_data_in_vld,
    input  wire        it_data_end,
    output wire        it_data_in_req,
    output wire [39:0] it_data_out,
    output wire        it_data_out_vld,
    input  wire        it_data_out_req,
    output wire        it_done,

    // 核心时钟 (可外部输入或 MMCM 生成)
    input  wire        clk_core
);
```

### 5.2 内部结构

```
its_top_500_wrapper
├── rst_sync_if    // rst_n 同步到 clk_if 域
├── rst_sync_core  // rst_n 同步到 clk_core 域
├── cmd_fifo       // async FIFO, 23-bit, depth=4
│   ├── wr: clk_if (it_info + it_data_end)
│   └── rd: clk_core
├── input_fifo     // async FIFO, 28-bit, depth=16
│   ├── wr: clk_if (it_data_addr + it_data_in)
│   └── rd: clk_core
├── its_core_500   // 核心模块, clk_core 域
│   ├── cmd_decode
│   ├── in_mem
│   ├── u_lfnst + u_lfnst_rom
│   ├── u_row_engine + u_row_rom
│   ├── tp_buf
│   ├── u_col_engine + u_col_rom
│   └── out_mem → output_fifo_wr
├── output_fifo    // async FIFO, 40-bit, depth=16
│   ├── wr: clk_core
│   └── rd: clk_if
├── done_sync      // done 脉冲跨域同步 (2-FF)
└── output_ctrl    // clk_if 域输出控制
```

### 5.3 反压处理

| 信号 | 域 | 处理 |
|------|----|------|
| `it_data_in_req` | clk_if | `input_fifo_count < 12` (FIFO 未满即可接收) |
| `it_data_out_req` | clk_if | 直接控制 `output_fifo` 读使能 |
| core 输出反压 | clk_core | core 检查 `output_fifo_almost_full`，暂停输出阶段 |

---

## 6. OOC 综合策略

### 6.1 文件清单

| 文件 | 用途 |
|------|------|
| `rtl/its_core_500.v` | 核心模块 (不含 I/O pad) |
| `rtl/its_top_500_wrapper.v` | 双时钟 wrapper |
| `rtl/async_fifo.v` | Gray code 异步 FIFO |
| `synth/its_core_500_ooc.tcl` | OOC 综合脚本 |
| `synth/timing_core_500.xdc` | 核心时序约束 |

### 6.2 核心 OOC 约束

```tcl
# synth/timing_core_500.xdc

# 核心时钟 500MHz
create_clock -period 2.000 -name clk_core [get_ports clk_core]

# 输入延迟 (从 FIFO 读出到核心寄存器)
set_input_delay -clock clk_core -max 0.500 [get_ports {cmd_fifo_rdata* input_fifo_rdata*}]
set_input_delay -clock clk_core -min 0.100 [get_ports {cmd_fifo_rdata* input_fifo_rdata*}]

# 输出延迟 (从核心寄存器到 FIFO 写入)
set_output_delay -clock clk_core -max 0.500 [get_ports {output_fifo_wdata* output_fifo_wr_en}]
set_output_delay -clock clk_core -min 0.100 [get_ports {output_fifo_wdata* output_fifo_wr_en}]

# 禁止 OBUF/IOB (核心不接 I/O pad)
set_property IOSTANDARD LVCMOS33 [all_outputs]
# 不设 IOB 约束
```

### 6.3 OOC 综合流程

```tcl
# synth/its_core_500_ooc.tcl
create_project -in_memory -part xc7a200tfbg484-3

# 读取 RTL
read_verilog rtl/its_core_500.v
read_verilog rtl/its_transform_engine.v
read_verilog rtl/its_mac.v
read_verilog rtl/its_rom.v
read_verilog rtl/its_lfnst.v
read_verilog rtl/its_lfnst_rom.v

# 读取约束
read_xdc synth/timing_core_500.xdc

# OOC 综合
synth_design -top its_core_500 -mode out_of_context

# 实现
opt_design
place_design -directive Explore
route_design -directive Explore

# 报告
report_timing -setup -nworst 10 -file synth/core_500_timing_setup.rpt
report_timing -hold -nworst 10 -file synth/core_500_timing_hold.rpt
report_utilization -file synth/core_500_utilization.rpt
report_power -file synth/core_500_power.rpt
```

---

## 7. 阶段划分与验收

### 阶段 0：冻结当前稳定版 [已完成]

- [x] commit `d3e730b` 归档当前版本
- [x] 108/108 测试通过
- [x] Artix-7 顶层 ~96MHz
- [x] 不在原 `its_top` 上直接大改

### 阶段 1：定义双时钟架构 [当前]

- [ ] 形成本文档 `doc/500mhz_architecture_plan.md`
- [ ] 明确模块边界和信号协议
- [ ] 确认 FIFO 深度和位宽
- [ ] 验收：架构文档完整，信号协议无歧义

### 阶段 2：Core-only OOC 目标

- [ ] 新增 `rtl/its_core_500.v`（从 `its_top` 提取核心逻辑）
- [ ] 新增 `synth/its_core_500_ooc.tcl`
- [ ] 新增 `synth/timing_core_500.xdc`（2ns 约束）
- [ ] 核心 I/O 全部寄存化（无 OBUF/IOB）
- [ ] 跑 Vivado OOC 综合 + 实现
- [ ] 验收：生成 500MHz timing report，列出真实内部关键路径
- [ ] 输出：`synth/core_500_timing_setup.rpt`

### 阶段 3：重构核心内部长路径

按优先级逐项优化，每项后跑 OOC 综合验证 WNS 改善：

| 优先级 | 优化项 | 预期效果 |
|--------|--------|---------|
| P0 | `in_mem`/`tp_buf` 改同步读 | 消除异步读组合逻辑，释放 DistRAM LUT |
| P0 | 地址计算改递推计数器 | 消除乘法器，减少逻辑级数 |
| P1 | MAC 深化到 4 级流水 | 每级 < 1ns，500MHz 可行 |
| P1 | ROM 地址预计算寄存化 | ROM 地址 → 数据路径拆分 |
| P2 | LFNST 流水线优化 | ROM addr → coeff → MAC → writeback 分级 |
| P2 | 状态机拆分（前段/中段/后段） | 减少状态寄存器扇出 |

验收：core-only 2ns 下 WNS 逐轮改善，功能回归不掉（需写 core-only testbench）。

### 阶段 4：实现双时钟 Wrapper

- [ ] 新增 `rtl/async_fifo.v`（Gray code 异步 FIFO）
- [ ] 新增 `rtl/its_top_500_wrapper.v`
- [ ] 实例化 cmd_fifo、input_fifo、output_fifo
- [ ] 实现复位同步器（异步释放、同步断言）
- [ ] 实现 done 脉冲跨域同步（2-FF + 脉冲检测）
- [ ] 约束：`set_clock_groups -asynchronous -group clk_if -group clk_core`
- [ ] 验收：顶层接口仍兼容赛题，core 500MHz timing 独立成立，wrapper 低速域 timing 成立

### 阶段 5：双时钟验证

- [ ] 新增 `tb/its_tb_500.v`（双时钟 testbench）
- [ ] 通过原 108 个功能用例（输出仍 bit-exact 匹配 Python golden）
- [ ] 新增 CDC 边界压力用例：
  - 随机 `clk_if` 与 `clk_core` 相位关系
  - FIFO 满/空边界
  - 输出反压期间的 FIFO 溢出保护
  - 连续 TU 无间隔
- [ ] 验收：全部测试通过，0 协议违规

### 阶段 6：PPA 与报告更新

- [ ] `doc/core_500mhz_timing_report.md`：证明内部核心 500MHz
- [ ] `doc/top_wrapper_timing_report.md`：证明外部低速接口可工作
- [ ] 更新 `doc/ppa_report.md`：分 core/wrapper 两套 PPA
- [ ] 文档写清：500MHz 达成的是 `its_core_500`，外部接口运行在低速域

---

## 8. 风险与决策点

| 风险 | 影响 | 缓解 |
|------|------|------|
| Artix-7 BRAM Tco 1.846ns > 2ns | ROM/out_mem 在 500MHz 下不工作 | OOC 综合实测；若不行，ROM 改为分布式 RAM 或加 1 级流水 |
| DistRAM 改同步读后增加 1 拍延迟 | 状态机变长，吞吐量可能下降 | 流水线化，行/列变换可重叠 |
| 异步 FIFO 延迟 | TU 间延迟增加 | FIFO 深度足够，不影响吞吐量 |
| 28nm ASIC vs Artix-7 差异 | OOC 综合结果不代表 ASIC | OOC 综合用于量化差距，500MHz 最终目标为 ASIC |

**关键决策点：** 阶段 2 OOC 综合结果出来后，根据真实 WNS 决定是否需要大规模流水线化。如果 WNS 接近 0（如 -0.5ns 以内），只需微调；如果 WNS 很大（如 -2ns 以上），需要更激进的流水线拆分。

---

## 9. 资源估算

| 资源 | 当前 (its_top) | 预估 (core_500) | 预估 (wrapper+FIFO) | 总计 |
|------|---------------|-----------------|---------------------|------|
| LUT | 6,556 | ~8,000 (增加流水线寄存器) | ~500 (FIFO + CDC) | ~8,500 |
| Register | 2,329 | ~4,000 (流水线深化) | ~300 | ~4,300 |
| BRAM | 10.5 | 10.5 (不变) | 1.5 (3 个 FIFO) | 12 |
| DSP | 9 | 9 (不变) | 0 | 9 |

资源利用率仍很低（~6% LUT），有足够的余量。

---

## 10. 测试向量兼容性

现有 108 个测试用例的 golden reference 不变。双时钟 wrapper 的外部接口协议与原 `its_top` 完全一致，因此：

- 原 testbench `its_tb.v` 可直接用于 wrapper 顶层（将 DUT 替换为 `its_top_500_wrapper`）
- golden hex 文件不需要重新生成
- Python `ref_model.py` 不需要修改
- 新增的 CDC 测试用例是额外补充，不替代原有测试

---

*文档版本：v1.0*
*创建时间：2026-06-10*
*基于 commit: d3e730b*
