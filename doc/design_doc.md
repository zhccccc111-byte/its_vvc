# ITS VVC 反变换模块 — 设计文档

## 1. 概述

### 1.1 设计目标

实现 VVC (H.266) 视频编码标准的反变换模块 (Inverse Transform Subsystem, ITS)，支持：
- 三种变换核：DCT2、DCT8、DST7
- 块大小：4x4 ~ 64x64 (DCT2)，4x4 ~ 32x32 (DCT8/DST7)
- LFNST (Low-Frequency Non-Separable Transform)
- 500MHz 目标时钟频率
- 每周期 4 点并行计算

### 1.2 标准参考

- VVC 标准：ITU-T H.266 / ISO/IEC 23090-3 (JVET-S2001)
- LFNST 矩阵：赛题附件 "Low frequency non.docx"

---

## 2. 架构设计

### 2.1 顶层架构

```
                    ┌─────────────────────────────────────────────────┐
                    │                   its_top                       │
                    │                                                 │
  it_info ─────────→│  ┌─────────┐                                    │
  it_data_in ──────→│  │ in_mem  │──→ ┌──────────────┐               │
  it_data_addr ────→│  │ (4096)  │    │ Row Engine   │──→ tp_buf     │
                    │  └─────────┘    │ (4 MAC)      │    (4096)     │
                    │                 └──────────────┘       │        │
                    │  ┌─────────┐                    ┌──────┘        │
                    │  │ LFNST   │                    ▼               │
                    │  │ Module  │           ┌──────────────┐         │
                    │  └─────────┘           │ Col Engine   │──→ out_mem
                    │                        │ (4 MAC)      │    (4096) │
                    │                        └──────────────┘    │     │
                    │                                            ▼     │
                    │                                     ┌──────────┐ │
                    │                                     │ Output   │ │
                    │                                     │ Control  │─→ it_data_out
                    │                                     └──────────┘ │
                    └─────────────────────────────────────────────────┘
```

### 2.2 状态机

```
S_IDLE ──→ S_LOAD ──→ [S_LFNST] ──→ S_ROW_START ──→ S_ROW_RUN ──┐
                        (可选)         (行变换启动)               │
                                                ┌────────────────┘
                                                ▼ (循环 height 次)
                                          S_COL_START ──→ S_COL_RUN ──┐
                                               (列变换启动)           │
                                                ┌─────────────────────┘
                                                ▼ (循环 width 次)
                                          S_OUT ──→ S_DONE ──→ S_IDLE
                                        (光栅输出)
```

**状态转移条件：**

| 当前状态 | 下一状态 | 条件 |
|---------|---------|------|
| S_IDLE | S_LOAD | it_info_vld 脉冲 |
| S_LOAD | S_LFNST | 输入超时(16周期) && lfnst_idx != 0 |
| S_LOAD | S_ROW_START | 输入超时 && lfnst_idx == 0 |
| S_LFNST | S_ROW_START | lfnst_done 脉冲 |
| S_ROW_START | S_ROW_RUN | 无条件（1周期） |
| S_ROW_RUN | S_COL_START | row_done && row_idx+1 >= height |
| S_ROW_RUN | S_ROW_START | row_done && row_idx+1 < height |
| S_COL_START | S_COL_RUN | 无条件（1周期） |
| S_COL_RUN | S_OUT | col_done && col_idx+1 >= width |
| S_COL_RUN | S_COL_START | col_done && col_idx+1 < width |
| S_OUT | S_DONE | out_cnt >= total_points |
| S_DONE | S_IDLE | 无条件（1周期） |

**输入结束检测：** 使用 16 周期超时机制。当 in_wr_cnt > 0 且连续 16 周期无 it_data_in_vld 脉冲时，判定输入结束。

### 2.3 数据流

1. **输入阶段 (S_LOAD)**：外部按地址写入 in_mem[0..4095]，只传非零系数
2. **LFNST 阶段 (S_LFNST)**：读取 in_mem 左上 4x4，经 LFNST 变换后写回
3. **行变换阶段 (S_ROW_RUN)**：逐行读取 in_mem，1D 变换后写入 tp_buf（行主序）
4. **列变换阶段 (S_COL_RUN)**：按步长 width 读取 tp_buf（列数据），1D 变换后写入 out_mem
5. **输出阶段 (S_OUT)**：按光栅扫描顺序每周期输出 4 个 10-bit 结果

---

## 3. 模块详细设计

### 3.1 变换引擎 (`its_transform_engine.v`)

