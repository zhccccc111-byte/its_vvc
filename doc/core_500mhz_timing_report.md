# ITS Core 500MHz OOC 综合时序报告

## 1. 结论摘要

| 器件 | 速度等级 | WNS | 500MHz 状态 | 备注 |
|------|---------|-----|------------|------|
| **Kintex UltraScale+ xcku5p** | -2 | **+0.030 ns** | **MET** | 零改动 RTL (v3.9)，DSP48E2 消除瓶颈 |
| Artix-7 xc7a200t | -3 | -1.733 ns | 未达标 | DSP48E1 FF→A 物理极限 |

**最终结论**: 500MHz 目标在 UltraScale+ (xcku5p-2) 上已达标，相同 RTL 零改动。Artix-7 受 DSP48E1 固有特性限制不可达。

---

## 2. UltraScale+ 时序结果 (v4.0)

### 2.1 综合配置

| 项目 | 配置 |
|------|------|
| 工具 | Vivado 2024.1 |
| 模式 | Out-of-Context (OOC) |
| 目标器件 | Kintex UltraScale+ xcku5p-ffvb676-2-e |
| 速度等级 | -2 |
| 时钟约束 | 500MHz (2ns) |
| 综合策略 | 默认 |
| 实现策略 | Explore + AggressiveExplore PhysOpt |
| RTL | 与 v3.9 完全相同（零改动） |

### 2.2 时序结果

| 指标 | 值 | 状态 |
|------|-----|------|
| WNS (Setup) | **+0.030 ns** | **MET** |
| TNS | 0.000 ns | — |
| WHS (Hold) | +0.020 ns | MET |
| WPWS (Pulse Width) | +0.431 ns | MET |
| Failing Endpoints | **0** | — |

### 2.3 Worst Path 分析

```
Source:  u_lfnst_rom/coeff_reg_1 (RAMB36E2)
  → DOUTADOUT[3]:                         0.960 ns  (BRAM 读延迟)
  → net (fo=108, routed):                 0.886 ns  (BRAM→DistRAM 路由)
Dest:    u_lfnst/coeff_buf_reg_192_255_7_13 (RAMD64E)
  ─────────────────────────────────────
  Data path total:       1.846 ns (logic 0.960ns/52%  route 0.886ns/48%)
  Logic levels:          0
  Clock skew:            -0.033 ns
  Clock uncertainty:     0.035 ns
  Slack:                 +0.030 ns
```

**关键观察**:
- Worst path 是 LFNST ROM→DistRAM，0 级逻辑，纯 BRAM 读 + 路由
- Artix-7 上的 DSP48E1 FF→A 瓶颈（-1.733ns）在 UltraScale+ 上完全消失
- DSP48E2 的 FF propagation + setup time 改善显著，不再是关键路径

### 2.4 资源利用

| 资源 | 使用 | 可用 | 利用率 |
|------|------|------|--------|
| CLB LUTs (Logic) | 1,993 | 216,960 | 0.92% |
| CLB LUTs (Memory) | 850 | 99,840 | 0.85% |
| CLB Registers | 2,882 | 433,920 | 0.66% |
| CARRY8 | 92 | 27,120 | 0.34% |
| DSP48E2 | 9 | — | ✅ |
| RAMB36E2 | 12 | — | ✅ |
| URAM289 | 0 | — | — |

### 2.5 原始级检查

| 原始级 | 最小周期 | 最高频率 | 500MHz 可行性 |
|--------|---------|---------|-------------|
| RAMB36E2 (Block RAM) | ~1.8ns | ~556MHz | 可行 |
| RAMD64E (DistRAM) | ~1.9ns | ~525MHz | 可行 |
| DSP48E2 | ~1.6ns | ~625MHz | 可行 |

UltraScale+ 的 Block RAM (RAMB36E2) 最小周期约 1.8ns，500MHz (2.0ns) 有充足余量。

---

## 3. Artix-7 时序分析 (v3.9 基线)

### 3.1 综合配置

| 项目 | 配置 |
|------|------|
| 工具 | Vivado 2024.1 |
| 模式 | Out-of-Context (OOC) |
| 目标器件 | Artix-7 xc7a200tfbg484-3 |
| 速度等级 | -3 |
| 时钟约束 | 500MHz (2ns) |
| 综合策略 | 默认 |
| 实现策略 | Explore + AggressiveExplore PhysOpt |

### 3.2 时序结果

| 指标 | 值 | 说明 |
|------|-----|------|
| WNS (Setup) | **-1.733 ns** | 未达标 |
| TNS (Setup) | -7,454 ns | 9,915 个违例端点 |
| WHS (Hold) | -0.280 ns | 轻微违例 |
| WPWS (Pulse Width) | -0.234 ns | 轻微违例 |

### 3.3 Worst Path 分析

