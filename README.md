# VVC 反变换模块 (ITS) — RTL 实现

第九届中国研究生创芯大赛 · 华为赛题一

---

## 1. 项目概述

本项目实现了 VVC (H.266) 视频编码标准的反变换模块 (Inverse Transform Subsystem, ITS)，用于解码端将频域系数还原为时域残差信号。

### 核心能力

| 特性 | 说明 |
|------|------|
| 变换类型 | DCT2、DCT8、DST7 三种反变换核 |
| 块大小 | DCT2: 4x4 ~ 64x64 (25种)；DCT8/DST7: 4x4 ~ 32x32 (各16种) |
| LFNST | 支持 nTrs=16 (4x4/8x8 TU) 和 nTrs=48 (其他 TU)，4 setIdx x 2 idx |
| 计算性能 | 4 个并行 MAC，每周期产出 4 个结果点 |
| 接口 | 22-bit it_info，符合赛题规范 |
| 反压 | 输入/输出均支持按点反压 (backpressure) |

### 处理流程

```
输入数据 → [LFNST 反变换] → 行方向 1D IDCT/IDST → 转置 → 列方向 1D IDCT/IDST → 光栅扫描输出
```

---

## 2. 目录结构

```
its_vvc/
├── rtl/                            # RTL 源代码
│   ├── its_top.v                   # 顶层模块 (状态机 + 数据通路)
│   ├── its_transform_engine.v      # 1D 变换引擎 (4 MAC 并行)
│   ├── its_mac.v                   # 流水线乘累加单元
│   ├── its_rom.v                   # 变换核 ROM (8176 系数)
│   ├── its_lfnst.v                 # LFNST 反变换模块
│   ├── its_lfnst_rom.v             # LFNST 系数 ROM (8192 系数)
│   ├── rom_coeffs.hex              # 变换核系数数据
│   └── lfnst_coeffs.hex            # LFNST 系数数据
├── tb/
│   ├── its_tb.v                    # 测试平台 (11 个测试用例)
│   └── test_vectors/               # 测试向量 (.hex 文件)
├── sim/
│   ├── run.do                      # ModelSim 仿真脚本
│   ├── rom_coeffs.hex              # 变换核系数 (symlink)
│   └── lfnst_coeffs.hex            # LFNST 系数 (symlink)
├── synth/
│   ├── its_synth.tcl               # Vivado 综合脚本
│   └── timing.xdc                  # 时序约束
└── scripts/
    ├── gen_rom_coeffs.py           # 变换核系数生成
    ├── gen_test_vectors.py         # 测试向量生成
    ├── ref_model.py                # Python 参考模型 (golden model)
    └── parse_lfnst_matrices.py     # LFNST 矩阵解析
```

---

## 3. 接口定义

### 3.1 顶层端口

| 信号 | 位宽 | 方向 | 说明 |
|------|------|------|------|
| `clk` | 1 | I | 时钟 (目标 500MHz) |
| `rst_n` | 1 | I | 异步复位，低有效 |
| `it_info` | 22 | I | TU 信息总线 (见下表) |
| `it_info_vld` | 1 | I | 信息有效，脉冲 |
| `it_data_in` | 16 | I | 输入系数 (有符号，只送非零点) |
| `it_data_addr` | 12 | I | 系数在 TU 内的光栅扫描地址 |
| `it_data_in_vld` | 1 | I | 输入数据有效 |
| `it_data_in_req` | 1 | O | 输入请求 (为 1 时才允许送数据) |
| `it_data_out` | 40 | O | 输出结果，4 个 10-bit 有符号值拼接 |
| `it_data_out_vld` | 1 | O | 输出有效 |
| `it_data_out_req` | 1 | I | 输出反压 (为 1 时才允许输出) |
| `it_done` | 1 | O | 当前 TU 处理完成，脉冲 |

### 3.2 it_info 位域定义

```
it_info [21:0]
├── [6:0]      tu_width          — TU 宽度 (4/8/16/32/64)
├── [13:7]     tu_height         — TU 高度 (4/8/16/32/64)
├── [15:14]    tr_type_hor       — 水平变换类型 (0=DCT2, 1=DCT8, 2=DST7)
├── [17:16]    tr_type_ver       — 垂直变换类型
├── [19:18]    lfnst_tr_set_idx  — LFNST 变换集索引 (0..3)
└── [21:20]    lfnst_idx         — LFNST 核索引 (0=不启用, 1/2)
```

### 3.3 输出数据格式

`it_data_out[39:0]` 按光栅扫描顺序打包 4 个结果点：

```
[9:0]    — 第 1 个点 (有符号 10-bit)
[19:10]  — 第 2 个点
[29:20]  — 第 3 个点
[39:30]  — 第 4 个点
```

---

## 4. 架构设计

### 4.1 顶层状态机

```
                          ┌──────────────────────────────────────────────────────┐
                          │                                                      │
  S_IDLE ──→ S_LOAD ──→ [S_LFNST] ──→ S_ROW_START ──→ S_ROW_RUN ──┐            │
              (输入)      (可选)         (行变换)                    │ 循环       │
                                                    ┌──────────────┘ height 次  │
                                                    ▼                            │
                                              S_COL_START ──→ S_COL_RUN ──┐      │
                                                   (列变换)               │ 循环 │
                                                    ┌────────────────────┘      │
                                                    ▼          width 次         │
                                              S_OUT ──→ S_DONE ──→ S_IDLE ──────┘
                                            (光栅输出)
```

