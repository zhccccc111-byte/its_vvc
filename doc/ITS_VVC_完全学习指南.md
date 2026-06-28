# ITS-VVC 逆变换了系统 完全学习指南

> 本报告面向**零基础读者**，从数学原理到代码实现，逐步讲解整个工程的每一个知识点。
> 读完本报告，你应该能理解：VVC 逆变换是什么、每个模块做什么、数据怎么流动、500MHz 跨时钟域怎么设计、以及如何验证正确性。

---

## 目录

1. [项目背景：什么是变换编码](#1-项目背景什么是变换编码)
2. [数学基础：DCT2、DST7、DCT8 和 LFNST](#2-数学基础dct2dst7dct8-和-lfnst)
3. [整体架构总览](#3-整体架构总览)
4. [模块逐一讲解](#4-模块逐一讲解)
5. [数据流详解：一个 4x4 变换的完整旅程](#5-数据流详解一个-4x4-变换的完整旅程)
6. [500MHz 跨时钟域设计](#6-500mhz-跨时钟域设计)
7. [关键设计模式](#7-关键设计模式)
8. [验证方法：3075 个测试怎么跑的](#8-验证方法3075-个测试怎么跑的)
9. [FPGA 实现注意事项](#9-fpga-实现注意事项)

---

## 1. 项目背景：什么是变换编码

### 1.1 视频压缩中的变换

视频压缩（如 H.266/VVC）的核心思想：**原始像素块在频域表示时，大部分能量集中在低频区域**。通过变换，把像素值转换成频域系数，然后对高频系数进行量化（丢弃精度），实现压缩。

```
编码器：像素 → 正变换 → 量化 → 熵编码 → 比特流
解码器：比特流 → 熵解码 → 反量化 → 逆变换 → 像素
```

**本项目实现的是逆变换**（解码器端），即把频域系数还原为空域像素。

### 1.2 为什么需要硬件加速

VVC 支持的变换尺寸从 4x4 到 64x64，一帧 4K 视频有数百万个变换块。纯软件处理速度不够，需要 FPGA/ASIC 硬件加速器来实时解码。

### 1.3 VVC 支持的变换类型

| 变换类型 | 英文全称 | 尺寸 | 说明 |
|---------|---------|------|------|
| DCT2 | Discrete Cosine Transform Type II | 4/8/16/32/64 | 经典变换，VVC 默认 |
| DST7 | Discrete Sine Transform Type VII | 4/8/16/32 | VVC 新增，某些预测模式下更优 |
| DCT8 | Discrete Cosine Transform Type VIII | 4/8/16/32 | VVC 新增，某些预测模式下更优 |
| LFNST | Low-Frequency Non-Separable Transform | 16/48 点 | 预处理变换，放在主变换之前 |

---

## 2. 数学基础：DCT2、DST7、DCT8 和 LFNST

### 2.1 一维逆变换的数学表达

对于大小为 N 的一维逆变换，输入是 N 个频域系数 `x[0..N-1]`，输出是 N 个空域值 `y[0..N-1]`：

```
y[i] = sum_{j=0}^{N-1} T[i][j] * x[j]      (i = 0, 1, ..., N-1)
```

其中 `T[i][j]` 是变换矩阵的第 i 行第 j 列元素。

写成矩阵形式：

```
y = T^T * x       （T 是正变换矩阵，T^T 是其转置）
```

**关键点：** 这就是一个矩阵乘向量的运算。每个输出 `y[i]` 是输入向量 `x` 和变换矩阵第 `i` 行的内积。

### 2.2 二维逆变换的行列分解

2D 逆变换（对 M×N 的块）数学上是：

```
Y = T_M^T * X * T_N
```

其中 `X` 是 M×N 的频域系数矩阵，`Y` 是 M×N 的空域像素矩阵。

**行列分解（Row-Column Decomposition）** 把 2D 变换拆成两次 1D 变换：

```
步骤1（行变换）：对 X 的每一行做 1D 逆变换 → 中间结果 Z
步骤2（列变换）：对 Z 的每一列做 1D 逆变换 → 最终结果 Y
```

**为什么能这样拆？** 因为变换矩阵可以分离（separable）。这是 DCT2/DST7/DCT8 的共同性质。

**实际操作中需要转置：** 行变换的输出按行存储，但列变换需要按列读取。所以中间需要一个**转置缓冲区**（Transpose Buffer）把行列数据重新排列。

```
行变换输出：Z[0][0..W-1], Z[1][0..W-1], ...  (行优先存储)
转置后读取：Z[0..H-1][c], Z[0..H-1][c+1], ...  (按列读取，stride = W)
```

### 2.3 LFNST（低频非分离变换）

LFNST 是 VVC 新增的**预处理变换**，在主变换之前执行。

- 只作用于**左上角 4×4 区域**的 16 个（或 48 个）系数
- nTrs=16（小 TU）：16 个输入，16×16 矩阵，16 个输出
- nTrs=48（大 TU，宽≥8 且高≥8）：48 个输入，48×16 矩阵，48 个输出
- 有 4 组变换集（set_idx 0-3），2 个索引（idx 1-2），共 8 套矩阵

LFNST 的核心操作仍然是矩阵乘向量：

```
y[i] = clip3(-32768, 32767, (sum_j(T[i][j] * x[j]) + 64) >> 7)
```

注意：
- 输入只有 16 个系数（不是全部 TU 系数）
- 输出有 16 或 48 个系数（写回 TU 的左上角）
- 有额外的舍入常数 64 和移位 7（比主变换多 1 位精度）
- 需要 clip3 裁剪到 16 位有符号范围

### 2.4 舍入与裁剪

逆变换的中间计算用 40 位有符号数（防止溢出），最终输出需要：

```
result = (mac_sum + 32) >>> 6      // 主变换：加舍入常数，右移 6 位
result = (mac_sum + 64) >>> 7      // LFNST：加舍入常数，右移 7 位
result = clip(result, -32768, 32767)  // 裁剪到 16 位有符号范围
```

`>>>` 是算术右移（保持符号位），`>>` 是逻辑右移。这里用 `>>>` 因为结果可能是负数。

**v5.3 参数化命名常数：** 这些魔数在 v5.3 中被提取为命名常数，提高可读性：

```verilog
// its_transform_engine.v
localparam ROUND_SHIFT = 6;
localparam ROUND_CONST = 40'sd32;  // 2^(ROUND_SHIFT-1)

// its_lfnst.v
localparam LFNST_ROUND_SHIFT = 7;
localparam LFNST_ROUND_CONST = 40'sd64;
localparam LFNST_CLIP_HIGH   = 40'sd32767;
localparam LFNST_CLIP_LOW    = -40'sd32768;
```

---

## 3. 整体架构总览

### 3.1 两种顶层架构

本项目提供两个版本：

```
版本1：its_top.v（单时钟版本）
  外部接口 → its_top → 内部直接处理
  适用于：单时钟域系统，或作为参考设计

版本2：its_top_500_wrapper.v + its_core_500.v（双时钟版本）
  外部接口 → its_top_500_wrapper → [异步FIFO CDC] → its_core_500 → 内部处理
  适用于：500MHz 高性能 FPGA，外部接口跑低速时钟
```

### 3.2 模块层次结构

```
its_top_500_wrapper（顶层）
 ├── rst_sync × 2              // 复位同步器（if域 + core域）
 ├── async_fifo (cmd)          // 命令 FIFO：23-bit, depth 4
 ├── async_fifo (input)        // 输入 FIFO：29-bit, depth 16
 ├── fifo_fwft_reg_slice       // FWFT 寄存器切片（打断关键路径）
 ├── async_fifo (output)       // 输出 FIFO：40-bit, depth 16
 └── its_core_500（计算核心）
      ├── its_rom              // 变换系数 ROM（8176 条目）
      ├── its_lfnst_rom        // LFNST 系数 ROM（8192 条目）
      ├── its_lfnst            // LFNST 逆变换模块
      │    └── its_mac × 1     // LFNST 用 1 个 MAC 单元
      ├── its_transform_engine × 2  // 行引擎 + 列引擎
      │    └── its_mac × 4     // 每个引擎 4 个并行 MAC
      └── 内部存储：in_mem, tp_buf, out_mem, lfnst_out_buf
```

### 3.3 关键存储器

| 存储器 | 用途 | 大小 | 实现方式 |
|-------|------|------|---------|
| in_mem | 输入缓冲（频域系数） | 4096 × 16bit | XPM BRAM（综合）/ reg 数组（仿真） |
| tp_buf | 转置缓冲区 | 4096 × 16bit | reg 数组（DistRAM） |
| out_mem | 输出重排缓冲 | 4096 × 10bit | reg 数组（DistRAM） |
| lfnst_out_buf | LFNST 覆盖缓冲 | 48 × 16bit | reg 数组（DistRAM） |
| line_buf | 变换引擎行缓冲 | 64 × 16bit | reg 数组（DistRAM） |
| coeff_buf | 变换引擎系数缓冲 | 256 × 16bit | reg 数组（DistRAM） |
| in_buf | LFNST 输入缓冲 | 16 × 16bit | reg 数组 |
| coeff_buf (lfnst) | LFNST 系数缓冲 | 768 × 16bit | reg 数组 |

---

## 4. 模块逐一讲解

### 4.1 its_pkg.v — 共享定义包

**作用：** 把两个顶层模块（its_top.v 和 its_core_500.v）中完全相同的定义提取出来，避免代码重复。

```verilog
package its_pkg;
    // 状态编码（10 个状态）
    localparam S_IDLE      = 4'd0;   // 空闲，等待新 TU
    localparam S_LOAD      = 4'd1;   // 加载输入数据
    localparam S_ROW_START = 4'd2;   // 行变换启动
    localparam S_ROW_RUN   = 4'd3;   // 行变换执行中
    localparam S_COL_START = 4'd4;   // 列变换启动
    localparam S_COL_RUN   = 4'd5;   // 列变换执行中
    localparam S_OUT       = 4'd6;   // 输出结果
    localparam S_DONE      = 4'd7;   // 变换完成
    localparam S_LFNST     = 4'd8;   // LFNST 执行中
    localparam S_CLEAR     = 4'd9;   // 清零内存

    // 两个位移乘法函数（用 case 替代乘法器）
    function [11:0] row_times_width; ... endfunction
    function [11:0] row48_times_width; ... endfunction
endpackage
```

**知识点：**
- `import its_pkg::*;` 导入包中所有定义
- `case` 替代乘法器：`row * tw` 用移位实现（因为 tw 是 2 的幂），综合后是纯连线，无 DSP 消耗

### 4.2 its_mac.v — 乘累加单元

**作用：** 执行 `result += a * b`，是变换运算的核心计算单元。

**架构：2 级流水线**

```
时钟周期 N：   product = a × b          （乘法阶段，32 位结果）
时钟周期 N+1： result = result + product （累加阶段，40 位结果）
```

**为什么需要流水线？** 乘法器是组合逻辑延迟最大的部分。插入寄存器把关键路径切成两半，可以跑更高频率。

**端口说明：**
- `a` [15:0]：输入数据（有符号 16 位）
- `b` [15:0]：变换系数（有符号 16 位）
- `en`：使能信号，控制乘法阶段是否工作
- `clr`：清零累加器（每开始新的一行/列时需要清零）
- `result` [39:0]：累加结果（有符号 40 位，防止 16 次累加溢出）
- `valid`：结果有效标志

**为什么用 40 位？** 16 位 × 16 位 = 32 位，累加 16 次最多需要 32 + 4 = 36 位。40 位留有余量。

### 4.3 its_rom.v — 变换系数 ROM

**作用：** 存储所有变换矩阵的系数（DCT2/DST7/DCT8），共 8176 个 16 位条目。

```verilog
reg [15:0] rom [0:8175];
initial $readmemh("rom_coeffs.hex", rom);  // 从 hex 文件加载
always @(posedge clk) coeff <= rom[addr];  // 同步读，1 周期延迟
```

**知识点：**
- `$readmemh`：Verilog 系统任务，从文件加载内存初始值
- 同步读：地址在时钟上升沿送入，数据在下一个时钟上升沿输出（1 周期延迟）
- ROM 地址是扁平化的：不同变换类型、不同尺寸的系数按顺序排列在 ROM 中

**ROM 地址布局（its_transform_engine 中计算）：**

```
DCT2:   addr 0~5455      （5 种尺寸：4/8/16/32/64）
DST7:   addr 5456~6815   （4 种尺寸：4/8/16/32）
DCT8:   addr 6816~8175   （4 种尺寸：4/8/16/32）
```

### 4.4 its_lfnst_rom.v — LFNST 系数 ROM

**作用：** 存储 LFNST 变换矩阵系数，共 8192 个 16 位条目。

```
nTrs=16 区域 [0..2047]：  4 setIdx × 2 idx × 16×16 = 2048 条目
nTrs=48 区域 [2048..8191]：4 setIdx × 2 idx × 48×16 = 6144 条目
```

### 4.5 its_transform_engine.v — 变换引擎（最复杂的模块）

**作用：** 执行 1D 逆变换。这是整个工程最核心、最复杂的模块。

**核心思想：4 路并行 MAC**

对于大小为 N 的 1D 变换，每次计算 4 个输出（`y[0..3]`），每个输出需要 N 次乘累加。4 个 MAC 单元并行工作，同时计算 4 个输出。

```
MAC0: y[0] = T[0][0]*x[0] + T[0][1]*x[1] + ... + T[0][N-1]*x[N-1]
MAC1: y[1] = T[1][0]*x[0] + T[1][1]*x[1] + ... + T[1][N-1]*x[N-1]
MAC2: y[2] = T[2][0]*x[0] + T[2][1]*x[1] + ... + T[2][N-1]*x[N-1]
MAC3: y[3] = T[3][0]*x[0] + T[3][1]*x[1] + ... + T[3][N-1]*x[N-1]
```

**状态机：**

```
S_IDLE → S_LOAD → S_PREFETCH → S_COMPUTE → S_PREFETCH → ... → S_OUTPUT → S_IDLE
         ↑                              |
         └──────────────────────────────┘
                    （循环 ceil(N/4) 次）
```

- `S_LOAD`：从 in_mem 加载 N 个输入系数到 line_buf
- `S_PREFETCH`：从 ROM 预取 4 行系数到 coeff_buf（ROM 有 1 周期延迟）
- `S_COMPUTE`：4 个 MAC 并行计算 4 个输出
- 如果 N > 4，需要多轮 PREFETCH → COMPUTE 循环

**关键设计：条件编译 `ifdef SYNTHESIS`**

```verilog
`ifdef SYNTHESIS
    // 综合版：注册 ROM 地址（打断桶形移位器关键路径）
    reg [13:0] rom_addr_reg;
    // ... 复杂的增量更新逻辑
`else
    // 仿真版：组合逻辑 ROM 地址（简单直接）
    wire [13:0] rom_addr_r = base_addr + ...;
`endif
```

**为什么要分开？** 综合版为了跑 500MHz，需要额外的流水线寄存器来打断关键路径。仿真版不需要这么复杂，用简单的组合逻辑更易读。

### 4.6 its_lfnst.v — LFNST 逆变换模块

**作用：** 在主变换之前执行 LFNST 预处理。

**与 transform_engine 的区别：**

| 特性 | transform_engine | lfnst |
|------|-----------------|-------|
| MAC 单元数 | 4 个并行 | 1 个串行 |
| 系数来源 | 共享 ROM（its_rom） | 专用 ROM（its_lfnst_rom） |
| 输入来源 | 外部端口 | 从 in_mem 读取 |
| 输出去向 | 外部端口 | 写回 in_mem |
| 舍入 | +32 >>> 6 (ROUND_CONST) | +64 >>> 7 (LFNST_ROUND_CONST) |
| 裁剪 | 无（中间结果） | clip3(LFNST_CLIP_LOW, LFNST_CLIP_HIGH) |

**LFNST 的串行 MAC 设计：**

由于 LFNST 最多只有 48 个输入、16/48 个输出，计算量小，用 1 个 MAC 串行处理即可（16 或 48 个周期 × 16 次累加）。不需要 4 路并行。

**LFNST 状态机：**

```
S_IDLE → S_LOAD → S_PREFETCH → S_COMPUTE → S_DRAIN → S_OUTPUT → S_OUTPUT_CLIP → S_DONE
                         ↑                              |
                         └──────────────────────────────┘
                                    （循环 nTrs 次）
```

- `S_LOAD`：加载 16 个低频系数（15 周期空闲超时机制）
- `S_PREFETCH`：从 LFNST ROM 预取系数到 coeff_buf（nTrs×16+1 周期）
- `S_COMPUTE`：单 MAC 串行计算（每 16 周期一个输出点）
- `S_DRAIN`：等待 MAC 流水线排空（2 周期）
- `S_OUTPUT`：计算 (sum+64)>>>7
- `S_OUTPUT_CLIP`：执行 clip3 饱和并输出
- `S_DONE`：完成脉冲

### 4.7 its_top.v — 单时钟顶层

**作用：** 整合所有模块，提供竞赛标准的 22-bit it_info 接口。

**状态机流程：**

```
S_IDLE: 等待 it_info_vld
  ↓
S_CLEAR: 清零 in_mem（只清 total_points 个条目，不全清 4096）
  ↓
S_LOAD: 接收外部输入数据（稀疏：只接收非零系数）
  ↓
S_LFNST: 如果 lfnst_idx != 0，执行 LFNST 预处理
  ↓
S_ROW_START → S_ROW_RUN: 逐行做 1D 逆变换（共 tu_height 行）
  ↓
S_COL_START → S_COL_RUN: 逐列做 1D 逆变换（共 tu_width 列）
  ↓
S_OUT: 输出 4×10bit 打包结果
  ↓
S_DONE → S_IDLE
```

**22-bit it_info 接口：**

```
it_info[6:0]    = tu_width     （变换宽度，4~64）
it_info[13:7]   = tu_height    （变换高度，4~64）
it_info[15:14]  = tr_type_hor  （水平变换类型：0=DCT2, 1=DST7, 2=DCT8）
it_info[17:16]  = tr_type_ver  （垂直变换类型：同上）
it_info[19:18]  = lfnst_tr_set_idx （LFNST 变换集索引：0~3）
it_info[21:20]  = lfnst_idx    （LFNST 索引：0=不使用, 1或2=使用）
```

**关键设计：ROM 共享**

行引擎和列引擎**严格串行**（先做完所有行变换，再做所有列变换），所以可以共享一个 ROM。通过 `is_col_phase` 信号切换 ROM 地址来源。

**关键设计：转置缓冲区**

行变换输出按行写入 tp_buf（顺序写），列变换按列读取 tp_buf（stride = tu_width）。这就是行列分解中"转置"的实现。

### 4.8 its_core_500.v — 500MHz 计算核心

**作用：** 与 its_top.v 功能完全等价，但使用 FIFO 接口，运行在 500MHz 时钟域。

**与 its_top.v 的主要区别：**

| 特性 | its_top.v | its_core_500.v |
|------|-----------|----------------|
| I/O 接口 | 直接信号 | FIFO 接口（cmd/input/output） |
| 时钟 | 单时钟 | 单时钟（clk_core） |
| 输入内存 | reg 数组 | XPM BRAM（综合时） |
| LFNST 写回 | 直接写 in_mem | 写 lfnst_out_buf（覆盖缓冲） |
| 输出控制 | 简单计数 | 3 级流水线 + ready/valid |
| 复位 | 异步复位 | 同步复位（经过 rst_sync） |

**LFNST 覆盖缓冲（overlay buffer）：**

这是 its_core_500 的一个重要优化。LFNST 只修改左上角 16/48 个系数，如果直接写回 in_mem（BRAM），会造成：
1. 高扇出写路径（in_mem 写端口被 LFNST 和普通加载共用）
2. BRAM 写冲突风险

解决方案：用一个小的 DistRAM 缓冲（`lfnst_out_buf[0:47]`），LFNST 写入这个缓冲。读取时通过 mux 选择：如果地址命中 LFNST 区域，从 overlay 缓冲读；否则从 in_mem BRAM 读。

**输出 3 级流水线：**

```
Stage 0: out_mem 读取（地址送入）
Stage 1: data_out_r 寄存（捕获读结果）+ out_valid_pipe
Stage 2: FIFO 写入（write_fire = valid && !full）
```

`out_cnt` 只在 `write_fire` 时递增（不是在读取时），确保在反压（FIFO 满）时不丢失数据。

### 4.9 its_top_500_wrapper.v — 跨时钟域顶层

**作用：** 在外部接口时钟（clk_if，如 100MHz）和核心时钟（clk_core，500MHz）之间建立 CDC 桥梁。

**三个异步 FIFO：**

```
cmd_fifo:    23-bit, depth 4,   clk_if → clk_core  （传递 it_info）
input_fifo:  29-bit, depth 16,  clk_if → clk_core  （传递输入数据）
output_fifo: 40-bit, depth 16,  clk_core → clk_if  （传递输出数据）
```

**done 信号 CDC：**

`core_done` 是 clk_core 域的脉冲信号，需要传递到 clk_if 域。使用 **toggle-based CDC**：

```verilog
// clk_core 域：每次 core_done 翻转一次
always @(posedge clk_core)
    if (core_done) done_toggle <= ~done_toggle;

// clk_if 域：2-FF 同步 + 边沿检测
always @(posedge clk_if) begin
    done_sync1 <= done_toggle;
    done_sync2 <= done_sync1;
    done_sync3 <= done_sync2;
end
wire core_done_pulse = done_sync2 ^ done_sync3;  // 边沿检测
```

**为什么用 toggle 而不是直接同步脉冲？** 脉冲信号如果太窄，可能被目标时钟域漏采。toggle 信号是电平信号，一定能被同步到。

**it_done 生成：**

`it_done` 不是简单地同步 `core_done`，而是等到所有输出都被外部读完才置位：

```verilog
it_done = core_finished && output_fifo_empty && all_beats_read;
```

这确保外部看到 `it_done` 时，所有数据都已经被读走。

### 4.10 async_fifo.v — Gray 码异步 FIFO

**作用：** 在两个不同时钟域之间安全传递数据。

**核心原理：Gray 码指针同步**

二进制指针跨时钟域时，多位同时翻转（如 011→100 有 3 位变化）会导致亚稳态。Gray 码相邻值只有 1 位变化（010→110），2-FF 同步器可以安全同步。

```
二进制: 000 → 001 → 010 → 011 → 100 → 101 → 110 → 111
Gray码: 000 → 001 → 011 → 010 → 110 → 111 → 101 → 100
```

**满/空判断：**

```
满（写域判断）：下一个写指针的 Gray 码 == 读指针 Gray 码（高 2 位取反）
空（读域判断）：读指针 Gray 码 == 同步后的写指针 Gray 码
```

**FWFT（First Word Fall Through）：**

读出的数据在 FIFO 非空时立即可用（不需要先发 rd_en 再等一拍）。这减少了读延迟。

**端口说明：**
- `wr_count`：写域看到的 FIFO 占用量（有 2-3 周期延迟，用于反压）
- `almost_full`：只剩 2 个空位时置位（用于提前反压）

### 4.11 rst_sync.v — 复位同步器

**作用：** 把外部异步复位信号同步到目标时钟域。

```
异步复位 → [FF1] → [FF2] → [FF3] → 同步复位
             ↑        ↑        ↑
           clk       clk       clk
```

- **异步置位**（低电平立即生效）：`if (!async_rst_n) rst_pipe <= 0`
- **同步释放**（高电平需要 3 个时钟周期）：`rst_pipe <= {rst_pipe[2:0], 1'b1}`

**为什么要同步释放？** 异步释放可能导致恢复时间（recovery time）违例，产生亚稳态。同步释放确保复位撤除时刻与目标时钟沿对齐。

### 4.12 fifo_fwft_reg_slice.v — FWFT 寄存器切片

**作用：** 在 FWFT FIFO 和消费者之间插入一级寄存器，打断组合逻辑关键路径。

```
FIFO 读指针 → FIFO RAM → 组合读出 → [寄存器] → 消费者
```

没有这个切片，FIFO 的读指针变化会直接通过 RAM 读到消费者，形成长组合逻辑链。加一级寄存器后，关键路径被切断。

**核心逻辑：**

```verilog
wire slice_load = (core_rd_en | (core_empty & core_ready)) & ~fifo_empty;
```

- 消费者读数据时（`core_rd_en`），同时从 FIFO 预取下一个
- 切片为空且消费者准备好时，主动填充
- `core_ready` 信号可以暂停填充（当消费者忙碌时）

---

## 5. 数据流详解：一个 4x4 DCT2 变换的完整旅程

以 `tu_width=4, tu_height=4, tr_type_hor=0(DCT2), tr_type_ver=0(DCT2)` 为例。

### Step 1: 接收命令

```
外部发送 it_info = {0,0, 0,0, 4,4} → it_info_vld 脉冲
 ↓
its_top 解码：tu_width=4, tu_height=4, tr_type_hor=0, tr_type_ver=0
total_points = 4 × 4 = 16
```

### Step 2: 清零内存 (S_CLEAR)

```
in_mem[0..15] 全部写零（16 个周期）
```

### Step 3: 加载输入 (S_LOAD)

```
外部逐个发送非零系数：
  send_data(addr=5, data=123)   → in_mem[5] = 123
  send_data(addr=10, data=-45)  → in_mem[10] = -45
  it_data_end 脉冲 → 加载完成
```

### Step 4: 行变换 (S_ROW_START → S_ROW_RUN)

对每一行（共 4 行）做 1D 逆变换：

**第 0 行：**
1. 预取 4 个系数：T[0][0..3] → coeff_buf[0..3]
2. 计算：MAC0 累加 line_buf[0..3] × coeff_buf[0..3] → result_buf[0]
3. 舍入：result_buf[0] = (mac_result + 32) >>> 6

**第 1 行：**
1. 预取 4 个系数：T[1][0..3] → coeff_buf[4..7]
2. 计算：MAC0 累加 → result_buf[1]

... 直到第 3 行完成。

**行变换输出写入 tp_buf：** `tp_buf[0..3] = 行0结果, tp_buf[4..7] = 行1结果, ...`

### Step 5: 列变换 (S_COL_START → S_COL_RUN)

对每一列（共 4 列）做 1D 逆变换：

**第 0 列：** 从 tp_buf 读取 `tp_buf[0], tp_buf[4], tp_buf[8], tp_buf[12]`（stride=4）
1. 预取 4 个系数：T[0][0..3] → coeff_buf
2. 计算：MAC0 累加 → result_buf[0]
3. 写入 out_mem[0]（地址 = col_idx + row * tu_width = 0 + 0*4 = 0）

**第 1 列：** 从 tp_buf 读取 `tp_buf[1], tp_buf[5], tp_buf[9], tp_buf[13]`
...

### Step 6: 输出 (S_OUT)

```
out_mem[0..15] 打包为 4×10bit = 40bit 输出：
  第 1 拍：{out_mem[3], out_mem[2], out_mem[1], out_mem[0]}
  第 2 拍：{out_mem[7], out_mem[6], out_mem[5], out_mem[4]}
  ...
  共 4 拍输出 16 个值
```

### Step 7: 完成 (S_DONE → S_IDLE)

`it_done` 脉冲，等待下一个 TU。

---

## 6. 500MHz 跨时钟域设计

### 6.1 为什么需要 CDC

FPGA 上 500MHz 的时钟周期只有 2ns，外部接口（如 SoC 总线）通常跑 100~200MHz。两个不同时钟域直接连接会产生**亚稳态**（metastability）——信号在时钟沿附近变化时，触发器可能进入不确定状态。

### 6.2 CDC 方案

本项目使用**异步 FIFO** 作为 CDC 桥梁：

```
写域（clk_if, 100MHz）          读域（clk_core, 500MHz）
     ↓                                ↑
 async_fifo: Gray码指针 → 2-FF同步 → Gray码指针
     ↓                                ↑
 双口RAM（写端口）          双口RAM（读端口）
```

### 6.3 数据打包

为了减少 FIFO 深度和传输次数，数据被打包：

```
cmd_fifo (23-bit):   {reserved[22], it_info[21:0]}
input_fifo (29-bit): {last[28], addr[27:16], coeff[15:0]}
output_fifo (40-bit): {out3[39:30], out2[29:20], out1[19:10], out0[9:0]}
```

输出 FIFO 的 40-bit 打包特别重要：4 个 10-bit 结果打包成一个 40-bit 字，减少了 4 倍的 FIFO 传输次数。

### 6.4 反压（Backpressure）

当 FIFO 满时，上游必须暂停写入。本项目中的反压链：

```
output_fifo 满 → output_fifo_almost_full → core_500 暂停输出
input_fifo 满 → input_fifo_full → wrapper 暂停接收外部数据
```

### 6.5 FWFT vs 标准 FIFO

- **FWFT（First Word Fall Through）：** 数据在非空时立即出现在读端口，不需要先发 rd_en。用于 cmd_fifo 和 input_fifo（减少延迟）。
- **标准 FIFO：** 需要发 rd_en 后一拍才有数据。用于 output_fifo（需要寄存输出）。

---

## 7. 关键设计模式

### 7.1 Block RAM 推断规则

FPGA 的 Block RAM 有固定的行为模式。为了正确推断 BRAM，Verilog 代码必须遵循：

1. **写端口必须是同步的**（在 `always @(posedge clk)` 中）
2. **读端口可以是异步的**（组合逻辑读，推断为分布式 RAM）或**同步的**（时钟沿读，推断为 Block RAM）
3. **不能在同一个 always 块中对同一个地址既读又写**（否则推断为寄存器而不是 RAM）

本项目的 `in_mem` 在综合时使用 XPM BRAM 宏（`xpm_memory_sdpram`），确保正确推断为 Block RAM。

### 7.2 寄存器 vs 分布式 RAM 的选择

| 存储器 | 实现方式 | 原因 |
|-------|---------|------|
| in_mem (4096×16) | BRAM | 大容量，1 读端口 + 1 写端口 |
| tp_buf (4096×16) | DistRAM | 需要同时读写（写行结果，读列数据） |
| out_mem (4096×10) | DistRAM | 小位宽，读延迟敏感 |
| lfnst_out_buf (48×16) | DistRAM | 超小容量 |
| coeff_buf (256×16) | DistRAM | 小容量，需要组合读 |
| line_buf (64×16) | DistRAM | 小容量，需要组合读 |

### 7.3 条件编译 `ifdef SYNTHESIS`

```verilog
`ifdef SYNTHESIS
    // 综合时：额外的流水线寄存器、增量地址更新、XPM 宏
`else
    // 仿真时：简单的组合逻辑、reg 数组
`endif
```

**目的：** 仿真用简单代码（易于理解），综合用优化代码（跑高频）。两者**功能等价**，但综合版有额外的流水线延迟（需要对应的控制逻辑补偿）。

### 7.4 稀疏输入加载

变换块中很多系数是零（量化后）。外部只发送非零系数：

```
send_data(addr=5, data=123)   // 只发非零点
send_data(addr=10, data=-45)
it_data_end = 1               // 标记输入结束
```

`it_data_end` 可以与最后一个数据同周期发送（`run_test_end_same_cycle`），也可以单独发送。

### 7.5 位移替代乘法

```verilog
// row_times_width 函数：用移位替代乘法
case (tw)
    7'd4:    row_times_width = {8'd0, row, 2'd0};   // row × 4 = row << 2
    7'd8:    row_times_width = {7'd0, row, 3'd0};   // row × 8 = row << 3
    7'd16:   row_times_width = {6'd0, row, 4'd0};   // row × 16 = row << 4
    ...
endcase
```

因为 `tu_width` 总是 2 的幂（4/8/16/32/64），乘法可以用移位替代，综合后是纯连线。

---

## 8. 验证方法：3075 个测试怎么跑的

### 8.1 测试层次

```
Level 1: its_tb_simple.v    → 单元测试 transform_engine
Level 2: its_tb.v           → 集成测试 its_top（1444 个用例）
Level 3: its_core_500_tb.v  → 核心测试 its_core_500（94 个用例）
Level 4: its_tb_500.v       → 系统测试 wrapper（1537 个用例）
```

### 8.2 测试向量生成

测试向量由 Python 脚本生成，包括：
- **输入向量**：频域系数（hex 格式）
- **黄金输出**：参考软件计算的逆变换结果（hex 格式）

测试覆盖了：
- 所有变换类型组合：DCT2/DST7/DCT8 × DCT2/DST7/DCT8
- 所有尺寸：4×4, 4×8, 8×4, 8×8, ..., 32×32
- 所有 LFNST 配置：set_idx 0-3, idx 1-2, nTrs=16 和 nTrs=48
- 边界条件：数据同时结束（`it_data_end` 与最后一个数据同周期）
- 反压测试（500MHz 版本）

### 8.3 测试流程

```verilog
task run_test;
    // 1. 复位 DUT
    rst_n = 0; repeat(5) @(posedge clk); rst_n = 1;

    // 2. 加载测试向量
    $readmemh(input_hex, input_vec);
    $readmemh(golden_hex, golden_vec);

    // 3. 发送变换参数
    send_info(width, height, tr_hor, tr_ver, lfnst_tr_set_idx, lfnst_idx);

    // 4. 发送输入数据
    for (i = 0; i < input_count; i++)
        send_data(input_vec[i][27:16], input_vec[i][15:0]);

    // 5. 标记输入结束
    it_data_end = 1; @(posedge clk); it_data_end = 0;

    // 6. 收集输出并与黄金值比较
    while (out_idx < total_outputs) begin
        wait_output(out_data, out_valid, out_timeout);
        // 比较 4 个 10-bit 值
        for (j = 0; j < 4; j++)
            if (got_val !== exp_val) mismatches++;
    end

    // 7. 判断 PASS/FAIL
endtask
```

### 8.4 协议监控

```verilog
// 全局协议监控：req=0 时 vld 必须为 0
always @(posedge clk) begin
    if (rst_n && !it_data_out_req && it_data_out_vld !== 1'b0)
        $display("PROTOCOL VIOLATION: vld=%b when req=0", it_data_out_vld);
end
```

500MHz wrapper 还有额外的 FWFT 稳定性监控：vld=1 且 req=0 时，数据不能变化。

### 8.5 运行回归测试

```bash
# its_top 1444 测试
cd sim && vsim -c -do "source run.do; quit -f"

# wrapper 1537 测试
cd sim && vsim -c -do "source run_500.do; quit -f"

# core_500 94 测试
cd sim && vsim -c -do "source run_core_500.do; quit -f"
```

---

## 9. FPGA 实现注意事项

### 9.1 目标器件

- **FPGA：** Xilinx UltraScale+ xcku5p
- **目标频率：** 500MHz（时钟周期 2ns）
- **综合工具：** Vivado 2024.1

### 9.2 时序优化策略

| 策略 | 位置 | 效果 |
|------|------|------|
| MAC 流水线 | its_mac.v | 乘法和累加分两级 |
| 寄存器切片 | fifo_fwft_reg_slice.v | 打断 FIFO 读关键路径 |
| ROM 地址增量更新 | its_transform_engine.v | 消除桶形移位器 |
| P0 流水线 | its_transform_engine.v | 寄存 line_buf/coeff_buf 输出 |
| mac_data_r 复制 | its_transform_engine.v | 4 份数据副本就近放置 DSP |
| XPM BRAM | its_core_500.v | 确保 in_mem 用 Block RAM |
| LFNST overlay | its_core_500.v | 避免大 BRAM 高扇出写 |
| out_mem 同步读 | its_top.v | 打断 BRAM→OBUF 关键路径 |

### 9.3 资源估算

| 资源 | 用量 | 说明 |
|------|------|------|
| DSP48E1 | ~10 | 4×2 MAC + LFNST MAC + 杂项 |
| BRAM36 | ~8 | in_mem(2) + ROM(1) + LFNST ROM(1) + 其他 |
| LUT | ~2000-3000 | 控制逻辑 + 地址计算 |
| FF | ~1500-2000 | 流水线寄存器 + 控制寄存器 |

### 9.4 时序报告关注点

- **WNS（Worst Negative Slack）：** 必须 ≥ 0 才能保证时序收敛
- **关键路径：** 通常在 ROM 地址→MAC 乘法→累加 链路上
- **高扇出信号：** `mac_clr`、`row_in_mem_data` 等需要 `max_fanout` 约束

---

## 附录 A：文件清单

| 文件 | 行数 | 作用 |
|------|------|------|
| `rtl/its_pkg.v` | 52 | 共享状态编码和函数 |
| `rtl/its_mac.v` | 49 | 2 级流水线乘累加单元 |
| `rtl/its_rom.v` | 26 | 变换系数 ROM |
| `rtl/its_lfnst_rom.v` | 26 | LFNST 系数 ROM |
| `rtl/its_transform_engine.v` | 632 | 4 路并行 MAC 变换引擎 |
| `rtl/its_lfnst.v` | 405 | LFNST 逆变换模块 |
| `rtl/its_top.v` | 578 | 单时钟顶层 |
| `rtl/its_core_500.v` | 857 | 500MHz 计算核心 |
| `rtl/its_top_500_wrapper.v` | 298 | 跨时钟域顶层 |
| `rtl/async_fifo.v` | 173 | Gray 码异步 FIFO |
| `rtl/rst_sync.v` | 23 | 复位同步器 |
| `rtl/fifo_fwft_reg_slice.v` | 47 | FWFT 寄存器切片 |
| `tb/its_tb.v` | ~750 | its_top 集成测试（1444 用例） |
| `tb/its_tb_500.v` | ~1250 | wrapper 系统测试（1537 用例） |
| `tb/its_core_500_tb.v` | ~750 | core_500 核心测试（94 用例） |
| `tb/its_tb_simple.v` | ~150 | transform_engine 单元测试 |

## 附录 B：术语表

| 术语 | 全称 | 含义 |
|------|------|------|
| VVC | Versatile Video Coding | H.266，最新视频编码标准 |
| ITS | Inverse Transform Subsystem | 逆变换了系统 |
| TU | Transform Unit | 变换单元，视频编码中的基本处理块 |
| DCT | Discrete Cosine Transform | 离散余弦变换 |
| DST | Discrete Sine Transform | 离散正弦变换 |
| LFNST | Low-Frequency Non-Separable Transform | 低频非分离变换 |
| MTS | Multiple Transform Selection | 多变换选择 |
| MAC | Multiply-Accumulate | 乘累加 |
| CDC | Clock Domain Crossing | 时钟域交叉 |
| FWFT | First Word Fall Through | 首字直通 |
| BRAM | Block RAM | FPGA 内嵌块 RAM |
| DistRAM | Distributed RAM | FPGA 分布式 RAM |
| DSP | Digital Signal Processor | FPGA 内嵌 DSP 单元 |
| XPM | Xilinx Parameterized Macros | Xilinx 参数化宏 |
| WNS | Worst Negative Slack | 最差负时序余量 |

---

*本报告由 Claude Code 根据 RTL 源码自动生成，适用于 ITS-VVC v5.3 版本。*