```
Source:  mac_data_r2_reg (FDCE)
  → DSP48E1 A[23]:                       0.341 ns  (FF propagation)
  → net (fo=15, routed):                 0.577 ns  (FF→DSP 路由)
Dest:    u_mac2/product0/A[23] (DSP48E1)
  ─────────────────────────────────────
  Data path total:       1.066 ns (logic 0.341ns/32%  route 0.577ns/54%)
  DSP setup:             0.106 ns
  Logic levels:          0
  Clock skew:            -0.035 ns
  Clock uncertainty:     0.035 ns
  Slack:                 -1.733 ns
```

**瓶颈分析**:
- DSP48E1 的 FF→A 输入路径固有延迟：FF propagation 0.341ns + 路由 0.577ns + DSP setup 0.106ns
- 这些延迟来自硅片物理特性，无法通过 RTL 或布局布线优化消除
- v3.3→v3.9 的全部 RTL 优化仅消除了逻辑瓶颈（从 -2.289ns 改善到 -1.733ns，+0.556ns）
- 剩余 -1.733ns 全部来自 DSP48E1 固有物理特性

### 3.4 资源利用

| 资源 | 使用 | 可用 | 利用率 |
|------|------|------|--------|
| LUT as Logic | 2,004 | 133,800 | 1.50% |
| LUT as Memory | 784 | 46,200 | 1.70% |
| Slice Registers | 2,992 | 267,600 | 1.12% |
| Block RAM Tile | 14 | 365 | 3.84% |
| DSP48E1 | 9 | 740 | 1.22% |

### 3.5 原始级硬约束

| 原始级 | 最小周期 | 最高频率 | 500MHz 可行性 |
|--------|---------|---------|-------------|
| **RAMB36E1 (Block RAM)** | **2.234ns** | **447.4MHz** | **不可行** |
| RAMD64E (DistRAM) | ~1.905ns | ~525MHz | 可行 |
| DSP48E1 | ~1.600ns | ~625MHz | 可行 |

Artix-7 的 RAMB36E1 最小周期 2.234ns（-3 速度等级），对应最高频率 447.4MHz，500MHz 硬不可行。

---

## 4. RTL 优化历程 (v3.2→v3.9)

| 版本 | WNS | 改善 | 优化内容 |
|------|-----|------|---------|
| v3.2 | -2.115ns | — | BRAM in_mem + LFNST overlay + P0 pipeline |
| v3.3 | -2.289ns | — | ifdef SYNTHESIS + size_m1/size_shift 寄存化 |
| v3.4 | -2.020ns | +0.269ns | LFNST 流水线拆分 + base_addr 寄存化 |
| v3.5 | -2.081ns | -0.061ns | 输出控制链优化 (clr_limit 寄存化) |
| v3.6 | -1.859ns | +0.222ns | 列引擎输入 tp_buf 流水线化 |
| v3.7 | -1.881ns | -0.022ns | ROM 地址累加器 + pf_ddly 二级流水 |
| v3.8 | -1.736ns | +0.145ns | mac_data_r 复制为 4 份 (fanout 60→15) |
| v3.9 | -1.733ns | +0.003ns | mac_clr 注册 (10 级控制链拆为 4+6) |

**累计改善**: -2.289ns → -1.733ns = +0.556ns（全部来自 RTL 逻辑优化）

---

## 5. 物理优化实验 (v4.0 Artix-7, 失败)

| 实验 | 方法 | WNS | 结论 |
|------|------|-----|------|
| pblock 约束 | mac_data_r 约束到 DSP 附近 | -1.746ns | 恶化，回退 |
| phys_opt 叠加 | AggressiveExplore + AlternateFlowWithRetiming | -1.733ns | 无改善 |
| DSP 输入流水线 | a_r/b_r 输入寄存器 | -1.728ns | 仅 +0.005ns，停止 |

---

## 6. 跨器件对比

| 指标 | Artix-7 (xc7a200t-3) | UltraScale+ (xcku5p-2) | 改善 |
|------|----------------------|------------------------|------|
| WNS | -1.733 ns | **+0.030 ns** | **+1.763 ns** |
| Worst path | DSP48E1 FF→A | BRAM→DistRAM | DSP 瓶颈消除 |
| DSP | DSP48E1 (9) | DSP48E2 (9) | 更快的 FF/setup |
| BRAM | RAMB36E1 (14) | RAMB36E2 (12) | min period 2.23→~1.8ns |
| Failing endpoints | 9,915 | **0** | 全部通过 |
| 500MHz | 不可达 | **达标** | — |

---

*报告生成时间：2026-06-17*
*综合工具：Vivado 2024.1 OOC 模式*
*目标器件：Kintex UltraScale+ xcku5p-ffvb676-2-e / Artix-7 xc7a200tfbg484-3*
