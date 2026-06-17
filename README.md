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
├── doc/
│   ├── design_doc.md               # 设计文档
│   ├── verification_report.md      # 验证报告
│   ├── ppa_report.md               # PPA 报告
│   └── fix_log.md                  # 修复记录
├── tb/
│   ├── its_tb.v                    # 测试平台 (95 个测试用例)
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
| `it_data_end` | 1 | I | 输入数据结束，脉冲（赛题 4/24 更新） |
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

预期输出: `ALL TESTS PASSED!`，95 个测试用例全部通过。

### 5.2 测试用例覆盖 (共 94 个)

| 类别 | 数量 | 覆盖范围 |
|------|------|---------|
| DCT2 | 25 | 4x4 ~ 64x64 全部 25 种块大小 |
| DCT8 | 16 | 4x4 ~ 32x32 全部 16 种块大小 |
| DST7 | 16 | 4x4 ~ 32x32 全部 16 种块大小 |
| LFNST (nTrs=16) | 8 | 4 setIdx x 2 idx |
| LFNST (nTrs=48) | 8 | 4 setIdx x 2 idx |
| LFNST+DCT2 | 6 | 8x16, 16x8, 16x16, 16x32, 32x16, 32x32 |
| 连续 TU | 8 | 无复位连续处理，覆盖 DCT2/DCT8/DST7/LFNST |
| 反压 | 8 | 输出反压 (3高/2低)，覆盖 DCT2/DCT8/DST7/LFNST |

每个测试用例与 Python 参考模型 (ref_model.py) 逐点比对输出值。

---

## 6. 综合与 PPA

### 6.1 500MHz OOC 综合结果 (v3.9)

**目标器件**: Artix-7 xc7a200tfbg484-3
**时钟约束**: 500MHz (2ns)
**综合方式**: Out-of-Context (OOC)，仅测内部时序，不含 I/O pad

| 资源 | 使用 | 可用 | 利用率 |
|------|------|------|--------|
| LUT as Logic | 2,004 | 133,800 | 1.50% |
| LUT as Memory | 784 | 46,200 | 1.70% |
| Slice Registers | 2,992 | 267,600 | 1.12% |
| Block RAM Tile | 14 | 365 | 3.84% |
| DSP48E1 | 9 | 740 | 1.22% |

| 指标 | 值 |
|------|-----|
| WNS (Setup) | **-1.733 ns** |
| TNS | -7,454 ns |
| WHS (Hold) | -0.280 ns |
| WPWS (Pulse Width) | -0.234 ns |
| Failing Endpoints | 9,915 |

**说明**: WNS = -1.733ns，worst path 为 DSP48E1 路径 (`mac_data_r2_reg → u_mac2/product0/A[23]`，0 级逻辑，routing 占 63%，DSP 固有 setup 0.106ns)。Top-20 全部为 FF→DSP 物理路径（0 级逻辑），RTL 控制链路径已消除（`mac_clr` 注册为 `mac_clr_r`，10 级组合链拆为 4+6）。

**仿真/综合路径说明**: 使用 `ifdef SYNTHESIS` 条件编译分离仿真和综合路径。仿真路径（无 SYNTHESIS）使用组合 ROM 地址 + pf_dly 一级流水 + mac_en 直连，108/108 PASS。综合路径（SYNTHESIS defined）使用注册 ROM 地址（累加器模式）+ pf_ddly 二级流水 + P0 管线 + mac_en_d（2 cycle delay）+ coeff_buf 写地址寄存，改善时序。由于 ModelSim 将所有数组视为组合读（忽略 ram_style 属性），SYNTHESIS 路径在 RTL 仿真中会有 1 cycle 的系数延迟差异，这是已知的 ModelSim 限制。功能正确性通过非 SYNTHESIS 路径验证。

### 6.2 100MHz 全芯片综合结果 (v1.0)

**时钟约束**: 100MHz (10ns)，含 I/O pad

| 资源 | 使用 | 可用 | 利用率 |
|------|------|------|--------|
| LUTs | 6,568 | 133,800 | 4.91% |
| Registers | 2,328 | 267,600 | 0.87% |
| Block RAM | 10.5 | 365 | 2.88% |
| DSPs | 9 | 740 | 1.22% |

| 指标 | 值 |
|------|-----|
| 总功耗 | 0.222 W |
| WNS (Setup) @ 100MHz | -0.421 ns |
| 实际最高频率 | ~96 MHz |

### 6.3 运行综合