执行一维反变换 `y = T^T * x`。

**端口列表：**

| 信号 | 位宽 | 方向 | 说明 |
|------|------|------|------|
| clk | 1 | I | 时钟 |
| rst_n | 1 | I | 异步复位 |
| start | 1 | I | 启动脉冲 |
| tr_type | 2 | I | 变换类型 (0=DCT2, 1=DCT8, 2=DST7) |
| size | 7 | I | 变换大小 (4/8/16/32/64) |
| data_in | 16 | I | 输入数据 |
| data_in_vld | 1 | I | 输入有效 |
| data_in_req | 1 | O | 输入请求 |
| rom_addr | 14 | O | ROM 地址 |
| rom_coeff | 16 | I | ROM 系数 |
| data_out | 16 | O | 输出数据 |
| data_out_vld | 1 | O | 输出有效 |
| data_out_req | 1 | I | 输出反压 |
| done | 1 | O | 完成脉冲 |

**内部架构：**

```
                ┌─────────────────────────────────────────┐
                │          its_transform_engine            │
                │                                         │
  data_in ─────→│  line_buf[0..63]                        │
                │       │                                 │
                │       ▼                                 │
                │  ┌─────────┐  ┌─────────┐              │
                │  │ MAC 0   │  │ MAC 1   │  ... (x4)    │
                │  │ a*b→acc │  │ a*b→acc │              │
                │  └─────────┘  └─────────┘              │
                │       │           │                     │
                │       ▼           ▼                     │
                │  result_buf[0..63]                      │
                │       │                                 │
                │       ▼                                 │
  data_out ←────│  (sum + 32) >>> 6                       │
                └─────────────────────────────────────────┘
```

**计算流程（N 点变换）：**

1. S_LOAD (N 周期)：加载 N 个输入到 line_buf
2. S_PREFETCH (4N 周期)：从 ROM 预取 4 行系数到 coeff_buf
3. S_COMPUTE (N 周期)：4 MAC 并行计算 4 个输出点
4. 若 N > 4，需 N/4 组，重复步骤 2-3
5. S_OUTPUT (N 周期)：输出结果

**行分组处理：** 对于 N > 4 的变换，将 N 行分成 N/4 组，每组 4 行共享同一次 ROM 预取。row_group 计数器跟踪当前组。

### 3.2 MAC 单元 (`its_mac.v`)

2 级流水线乘累加器。

**流水线时序：**

```
周期 0: en=1 → product = a * b (Stage 1)
周期 1: valid_s1=1 → result += sign_ext(product) (Stage 2)
周期 2: valid=1 (结果可用)
```

**清零机制：** `clr` 信号优先级高于累加，用于每组计算开始前复位累加器。

**位宽：**
- 输入 a, b: 16-bit signed
- 乘积 product: 32-bit signed
- 累加器 result: 40-bit signed

### 3.3 LFNST 模块 (`its_lfnst.v`)

执行 LFNST 反变换。

**公式：** `y[i] = clip3(-32768, 32767, (Σ_j T[i][j]·x[j] + 64) >> 7)`

**nTrs 定义：**
- `nTrs = (tu_width >= 8 && tu_height >= 8) ? 48 : 16`
- nTrs=16: 16x16 矩阵，16 输入 → 16 输出
- nTrs=48: 48x16 矩阵，16 输入 → 48 输出

**状态机：**

```
S_IDLE → S_LOAD → S_PREFETCH → S_COMPUTE → S_DRAIN → S_OUTPUT → S_DONE
```

**计算流程：**

1. S_LOAD：加载 16 个输入到 in_buf（超时检测：16 周期无数据则结束）
2. S_PREFETCH：从 LFNST ROM 预取 nTrs*16 个系数到 coeff_buf
3. S_COMPUTE：16 周期内积计算（MAC 串行）
4. S_DRAIN：等待 MAC 流水线排空（2 周期）
5. S_OUTPUT：裁剪并输出结果（nTrs 个点）
6. S_DONE：完成

**ROM 地址布局（8192 条目）：**

```
nTrs=16 [0..2047]:
  base = lfnstTrSetIdx * 512 + (lfnst_idx-1) * 256
  每场景: 16x16 = 256 条

nTrs=48 [2048..8191]:
  base = 2048 + (lfnstTrSetIdx * 2 + (lfnst_idx-1)) * 768
  每场景: 48x16 = 768 条
```

### 3.4 顶层 LFNST 集成

**读地址映射（nTrs=48）：**

