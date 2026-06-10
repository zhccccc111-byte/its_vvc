# ITS Core 500MHz OOC 综合时序报告

## 1. 综合配置

| 项目 | 配置 |
|------|------|
| 工具 | Vivado 2024.1 |
| 模式 | Out-of-Context (OOC) |
| 目标器件 | Artix-7 xc7a200tfbg484-3 |
| 速度等级 | -3 |
| 时钟约束 | 500MHz (2ns) |
| 综合策略 | 默认 |
| 实现策略 | Explore + AggressiveExplore PhysOpt |

## 2. 时序结果

| 指标 | 值 | 说明 |
|------|-----|------|
| WNS (Setup) | **-5.213ns** | 违例 |
| TNS (Setup) | -89,197.4ns | 31,253 个违例端点 |
| WHS (Hold) | -0.230ns | 轻微违例 |
| WPWS (Pulse Width) | -0.234ns | 轻微违例 |
| 实际内部极限频率 | **~136MHz** | = 1/(2.0+5.213) ns |

## 3. 关键路径分析

### 3.1 最差路径

```
Source:  tu_width_reg[1]_replica_7 (FDCE)
  → LUT2 (ROM addr decode):         0.097 ns
  → LUT6 (coeff_buf addr):          0.097 ns  (fo=46, high fanout!)
  → LUT3 (addr computation):        0.097 ns
  → CARRY4 (addr adder):            0.432 ns
  → RAMD64E (coeff_buf read):       0.230 ns  (distributed RAM async read)
  → LUT6 (MAC input mux):           0.097 ns
Dest:    u_row_engine/u_mac3/product0/B[4] (DSP48E1)
  ─────────────────────────────────────
  Data path total:       4.699 ns (logic 1.443ns/30.7%, route 3.256ns/69.3%)
  Logic levels:          6
  Clock skew:            -0.035 ns (OOC, almost zero)
  Clock uncertainty:     0.035 ns
```

### 3.2 路径图示

```
tu_width_reg[1]  ──→  LUT2  ──→  LUT6  ──→  LUT3  ──→  CARRY4  ──→  RAMD64E  ──→  LUT6  ──→  DSP48E1
   (FDCE)          ROM addr   coeff_buf   addr calc    addr adder   coeff_buf    MAC mux    product0/B
                  decode      addr (fo=46)              (4-bit)     async read
```

### 3.3 瓶颈分解

| 组件 | 延迟 | 占比 | 说明 |
|------|------|------|------|
| **路由** | 3.256ns | 69.3% | 主要是 LUT6→CARRY4 (0.785ns) 和 RAMD64E→LUT6 (0.486ns) |
| CARRY4 | 0.432ns | 9.2% | 地址加法器，4-bit carry chain |
| FDCE (Q delay) | 0.393ns | 8.4% | 寄存器输出延迟 |
| RAMD64E | 0.230ns | 4.9% | 分布式 RAM 异步读 |
| LUT (各级) | 0.388ns | 8.2% | 4 级 LUT 合计 |
| **合计** | **4.699ns** | **100%** | |

### 3.4 关键发现

1. **6 级组合逻辑**：从 `tu_width_reg` 到 DSP 输入，中间经过 4 级 LUT + 1 级 CARRY4 + 1 级 RAMD64E。在 2ns 周期内不可能完成。

2. **高扇出 (fo=46)**：`size_shift[1]` 信号扇出 46，路由延迟 0.785ns。这是 `coeff_buf` 地址计算的一部分，被 4 个 MAC 共享。

3. **异步读 RAM 在关键路径上**：`coeff_buf` (DistRAM) 的异步读直接在组合逻辑链中。读地址来自 CARRY4 加法器，读出数据直接进 DSP。

4. **地址计算是乘法的一部分**：ROM 地址依赖 `tu_width`（运行时参数），`coeff_buf` 地址依赖 `size_shift` + `comp_col`，这些计算与 MAC 乘法串行。

## 4. 资源利用

| 资源 | 使用 | 可用 | 利用率 |
|------|------|------|--------|
| Slice LUTs | 7,179 | 133,800 | 5.37% |
|   LUT as Logic | 2,779 | | |
|   LUT as Memory (DistRAM) | 4,400 | 46,200 | 9.52% |
| Slice Registers | 2,529 | 267,600 | 0.95% |
| DSP48E1 | 9 | 740 | 1.22% |

## 5. Artix-7 原始级 500MHz 硬约束风险

### 5.1 Pulse Width 违例分析

| 检查项 | 类型 | 原始级 | 要求 | 实际 | 余量 | 违例端点 |
|--------|------|--------|------|------|------|---------|
| **Min Period** | WPWS | RAMB36E1/CLKARDCLK | 2.234ns | 2.000ns | **-0.234ns** | out_mem_reg |
| Low Pulse Width | WPWS | RAMD64E/CLK | 1.000ns | 1.050ns | +0.050ns | in_mem (DistRAM) |
| High Pulse Width | WPWS | RAMD64E/CLK | 1.000ns | 1.050ns | +0.050ns | in_mem (DistRAM) |

### 5.2 硬约束结论

| 原始级 | 最小周期 | 最高频率 | 500MHz 可行性 |
|--------|---------|---------|-------------|
| **RAMB36E1 (Block RAM)** | **2.234ns** | **447.4MHz** | **不可行** — 差 52.6MHz |
| RAMD64E (Distributed RAM) | ~1.905ns | ~525MHz | 可行（余量 50ps） |
| DSP48E1 | ~1.600ns | ~625MHz | 可行 |