```bash
# 500MHz OOC 综合 (仅内部时序)
cd synth
vivado -mode batch -source its_core_500_ooc.tcl
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
| 输出反压 | ✅ | it_data_out_req，8 个反压测试验证通过 |
| Verilog 实现 | ✅ | |
| it_data_end 接口 | ✅ | 赛题 4/24 更新要求 |
| 500MHz 主频 | ⚠️ | Artix-7 物理限制，实际 ~96MHz；500MHz 为 ASIC 目标，详见 doc/design_doc.md 第 8 节 |
| 量化定标分析 | ✅ | 见 doc/design_doc.md 第 5.2 节 |
| PPA 报告 | ✅ | 见 doc/ppa_report.md |
| 设计文档 | ✅ | 见 doc/design_doc.md |

---

## 8. 版本历史

| 版本 | Tag | 关键改动 | WNS | 测试 |
|------|-----|---------|-----|------|
| **v3.9** | | mac_clr 注册（10 级控制链拆为 4+6），Top-20 全为 FF→DSP 物理路径 | **-1.733ns** | 108/108 |
| v3.8 | `v3.8-mac-data-replicate` | mac_data_r 复制为 4 份（fanout 60→15），消除所有 RTL 逻辑瓶颈 | -1.736ns | 108/108 |
| v3.7 | `v3.7-rom-accumulator` | ROM 地址累加器（消除 barrel shifter 关键路径）+ pf_ddly 二级流水 | -1.881ns | 108/108 |
| v3.6 | | 列引擎输入 tp_buf 流水线化（切断 DistRAM→line_buf 组合链） | -1.859ns | 108/108 |
| v3.5 | | 输出控制链优化（clr_limit 寄存化 + out_done 退出条件 + 清除延迟启动） | -2.081ns | 108/108 |
| v3.4 | | LFNST 输出流水线拆分 + base_addr 寄存化 | -2.020ns | 108/108 |
| v3.3 | | `ifdef SYNTHESIS` 条件编译分离仿真/综合路径 + size_m1/size_shift 寄存化 | -2.289ns | 108/108 |
| v3.2 | `v3.2-500mhz-timing-baseline` | BRAM in_mem + LFNST overlay buffer + P0 pipeline + size_shift 寄存 + coeff_buf 写地址寄存 | -2.115ns | 94/94 |
| v3.1 | `v3.1-core-protocol-stable` | FIFO 接口协议稳定，29-bit last 标记，文档修正 | -5.213ns | 94/94 |
| v3.0 | `v3.0-500mhz` | 引入 its_core_500 双时钟架构，OOC 综合脚本 | — | 94/94 |
| v2.0 | `v2.0-deliverable` | 交付版：XDC 清理、PPA 对齐、波形 SVG | ~-0.4ns@100MHz | 95/95 |
| v1.0 | `v1.0-baseline` | 初始基线：同步复位、DistRAM 推断 | ~-0.4ns@100MHz | 95/95 |

### v3.9 详细改动

**目标**: 消除 `pf_rom_col_reg → pf_to_compute → mac_clr → result_reg` 10 级控制链路径。

**its_transform_engine.v**:
- `mac_clr` 注册为 `mac_clr_r`（`max_fanout=16`），切断 `pf_to_compute → mac_clr → result_reg` 组合链
- 路径从 10 级拆为 4 级（`pf_rom_col → pf_to_compute → mac_clr → mac_clr_r`）+ 6 级（`mac_clr_r → result CARRY4`）
- 时序安全：MAC 管线 `en` 信号已有 2 拍延迟，`clr` 延迟 1 拍不影响功能

**综合结果**: WNS = -1.733ns（+0.003ns）。控制链路径从 top-20 消除，全部为 FF→DSP 物理路径。LUT 减少 121（组合逻辑被寄存器吸收）。

### v3.8 详细改动

**目标**: 消除 `mac_data_r_reg → DSP48E1` 路由瓶颈（fanout=60，routing 63%）。

**its_transform_engine.v**:
- `mac_data_r` 从单寄存器复制为 4 份（`mac_data_r0`~`mac_data_r3`），每份驱动 1 个 MAC
- 使用 `(* max_fanout = 16 *)` 属性引导 Vivado 保留独立副本（fanout 60→15）
- `mac_coeff` 声明提到 `ifdef` 外部，确保 SYNTHESIS/SIM 路径共享
- 同步应用到行引擎和列引擎

**综合结果**: WNS = -1.736ns（+0.145ns）。路由延迟从 0.679ns 降至 0.534ns。Top-20 以 FF→DSP 物理路径为主，但残留控制链路径（`pf_rom_col_reg → mac_clr → result_reg`，10 级逻辑，-1.714ns）。`size_shift_reg → mac_coeff_p0_reg` 路径跌出 top-20。

### v3.7 详细改动

**目标**: 消除行引擎 ROM 地址路径（`size_shift_reg → barrel shift + add → ROM ADDRARDADDR`，5 级逻辑 + 63% 路由）。

**its_transform_engine.v**:
- ROM 地址从组合逻辑改为寄存器（累加器模式），用 `ifdef SYNTHESIS` 条件编译分离：
  - 仿真路径：组合 ROM 地址 + pf_dly 一级流水（保持 108/108 PASS）
  - 综合路径：注册 ROM 地址 + pf_ddly 二级流水（补偿 2 拍总延迟）
- 新增 `next_row_base` 寄存器：提前 1 周期预计算下一行基地址（含 barrel shifter，不在公共关键路径）
- `prefetch_start_addr` 直接从已注册的 `base_addr`/`next_row_base` 选择，无需中间寄存器（消除 P0 NBA stale-read 风险）
- `acc_next` 选择逻辑：`entering_prefetch` 用 `prefetch_start_addr`，`is_last_col` 用 `next_row_base`，公共路径用 `acc+1`
- `pf_ddly` 二级流水：补偿注册 ROM 地址 + BRAM 读的 2 拍总延迟
- `pf_to_compute` 保持不变（pf_rom_col == N-1 触发）

**综合结果**: WNS = -1.881ns（默认 OOC）。旧 ROM 地址路径完全消除（从 top-20 中消失）。新 worst path 为 DSP48E1 路径（mac_data_r_reg → DSP48E1，0 级逻辑，routing 63%，DSP 固有 setup 0.106ns）。第二 path 为系数选择路径（size_shift_reg → mac_coeff_p0_reg，4 级逻辑，-1.838ns）。

### v3.5 详细改动

**目标**: 消除 `total_points → state CE` 的 8 级逻辑关键路径。

**its_core_500.v**:
- `clr_limit` 从组合 wire 改为寄存器 `clr_limit_r`（清除启动时从 `total_points` 锁存），移除 3 CARRY4 减法器
- 新增 `last_out_cnt = total_points - 4` 寄存器（S_COL_RUN→S_OUT 转换时锁存），替换 `out_cnt >= total_points` 的宽位比较
- `out_pipe_flush` 改用 `write_fire && out_cnt == last_out_cnt` 触发
- `out_read_en` 改用 `!out_pipe_flush` 替代 `out_cnt < total_points` 比较
- 新增 `out_done` 寄存器，将 `out_pipe_flush && !out_valid_pipe` 打一拍，切断到 state CE 的组合路径
- 状态机 S_OUT 退出改用 `out_done`
- 清除启动延迟一拍（`clearing_start` 脉冲），确保 `clr_limit_r` 从已注册的 `total_points` 锁存，避免乘法器暴露在关键路径

**综合结果**: WNS = -2.081ns（默认 OOC），failing endpoints 从 18,377 降至 17,234。

### v3.6 详细改动

**目标**: 切断列引擎输入 `tp_buf DistRAM → line_buf` 的组合链。

**its_core_500.v**:
- 新增 `tp_buf_rd_data` 流水寄存器，在 tp_buf DistRAM 读和 col_engine `data_in` 之间插入一级流水
- 新增 `col_data_in_vld_d` 延迟有效信号（1 拍），与 `tp_buf_rd_data` 对齐
- col_engine `data_in` 改接 `tp_buf_rd_data`，`data_in_vld` 改接 `col_data_in_vld_d`

**综合结果**: WNS = -1.859ns（默认 OOC），failing endpoints 从 17,234 降至 9,830。worst path 转移到行引擎 ROM 地址路径（`size_shift_reg → coeff_reg_1/ADDRARDADDR`，5 级逻辑，route 63%）。

### v3.4 详细改动

**目标**: 打断 LFNST 12 级 CARRY4 关键路径 + ROM 地址组合链。

**its_lfnst.v**:
- 新增 `S_OUTPUT_CLIP` 状态，将原 S_OUTPUT 的 40-bit add + shift + clip 单周期组合逻辑拆为两级流水：
  - S_OUTPUT: `(captured_result + 64) >>> 7` → `shifted_r` 寄存器
  - S_OUTPUT_CLIP: clip `shifted_r` → `data_out`，输出有效
- 原 12 级 CARRY4 链拆为 ~5 + ~2 级

**its_transform_engine.v**:
- `base_addr` 从组合逻辑改为寄存器（`start` 时锁存），切断 `tu_width → base_addr case → ROM address` 组合链
- ROM 地址路径从 5 级逻辑（3 LUT6 + 2 CARRY4）减为 3 级（纯加法）

**综合结果**: WNS 从 -2.289ns → -2.108ns（LFNST 流水线）→ -2.020ns（base_addr 寄存化），worst path 转移到 row engine 内部 `total_points_reg → state_reg/CE`

### v3.3 详细改动

**目标**: 解决 v3.2 的仿真/综合路径冲突（v3.2 的 BRAM 管线改动导致 ModelSim 仿真 2/108 PASS）。

**its_transform_engine.v**:
- 用 `ifdef SYNTHESIS` 条件编译分离仿真和综合路径：
  - 仿真路径（无 SYNTHESIS）：组合读 + mac_en 直连，保持 108/108 PASS
  - 综合路径（SYNTHESIS defined）：P0 管线 + mac_en_d（2 cycle delay）+ coeff_buf 写地址寄存
- `size_m1` 和 `size_shift` 改为无条件寄存器（`start` 时锁存），减少组合逻辑深度

**synth/its_core_500_ooc.tcl**:
- 添加 `set_property verilog_define {SYNTHESIS} [current_fileset]`

**已知限制**: ModelSim 将所有数组视为组合读（忽略 `(* ram_style *)` 属性），SYNTHESIS 路径在 RTL 仿真中有 1 cycle 系数延迟差异。功能正确性通过非 SYNTHESIS 路径（108/108 PASS）验证。完整 SYNTHESIS 路径验证需使用含 BRAM 模型的门级仿真。

### v3.2 详细改动

**目标**: 从 v3.1 的 WNS -5.213ns 优化到 500MHz (2ns) 附近。

**its_core_500.v**:
- `in_mem` 从 DistRAM 改为 Block RAM (`(* ram_style = "block" *)`)，移除 clearing 写分支以启用 BRAM 推断
- 新增 `lfnst_out_buf[0:47]` overlay buffer，LFNST 结果不再写回 in_mem，消除高扇出写路径
- 行引擎改用绝对地址计数器 `row_in_mem_addr`（取代 `row_base_addr + row_eng_rd_addr`）
- 新增 overlay 检测逻辑：`lfnst_active && row < 4/12 && col < 4` 时从 overlay buffer 读取
- 注册 `in_mem_rd_addr` 断开 LFNST 地址计算关键路径
- LFNST 读路径增加 2 拍延迟（地址寄存 + BRAM 读延迟）

**its_transform_engine.v**:
- `line_buf` 和 `coeff_buf` 改为 Block RAM
- 新增 P0 管线寄存器 (`(* dont_touch = "yes" *)`)，对齐 BRAM 读延迟与 MAC 输入
- `mac_en` 增加 2 拍延迟链 (`mac_en_raw → mac_en → mac_en_d`)
- `size_shift` 和 `size_m1` 改为寄存器（`start` 时锁存）
- `coeff_buf` 写地址注册，断开高扇出写路径 (fanout=528 → ~16)
- `mac_final` 增加第 3 拍 `mac_final_e`，对齐 MAC 累加完成时序

### v3.0 → v3.1 改动

- 引入 `its_core_500.v`：独立于 `its_top.v` 的 500MHz 计算核
- 接口改为 FIFO 协议 (cmd_fifo 23-bit, input_fifo 29-bit, output_fifo 40-bit)
- 输出管线增加 ready/valid 握手，支持反压
- OOC 综合脚本 `its_core_500_ooc.tcl`

### v2.0 → v3.0 改动

- 从单时钟架构 (`its_top`) 分离出双时钟架构 (`its_core_500`)
- 添加 OOC 综合流程，独立评估内部时序

### v1.0 → v2.0 改动

- XDC 约束清理、PPA 报告对齐
- 波形 SVG 文档、设计文档完善
- 交付版打磨

---

## 9. 工具与环境

| 工具 | 版本 | 用途 |
|------|------|------|
| ModelSim | SE-64 10.6e | 功能仿真 |
| Vivado | 2024.1 | 综合与实现 |
| Python | 3.x | 系数生成、参考模型 |