### 4.2 LFNST 模块 (`its_lfnst.v`)

执行 LFNST 反变换：`y[i] = clip3(-32768, 32767, (Σ_j T[i][j]·x[j] + 64) >> 7)`

**nTrs 定义（官方 VVC 标准）：**
- `nTrs = (tu_width >= 8 && tu_height >= 8) ? 48 : 16`
- nTrs=16: 16 个输入，16x16 矩阵，16 个输出（写回左上 4x4）
- nTrs=48: 16 个输入（左上 4x4），48x16 矩阵，48 个输出（写回 3 个 4x4 子块）

**nTrs=48 子块布局：**
```
┌───────┬───────┐
│ blk 0 │ blk 1 │  rows 0-3, cols 0-7
│ (4x4) │ (4x4) │
├───────┤       │
│ blk 2 │       │  rows 4-7, cols 0-3
│ (4x4) │       │
└───────┴───────┘
```

**ROM 布局（8192 条目）：**
- nTrs=16 [0..2047]: 4 setIdx x 2 idx x 16x16
- nTrs=48 [2048..8191]: 4 setIdx x 2 idx x 48x16

### 4.3 变换引擎 (`its_transform_engine.v`)

4 个并行 MAC 执行一维反变换 `y = T^T * x`。

- S_LOAD: 加载 N 个输入到 line_buf
- S_PREFETCH: 从 ROM 预取 4 行系数到 coeff_buf
- S_COMPUTE: 4 MAC 并行计算 4 个输出点
- S_OUTPUT: 输出结果，`(sum + 32) >>> 6`

### 4.4 MAC 单元 (`its_mac.v`)

2 级流水线乘累加器：
- Stage 1: `product = a * b` (16x16 → 32-bit signed)
- Stage 2: `result += sign_ext(product)` (40-bit accumulator)

---

## 5. 仿真与验证

### 5.1 运行仿真

```bash
cd sim
vsim -c -do "do run.do"
```

预期输出: `ALL TESTS PASSED!`，11 个测试用例全部通过。

### 5.2 测试用例覆盖

| 编号 | 变换类型 | 块大小 | LFNST set/idx | 说明 |
|------|---------|--------|--------------|------|
| 1 | DCT2 | 8x8 | - | 基础 DCT2 |
| 2 | DCT2 | 16x16 | - | 大块 DCT2 |
| 3 | DCT8 | 4x4 | - | DCT8 变换 |
| 4 | DST7 | 4x4 | - | DST7 变换 |
| 5 | DCT8 | 8x8 | - | 大块 DCT8 |
| 6 | DCT2 | 4x4 | 0/1 | LFNST nTrs=16 |
| 7 | DCT2 | 4x4 | 0/2 | LFNST nTrs=16 |
| 8 | DCT2 | 4x4 | 1/1 | LFNST 不同 setIdx |
| 9 | DCT2 | 8x8 | 0/1 | LFNST nTrs=48 |
| 10 | DCT2 | 8x8 | 0/2 | LFNST nTrs=48 |
| 11 | DCT2 | 16x16 | 0/1 | LFNST nTrs=48 |

---

## 6. 综合与 PPA

### 6.1 综合结果

**目标器件**: Artix-7 xc7a200tfbg484-1
**时钟约束**: 500MHz (2ns)

| 资源 | 使用 | 可用 | 利用率 |
|------|------|------|--------|
| LUTs | 82,632 | 134,600 | 61.39% |
| Registers | 192,924 | 269,200 | 71.67% |
| Block RAM | 4 | 365 | 1.10% |
| DSPs | 9 | 740 | 1.22% |

| 指标 | 值 |
|------|-----|
| 总功耗 | 3.286 W |
| WNS (Setup) | -9.531 ns |

**说明**: 寄存器数偏高是因为多个 RAM 数组因异步复位被综合为触发器而非 Block RAM。时序不满足 500MHz 是原型阶段预期行为。

### 6.2 运行综合

```bash
cd synth
vivado -mode batch -source its_synth.tcl
```

---

## 7. 赛题要求对照

| 赛题要求 | 实现状态 | 说明 |
|---------|---------|------|
| DCT2 4x4~64x64 | ✅ | 25 种组合全部支持 |
| DCT8 4x4~32x32 | ✅ | 16 种组合全部支持 |
| DST7 4x4~32x32 | ✅ | 16 种组合全部支持 |
| LFNST (全部 16 场景) | ✅ | 4 setIdx x 2 idx x 2 nTrs |
| 22-bit it_info 接口 | ✅ | 符合赛题位域定义 |
| 一拍 4 点计算 | ✅ | 4 MAC 并行 |
| 一拍 4 点输出 | ✅ | 光栅扫描顺序 |
| 输入反压 | ✅ | it_data_in_req |
| 输出反压 | ✅ | it_data_out_req |
| Verilog 实现 | ✅ | |
| 500MHz 主频 | ⏳ | 综合时序待优化 |
| PPA 优化 | ⏳ | 面积/功耗待优化 |
| 设计文档 | ⏳ | 待编写 |

---

## 8. 工具与环境

| 工具 | 版本 | 用途 |
|------|------|------|
| ModelSim | SE-64 10.6e | 功能仿真 |
| Vivado | 2024.1 | 综合与实现 |
| Python | 3.x | 系数生成、参考模型 |
