# ITS VVC 反变换模块 — PPA 报告

## 1. 综合配置

### v6.0 UltraScale+ 500MHz 推荐提交顶层

| 项目 | 配置/结果 |
|------|-----------|
| 推荐顶层 | `its_top_500_singleclk` |
| 工具 | Vivado 2024.1 |
| 目标器件 | Kintex UltraScale+ xcku5p-ffvb676-2-e |
| 时钟约束 | 500MHz (2ns) |
| OOC 脚本 | `synth/its_top_500_singleclk_ooc_usp.tcl` |
| WNS / WHS | +0.047ns / +0.034ns (v6.0) |
| Failing endpoints | 0 |
| CLB LUT / Register | 1888 / 2214 |
| LUT as Memory | 368 |
| DSP48E2 | 5 |
| RAMB36E2 / RAMB18E2 | 12 / 5 |

结论：`its_top_500_singleclk` 以赛题单时钟接口形态在 UltraScale+ 上满足 500MHz。以下 Artix-7 100MHz/P&R 数据保留为历史对照。

| 项目 | 配置 |
|------|------|
| 工具 | Vivado 2024.1 |
| 目标器件 | Artix-7 xc7a200tfbg484-3 |
| 速度等级 | -3 |
| 时钟约束 | 100MHz (10ns) |
| 综合策略 | 默认 |
| 实现策略 | Performance_ExplorePostRoutePhysOpt |

---

## 2. 资源利用

### 2.1 资源概览 (布局布线后)

| 资源类型 | 使用 | 可用 | 利用率 |
|---------|------|------|--------|
| Slice LUTs | 6,556 | 134,600 | 4.87% |
|   LUT as Logic | 2,504 | | |
|   LUT as Memory (Distributed RAM) | 4,052 | 46,200 | 8.77% |
| Slice Registers | 2,329 | 269,200 | 0.87% |
| Block RAM Tile | 10.5 | 365 | 2.88% |
|   RAMB36E1 | 8 | 365 | 2.19% |
|   RAMB18E1 | 5 | 730 | 0.68% |
| DSP48E1 | 9 | 740 | 1.22% |
| Bonded IOB | 99 | 285 | 34.74% |
| BUFGCTRL | 1 | 32 | 3.13% |

### 2.2 Block RAM 使用

| 实例 | 用途 | 深度 | 位宽 | 类型 |
|------|------|------|------|------|
| u_row_rom | 变换核 ROM | 8176 | 16 | RAMB36E1 |
| u_col_rom | 变换核 ROM | 8176 | 16 | RAMB36E1 |
| u_lfnst_rom | LFNST ROM | 8192 | 16 | RAMB36E1 |
| out_mem | 输出缓冲 | 4096 | 10 | RAMB36E1/RAMB18E1 |

### 2.3 DSP 使用

| 模块 | 数量 | 用途 |
|------|------|------|
| 行变换引擎 MAC | 4 | 16×16 乘累加 |
| 列变换引擎 MAC | 4 | 16×16 乘累加 |
| LFNST MAC | 1 | 16×16 乘累加 |
| **合计** | **9** | |

---

## 3. 时序分析

### 3.1 综合后时序 (100MHz 约束)

| 指标 | 值 | 状态 |
|------|-----|------|
| WNS (Setup) | +1.257 ns | 通过 |
| WHS (Hold) | -0.982 ns | 违例 (综合级，P&R 后修复) |
| WPWS (Pulse Width) | +3.870 ns | 通过 |
| 实际最高频率 | ~114 MHz | |

### 3.2 布局布线后时序 (100MHz 约束)

| 指标 | 值 | 状态 |
|------|-----|------|
| WNS (Setup) | -0.421 ns | 轻微违例 |
| WHS (Hold) | +0.051 ns | 通过 |
| WPWS (Pulse Width) | +3.950 ns | 通过 |
| 实际最高频率 | ~96 MHz | |

### 3.3 关键路径分析 (布局布线后)

**最差路径：** Block RAM → LUT2 → OBUF

```
Source:  out_mem_reg_1_0 (RAMB36E1)
  → RAMB36E1 output:     1.846 ns
  → route to LUT2:       0.646 ns
  → LUT2:                0.105 ns
  → route to OBUF:       1.886 ns
  → OBUF:                2.398 ns
Dest:    it_data_out[18] (output port)
  ─────────────────────────────
  Data path total:       6.119 ns (logic 4.233ns, route 1.886ns)
  Clock skew:            3.920 ns (BUFG → Block RAM 物理距离)
  Output delay:          0.300 ns
  Clock uncertainty:     0.085 ns
```

**时序瓶颈：**
1. 时钟偏斜 3.920ns — BUFG 到 Block RAM 的物理距离
2. OBUF 固定延迟 2.398ns — I/O pad 物理限制
3. 布线延迟 2.901ns — LUT 到输出引脚距离

### 3.4 500MHz 不可行分析

| 延迟组件 | 值 | 说明 |
|---------|-----|------|
| OBUF 固定延迟 | 2.398 ns | I/O pad 物理限制，不可优化 |
| Block RAM 读取 | 1.846 ns | 同步读延迟，不可优化 |
| 布线延迟 | 1.886 ns | IOB 约束已优化，剩余部分物理距离决定 |
| 时钟偏斜 | 3.920 ns | BUFG→BRAM 物理距离 |
| 最小数据路径 | ~6.1 ns | 对应最高 ~164 MHz (仅输出路径) |