LFNST 读取 in_mem 左上 4x4 子块（16 个元素），地址计算：
```
row = rd_addr[3:2]
col = rd_addr[1:0]
addr = row * tu_width + col
```

**写回地址映射：**

nTrs=16：顺序写回 in_mem[0..15]

nTrs=48：3 个 4x4 子块布局：
```
blk 0: rows 0-3, cols 0-3  → addr = row * width + col
blk 1: rows 0-3, cols 4-7  → addr = row * width + (col+4)
blk 2: rows 4-7, cols 0-3  → addr = (row+4) * width + col
```

---

## 4. ROM 结构

### 4.1 变换核 ROM (`its_rom.v`)

8176 条目，16-bit 系数，同步读（1 周期延迟）。

| 变换类型 | 块大小 | 起始地址 | 系数数量 |
|---------|--------|---------|---------|
| DCT2 | 4 | 0 | 16 |
| DCT2 | 8 | 16 | 64 |
| DCT2 | 16 | 80 | 256 |
| DCT2 | 32 | 336 | 1024 |
| DCT2 | 64 | 1360 | 4096 |
| DCT8 | 4 | 5456 | 16 |
| DCT8 | 8 | 5472 | 64 |
| DCT8 | 16 | 5536 | 256 |
| DCT8 | 32 | 5792 | 1024 |
| DST7 | 4 | 6816 | 16 |
| DST7 | 8 | 6832 | 64 |
| DST7 | 16 | 6896 | 256 |
| DST7 | 32 | 7152 | 1024 |

**地址公式：** `addr = base_addr + row * size + col`

**系数生成公式：**
- DCT2: T(0,j) = 64, T(i,j) = round(89 * cos(π·i·(2j+1)/(2N))) for i>0
- DCT8: T(i,j) = round(64 * cos(π·(2i+1)·(2j+1)/(4N)))
- DST7: T(i,j) = round(64 * sin(π·(i+1)·(j+1)/(N+1)))

### 4.2 LFNST ROM (`its_lfnst_rom.v`)

8192 条目，16-bit 系数，同步读（1 周期延迟）。

ROM 地址布局：
- [0..2047]：nTrs=16 (8 场景 × 256 条)
- [2048..8191]：nTrs=48 (8 场景 × 768 条)

---

## 5. 定点量化方案

| 模块 | 运算 | 量化方式 |
|------|------|---------|
| 变换引擎 | y = T^T * x | (sum + 32) >>> 6 |
| LFNST | y = T * x | (sum + 64) >>> 7，clip3(-32768, 32767) |
| 输出 | 40-bit → 10-bit | 截取低 10 位 |

**位宽分析：**
- 输入系数: 16-bit signed [-32768, 32767]
- 变换核系数: 16-bit signed
- MAC 累加器: 40-bit signed（避免 16×16×N 溢出）
- 输出结果: 10-bit signed [-512, 511]

---

## 6. 接口时序

### 6.1 输入时序

```
         ___     ___     ___     ___     ___
clk   __|   |___|   |___|   |___|   |___|   |___
      
           ┌───────────────────────────
it_info_vld|  ┐
           └──┘
           ┌───────────────────────────
it_data_in_|  ┐     ┐     ┐
vld        └──┘     └──┘   └──┘
           ┌───────────────────────────
it_data_in_| D0    | D1    | D2
req        └───────────────────────────
```

### 6.2 输出时序

```
         ___     ___     ___     ___     ___
clk   __|   |___|   |___|   |___|   |___|   |___
      
           ┌───────────────────────────
it_data_out| V0    | V1    | V2
_vld       └───────────────────────────
           ┌───────────────────────────
it_data_out| D0    | D1    | D2
_req       └───────────────────────────
```

---

## 7. 存储资源

| 存储 | 深度 | 位宽 | 用途 |
|------|------|------|------|
| in_mem | 4096 | 16-bit | 输入系数缓冲 |
| tp_buf | 4096 | 16-bit | 转置缓冲（行变换输出） |
| out_mem | 4096 | 10-bit | 输出结果缓冲 |
| line_buf (引擎) | 64 | 16-bit | 行输入缓冲 |
| coeff_buf (引擎) | 256 | 16-bit | 系数缓冲 |
| result_buf (引擎) | 64 | 40-bit | 结果缓冲 |
| in_buf (LFNST) | 16 | 16-bit | LFNST 输入缓冲 |
| coeff_buf (LFNST) | 768 | 16-bit | LFNST 系数缓冲 |