**关键发现：**

1. **RAMB36E1 是 500MHz 的硬天花板。** Artix-7 Block RAM 的 CLKARDCLK 端口最小周期为 2.234ns（-3 速度等级），对应最高频率 447.4MHz。这是硅片物理限制，无法通过综合/布局布线优化消除。

2. **DistRAM 可以跑 500MHz。** RAMD64E 脉冲宽度余量 +50ps，勉强满足。但 `in_mem`（4096x16）和 `tp_buf`（4096x16）使用 DistRAM 实现，资源占用 4400 LUT (9.52%)，高扇出信号导致路由延迟大。

3. **DSP48E1 不是瓶颈。** DSP 最小周期约 1.6ns，500MHz (2.0ns) 有充足余量。

### 5.3 突破 500MHz 的架构选项

| 方案 | 目标频率 | 方法 | 代价 |
|------|---------|------|------|
| **A. 去掉 out_mem BRAM** | 500MHz | 输出直接从列引擎流式写出，不用 Block RAM 缓冲 | 需要输出端反压处理，增加控制复杂度 |
| **B. BRAM 2 分频** | 500MHz core, 250MHz BRAM | out_mem 用 2:1 时钟分频读写，core 侧用双端口 | 增加 1 拍延迟，需要 CDC |
| **C. 换器件 (Kintex-7 -2)** | 500MHz | RAMB36E1 min period ≈ 1.8ns (K7-2) | 成本增加，需确认器件可用性 |
| **D. 接受 447MHz** | 447MHz | 放弃 500MHz 目标，优化到 BRAM 极限 | 最简单，PPA 可能够用 |

**建议：** 方案 A（去掉 out_mem BRAM）最可行。当前 `out_mem` 仅用于输出重排序（列优先→光栅扫描），可以在列引擎输出时直接按光栅顺序写出，完全避免 Block RAM。

---

## 6. 优化路径分析

要达到 500MHz，关键路径需要从 4.699ns 降到 < 2ns。差距 **2.7ns**。

### 6.1 优化方案优先级

| 优先级 | 方案 | 预期效果 | 难度 |
|--------|------|---------|------|
| **P0** | `coeff_buf` 改同步读 + 流水线 | 拆断 RAMD64E 在关键路径上，减少 2 级逻辑 | 中 |
| **P0** | ROM 地址预计算寄存化 | 消除 `tu_width` 到 ROM 地址的组合路径 | 中 |
| **P1** | `size_shift` 信号寄存 + 复制 | 减少高扇出路由延迟 (0.785ns) | 低 |
| **P1** | MAC 输入寄存器 | 在 DSP 前加一级寄存，切断组合路径 | 低 |
| **P2** | `in_mem`/`tp_buf` 改同步读 | 消除 DistRAM 异步读，但增加 1 拍延迟 | 高 |
| **P2** | 地址计算改递推计数器 | 消除 CARRY4 加法器 | 中 |

### 6.2 预估优化效果

| 优化后路径 | 逻辑级数 | 预估延迟 | Fmax |
|-----------|---------|---------|------|
| 当前 | 6 | 4.699ns | ~136MHz |
| P0: coeff_buf 同步读 + ROM 地址寄存 | 3 (LUT→LUT→DSP) | ~2.0ns | ~330MHz |
| P0+P1: + 寄存器复制 + MAC 输入寄存 | 2 (LUT→DSP) | ~1.5ns | ~400MHz |
| P0+P1+P2: + 递推计数器 | 1 (DSP) | ~1.0ns | ~500MHz+ |

**注：** 以上为 Artix-7 -3 估算。28nm ASIC 下每级逻辑延迟约为 FPGA 的 1/3~1/4，6 级逻辑在 ASIC 下约 1.0ns，已可满足 500MHz。

## 7. 结论

| 维度 | 结果 |
|------|------|
| 内部逻辑极限 (FPGA Artix-7 -3) | **~136MHz** |
| 500MHz 差距 | 5.213ns (需减少 ~2.6ns) |
| 关键路径 | `tu_width → coeff_buf addr → DistRAM read → DSP` |
| 主要瓶颈 | 6 级组合逻辑 + 高扇出路由 |
| **BRAM 硬约束** | **RAMB36E1 min period 2.234ns → 最高 447.4MHz，500MHz 不可行** |
| DistRAM 约束 | RAMD64E 脉冲余量 +50ps，勉强满足 500MHz |
| ASIC 28nm 可行性 | **可行** (6 级逻辑 ~1.0ns < 2.0ns) |

**建议执行顺序：**
1. 先做 P0（coeff_buf 同步读 + ROM 地址寄存），预期 Fmax 提升到 ~330MHz
2. 再做 P1（寄存器复制 + MAC 输入寄存），预期 Fmax 提升到 ~400MHz
3. **评估 out_mem BRAM 去除方案**（消除 RAMB36E1 min period 硬约束）
4. 最后做 P2（递推计数器），冲击 500MHz
5. 每步后跑 OOC 综合验证 WNS 改善

**注意：** 如不去除 out_mem BRAM，FPGA 最高频率锁定在 ~447MHz。要真正达到 500MHz，必须消除所有 RAMB36E1 实例或更换器件族。

---

*报告生成时间：2026-06-10*
*综合工具：Vivado 2024.1 OOC 模式*
*目标器件：Artix-7 xc7a200tfbg484-3*