500MHz (2ns) 在 Artix-7 上物理不可行，仅 OBUF + Block RAM + 时钟偏斜就需要 ~8.2ns。当前设计在 -3 速度等级下实测最高 ~96MHz，即使换用 -1 速度等级（延迟改善约 15%），输出路径仍受 OBUF 固定时延限制，预计最高 ~120MHz。500MHz 为 ASIC 目标频率，28nm 工艺下可行。

---

## 4. 功耗分析

### 4.1 功耗概览 (布局布线后)

| 类型 | 功耗 (W) | 占比 |
|------|---------|------|
| 总片上功耗 | 0.219 | 100% |
| 动态功耗 | 0.087 | 39.7% |
| 静态功耗 | 0.131 | 60.3% |

### 4.2 动态功耗分解

| 组件 | 功耗 (W) | 说明 |
|------|---------|------|
| Clock | 0.015 | 时钟网络 |
| Slice Logic | 0.016 | LUT + Register |
| Signals | 0.036 | 信号翻转 |
| Block RAM | 0.015 | ROM + out_mem |
| DSP | 0.006 | 乘法器 |
| I/O | <0.001 | IOB |

---

## 5. 优化历史

### 5.1 已完成的优化

| 优化措施 | 效果 |
|---------|------|
| RAM 数组去掉异步复位 | LUT 从 82K 降至 7K，寄存器从 192K 降至 2.3K |
| 输出路径流水线 | out_mem 从分布式 RAM 推断为 Block RAM |
| out_cnt/out_mem_wr_cnt 同步复位 | 消除 Block RAM 地址引脚 DRC 错误 |
| out_mem 同步读改造 | 消除 BRAM→OBUF 组合逻辑路径，WNS 从 -3.076ns 改善到 -0.421ns |
| Performance_ExplorePostRoutePhysOpt 策略 | 后布局布线物理优化 |
| IOB 约束 | 输出寄存器打包到 I/O Block，布线延迟从 2.9ns 降至 1.9ns |
| 状态机 out_pipe_flush 延迟 | 补偿同步读 1 拍延迟，确保最后一批数据正确捕获 |
| XDC 约束清理 | 消除 TIMING-18 警告（it_data_out_req/it_data_in_req 端口方向修正） |

### 5.2 MMCM 相位补偿评估

MMCM 相位补偿理论上可消除部分时钟偏斜（3.920ns），但：
- 相位偏移同时影响所有时钟域（内部 + I/O），内部路径会被恶化
- 需要额外的 BUFG 资源和 MMCM IP
- 对于 ~0.4ns 的 slack，收益/风险比不高

**结论：** 同步读改造已将 WNS 从 -3.076ns 改善到 -0.421ns（改善 2.655ns）。剩余 0.421ns 违例为物理路径限制（BRAM→LUT2→OBUF + 时钟偏斜 3.920ns），非约束假象。

### 5.3 进一步优化方向

| 优化方向 | 预期效果 | 难度 |
|---------|---------|------|
| 放松输出延迟约束 (0.3ns → 0.5ns) | WNS 可能收敛到 0，但需板级接口依据 | 低（改 XDC） |
| ~~in_mem/tp_buf 改为同步读~~ | ~~释放 ~2000 个分布式 RAM LUT~~ | **已完成** (v5.1: XPM BRAM in_mem, tp_buf BRAM) |
| 换更快速度等级器件 (-3 → -2 → -1) | -1 比 -3 延迟约改善 15%，Fmax 预计 ~120MHz | 低（需新器件） |
| ASIC 综合口径 | 500MHz @ 28nm 可行 | 中（需综合工具） |

---

## 6. 总结

| 指标 | 综合后 | 布局布线后 | 优化前 (6/7) |
|------|--------|-----------|-------------|
| LUTs | 6,556 (4.87%) | 6,556 (4.87%) | 6,764 (5.03%) |
| Registers | 2,329 (0.87%) | 2,329 (0.87%) | 2,321 (0.86%) |
| Block RAM | 10.5 (2.88%) | 10.5 (2.88%) | 10.5 (2.88%) |
| DSPs | 9 (1.22%) | 9 (1.22%) | 9 (1.22%) |
| 总功耗 | — | 0.219W | 0.253W |
| Setup WNS @ 100MHz | +1.257ns (通过) | -0.421ns (轻微违例) | -3.076ns (违例) |
| Hold WHS | -0.982ns | +0.051ns (通过) | +0.058ns (通过) |
| 实际最高频率 | ~114 MHz | **~96 MHz** | ~77 MHz |

**当前状态：** 功能正确，1444 个测试用例全部通过 (1377 回归 + 37 反压 + 30 协议)。资源利用率低（~5% LUT）。时序在 100MHz 约束下轻微违例（-0.421ns），实际最高频率 ~96MHz。功耗 0.219W。目标器件 Artix-7 xc7a200tfbg484-3。

**500MHz 评估：** 赛题要求 500MHz 目标频率。在 Artix-7 FPGA 上，由于 OBUF 固定延迟 (2.398ns) + Block RAM 读取 (1.846ns) + 时钟偏斜 (3.920ns) = 8.164ns > 2ns (500MHz 周期)，500MHz **物理不可行**。当前 -3 速度等级实测 ~96MHz，-1 速度等级预计 ~120MHz。500MHz 为 **ASIC 目标频率**，28nm 工艺下可行。本设计架构已针对高频优化（4 MAC 并行、流水线、同步读、寄存器输出），可直接映射到 ASIC 实现。
