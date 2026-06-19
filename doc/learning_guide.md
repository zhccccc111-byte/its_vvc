# ITS VVC 工程学习指南

> 从零开始，带你完整理解这个 VVC (H.266) 逆变换硬件加速器工程。
>
> 适合读者：有基础编程能力，但对 FPGA/数字电路/视频编码不熟悉的同学。

---

## 第一章：这个工程在做什么

### 1.1 视频编码中的"变换"

视频压缩的核心思路：把图像从"像素域"转换到"频率域"，这样大部分能量集中在少数低频系数上，高频系数接近零，可以大幅压缩。

```
原始像素块 (8x8)          变换后系数块 (8x8)
┌────────────────┐        ┌────────────────┐
│ 128 130 132 ... │  ──→  │ 2048  12  3  0 │  ← 左上角(低频)数值大
│ 129 131 133 ... │        │   8   2  0  0 │  ← 右下角(高频)数值小
│ ...              │        │   1   0  0  0 │
│ ...              │        │   0   0  0  0 │
└────────────────┘        └────────────────┘
```

- **正变换（编码端）**：像素 → 频率系数（DCT/DST）
- **逆变换（解码端）**：频率系数 → 像素（IDCT/IDST）← **本工程做的是这个**

### 1.2 VVC (H.266) 标准

VVC 是最新一代视频编码标准（2020 年发布），相比上一代 HEVC (H.265)：
- 支持更大的变换尺寸（最大 64x64，HEVC 最大 32x32）
- 支持更多变换类型（DCT2 + DCT8 + DST7，HEVC 只有 DCT2）
- 新增 LFNST（低频不可分变换）后处理步骤

### 1.3 本工程的输入输出

```
输入：变换系数（稀疏格式，只传非零值）+ TU 配置信息（尺寸、变换类型、LFNST 参数）
  │
  ▼
┌─────────────────────────────┐
│     ITS 逆变换子系统         │  ← 本工程实现的硬件
│  LFNST → 行变换 → 列变换    │
└─────────────────────────────┘
  │
  ▼
输出：重建像素残差（10-bit 有符号，光栅扫描顺序，每周期 4 个点）
```

### 1.4 赛题要求

第九届中国研究生创芯大赛·华为赛题1，要求实现一个 VVC 逆变换硬件加速器：
- 支持 DCT2 (4x4 ~ 64x64)、DCT8 (4x4 ~ 32x32)、DST7 (4x4 ~ 32x32)
- 支持 LFNST（低频不可分变换）
- 工作主频 500MHz
- 稀疏输入、40-bit 打包输出、反压支持

---

## 第二章：需要的前置知识

### 2.1 数字电路基础

**组合逻辑 vs 时序逻辑**

```
组合逻辑：输出 = f(输入)，无记忆
  例：y = a + b    （加法器）

时序逻辑：输出 = f(输入, 上一个状态)，有记忆
  例：always @(posedge clk)  q <= d;    （触发器/寄存器）
```

**寄存器（Register）**

数字电路的"记忆单元"，每个时钟上升沿采样一次输入：

```
        ┌───┐
  d ───►│ D ├─┬──► q
        │   │ │
  clk ─►│ > │ │
        └───┘ │
              │
  always @(posedge clk)  q <= d;
```

**时钟周期与频率**

```
500MHz → 周期 = 1/500M = 2ns（纳秒）
100MHz → 周期 = 1/100M = 10ns

关键约束：数据从一个寄存器出发，经过组合逻辑，必须在下一个时钟沿之前到达下一个寄存器。
如果路径太长（延迟 > 时钟周期），就是"时序违例"（timing violation）。
```

### 2.2 Verilog 基础

**模块（module）**

```verilog
module adder (
    input  wire [7:0] a,    // 8-bit 输入
    input  wire [7:0] b,
    output wire [7:0] sum   // 8-bit 输出
);
    assign sum = a + b;     // 组合逻辑
endmodule
```

**always 块（时序逻辑）**

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)         // 异步复位
        q <= 8'd0;
    else
        q <= d;         // 每个时钟沿采样
end
```

**有限状态机（FSM）**

```verilog
localparam S_IDLE = 3'd0;
localparam S_RUN  = 3'd1;
localparam S_DONE = 3'd2;

reg [2:0] state;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        state <= S_IDLE;
    else case (state)
        S_IDLE: if (start) state <= S_RUN;
        S_RUN:  if (done)  state <= S_DONE;
        S_DONE:            state <= S_IDLE;
    endcase
end
```

**实例化（调用子模块）**

```verilog
// 调用 4 个 MAC 单元
its_mac u_mac0 (.clk(clk), .rst_n(rst_n), .a(a0), .b(b0), .result(r0));
its_mac u_mac1 (.clk(clk), .rst_n(rst_n), .a(a1), .b(b1), .result(r1));
its_mac u_mac2 (.clk(clk), .rst_n(rst_n), .a(a2), .b(b2), .result(r2));
its_mac u_mac3 (.clk(clk), .rst_n(rst_n), .a(a3), .b(b3), .result(r3));
```

### 2.3 FPGA 基础

**FPGA 是什么**

FPGA（Field Programmable Gate Array）是一种可编程芯片，内部有大量可配置的逻辑单元：

```
FPGA 内部资源：
├── LUT（查找表）：实现任意组合逻辑（本工程用 6,556 个）
├── FF（触发器）：1-bit 寄存器（本工程用 2,329 个）
├── BRAM（块 RAM）：专用存储器，同步读写（本工程用 10.5 个）
├── DSP（数字信号处理单元）：硬件乘法器（本工程用 9 个）
└── IOB（I/O 缓冲器）：连接外部引脚
```

**BRAM vs 分布式 RAM**

```
BRAM：专用存储器块，同步读（1 周期延迟），容量大，时序好
  → 本工程的 in_mem、out_mem、ROM 都用 BRAM

分布式 RAM：用 LUT 实现的小容量存储器，组合读（0 周期延迟）
  → 本工程的 coeff_buf、line_buf 用分布式 RAM
```

**DSP48E1/E2**

FPGA 内置的硬件乘法器，可以做 16x16 或 25x18 的乘法：

```
DSP48E1 (Artix-7): 最高 ~447MHz
DSP48E2 (UltraScale+): 最高 ~625MHz

本工程用 9 个 DSP：4 个 MAC 单元 × 2（行引擎 + 列引擎）+ 1 个 LFNST MAC
```

### 2.4 定点数与量化

**为什么不用浮点数**

浮点运算（如 3.14159 × 2.71828）需要大量逻辑资源，硬件中通常用定点数：

```
16-bit 有符号定点数：范围 -32768 ~ +32767
  → 整数部分直接用二进制表示
  → 没有小数部分（本工程的变换系数都是整数）
```

**溢出与截断**

```
16-bit × 16-bit = 32-bit 乘积
  ↓ 累加 N 次（N 最大 64）
40-bit 累加器（足够容纳最大值）
  ↓ 右移 + 舍入
10-bit 输出（Clip 到 -512 ~ +511）
```

**舍入（Rounding）**

```verilog
// 右移 6 位 + 舍入
result_rounded = (sum + 32) >>> 6;
//                ^^^^   ^^
//                加偏移  算术右移
// 加 32 (= 2^5) 的目的是：如果被丢弃的低 6 位 >= 0.5，就进位
```

### 2.5 时序分析基础

**建立时间（Setup Time）约束**

```
数据路径延迟 < 时钟周期 - Tsetup

  寄存器A ──→ [组合逻辑] ──→ 寄存器B
              ^^^^^^^^^^
              这段延迟必须 < 2ns (500MHz)

WNS (Worst Negative Slack) = 时钟周期 - 路径延迟
  WNS > 0: 时序满足 ✓
  WNS < 0: 时序违例 ✗
```

**关键路径（Critical Path）**

延迟最长的那条数据路径，决定了最高工作频率。优化时序 = 缩短关键路径。

**打断关键路径的方法**

```
方法1：插入流水线寄存器
  [长组合逻辑]  →  [逻辑1] → reg → [逻辑2]
  延迟从 3ns 变为 1.5ns + 1.5ns，每个阶段都能在 2ns 内完成

方法2：寄存器前移（register retiming）
  把寄存器从输出端移到组合逻辑中间

方法3：复制寄存器（register replication）
  一个寄存器驱动太多负载 → 复制多个，每个驱动部分负载
  fanout 从 60 降到 15
```

---

## 第三章：VVC 逆变换数学原理

### 3.1 二维可分变换

VVC 的 2D 逆变换分解为两步 1D 变换：

```
2D 逆变换：Y = T_col^T × X × T_row

实现步骤：
  Step 1: 对 X 的每一行做 1D 行变换  →  中间结果 Z
  Step 2: 对 Z 的每一列做 1D 列变换  →  最终结果 Y

为什么可分？因为 2D 基函数可以写成两个 1D 基函数的乘积：
  cos(π·m·x/M) × cos(π·n·y/N) = f(x) × g(y)
```

### 3.2 三种变换类型

**DCT2（Type-II DCT）**—— 最常用的变换

```
公式：T[k][n] = round(64 × cos(π × k × (2n+1) / (2N)))
  N = 变换尺寸 (4/8/16/32/64)
  k = 行索引 (0 ~ N-1)
  n = 列索引 (0 ~ N-1)
  64 = 缩放因子（定点化）

4x4 DCT2 矩阵示例（每行乘以 64 后取整）：
  T = [ 64   64   64   64 ]
      [ 89   38  -38  -89 ]
      [ 64  -64  -64   64 ]
      [ 38  -89   89  -38 ]
```

**DCT8（Type-VIII DCT）**—— VVC 新增

```
公式：T[k][n] = round(64 × cos(π × (4k+1) × (4n+1) / (4N+2)))
```

**DST7（Type-VII DST）**—— VVC 新增

```
公式：T[k][n] = round(64 × sin(π × (4k+1) × (4n+1) / (4N+2)))
```

DCT8 和 DST7 经常混合使用（水平用一种，垂直用另一种），称为 MTS（Multiple Transform Selection）。

### 3.3 LFNST（低频不可分变换）

LFNST 是 VVC 的一个创新：在主变换之前，对左上角 4x4 区域的系数做一次额外的矩阵变换。

```
输入：TU 左上角 16 个系数（4x4，按对角扫描顺序取）
输出：16 或 48 个新系数（写回到 TU 的左上角区域）

公式：y[i] = clip3(-32768, 32767, (Σ_j T[i][j]×x[j] + 64) >> 7)

nTrs = 16（TU 尺寸 < 8x8 时，输出 16 个点）
nTrs = 48（TU 尺寸 >= 8x8 时，输出 48 个点，覆盖 3 个 4x4 子块）
```

### 3.4 MAC 运算

矩阵-向量乘法的核心操作：

```
y[i] = Σ_j T[i][j] × x[j]
     = T[i][0]×x[0] + T[i][1]×x[1] + ... + T[i][N-1]×x[N-1]

硬件实现：用 MAC（乘累加器）
  每个周期做一次乘法 + 累加
  N 个输入需要 N 个周期

本工程用 4 个并行 MAC，同时计算 4 个输出：
  y[0] = T[0][0]×x[0] + T[0][1]×x[1] + ...
  y[1] = T[1][0]×x[0] + T[1][1]×x[1] + ...
  y[2] = T[2][0]×x[0] + T[2][1]×x[1] + ...
  y[3] = T[3][0]×x[0] + T[3][1]×x[1] + ...
  ──── 4 个 MAC 并行，共享输入 x[j]，各自用不同的 T[i][j]
```

---

## 第四章：工程架构全景

### 4.1 文件结构

```
D:\Workspace\its_vvc\
├── rtl/                          ← RTL 源代码（硬件描述）
│   ├── its_top.v                 ← 仿真用顶层（直连端口）
│   ├── its_core_500.v            ← 500MHz 计算核心（FIFO 接口）
│   ├── its_top_500_wrapper.v     ← 500MHz 完整系统（CDC wrapper）
│   ├── async_fifo.v              ← Gray 码异步 FIFO
│   ├── rst_sync.v                ← 复位同步器
│   ├── its_transform_engine.v    ← 1D 变换引擎（4 并行 MAC）
│   ├── its_mac.v                 ← 2 级流水线乘累加器
│   ├── its_lfnst.v               ← LFNST 模块
│   ├── its_rom.v                 ← 变换核 ROM（8176 条）
│   ├── its_lfnst_rom.v           ← LFNST ROM（8192 条）
│   ├── rom_coeffs.hex            ← 变换核系数
│   └── lfnst_coeffs.hex          ← LFNST 系数
│
├── tb/                           ← 测试平台
│   ├── its_tb.v                  ← 主测试（1,444 case）
│   ├── its_tb_500.v              ← 500MHz wrapper 测试（双时钟 CDC）
│   ├── tb_core_500_direct.v      ← core 500 直连测试
│   ├── tb_async_fifo.v           ← 异步 FIFO 单元测试
│   ├── its_tb_simple.v           ← 简单测试（108 case，旧版）
│   └── test_vectors/             ← 测试向量（1,377 对 input/golden hex）
│
├── sim/                          ← ModelSim 仿真脚本
│   ├── run.do                    ← 主仿真脚本
│   ├── run_core_500.do           ← 500MHz 核心测试
│   └── *.log                     ← 仿真日志
│
├── synth/                        ← Vivado 综合脚本和报告
│   ├── its_synth.tcl             ← Artix-7 综合脚本
│   ├── its_core_500_ooc_usp.tcl  ← UltraScale+ OOC 综合脚本
│   ├── timing.xdc                ← 时序约束
│   └── *.rpt                     ← 综合报告
│
├── scripts/                      ← Python 工具脚本
│   ├── ref_model.py              ← 参考模型（golden）
│   ├── gen_rom_coeffs.py         ← 生成 ROM 系数 hex
│   └── gen_test_vectors.py       ← 生成测试向量
│
└── doc/                          ← 文档
    ├── design_doc.md             ← 设计文档
    ├── verification_report.md    ← 验证报告
    ├── ppa_report.md             ← PPA 报告
    └── ...                       ← 其他文档
```

### 4.2 数据流总览

```
                        ┌──────────────────────────────────────────┐
                        │            its_top.v / its_core_500.v     │
                        │                                          │
  it_info ─────────────►│  ┌──────────┐                            │
  it_data_in ──────────►│  │ in_mem   │  (4096×16-bit BRAM)        │
  it_data_addr ────────►│  │ (输入)   │                            │
  it_data_end ─────────►│  └────┬─────┘                            │
                        │       │                                   │
                        │       ▼                                   │
                        │  ┌──────────┐     ┌──────────┐           │
                        │  │ LFNST    │────►│ 行变换    │           │
                        │  │ (可选)   │     │ Engine   │           │
                        │  └──────────┘     └────┬─────┘           │
                        │                        │                  │
                        │                        ▼                  │
                        │                  ┌──────────┐            │
                        │                  │ tp_buf   │ (转置缓冲)  │
                        │                  └────┬─────┘            │
                        │                       │                   │
                        │                       ▼                   │
                        │                 ┌──────────┐             │
                        │                 │ 列变换    │             │
                        │                 │ Engine   │             │
                        │                 └────┬─────┘             │
                        │                      │                    │
                        │                      ▼                    │
                        │                ┌──────────┐              │
                        │                │ out_mem  │ (输出重排)    │
                        │                └────┬─────┘              │
                        │                     │                     │
  it_data_out ◄─────────│◄────────────────────┘                     │
  it_data_out_vld ◄─────│                                           │
  it_done ◄─────────────│                                           │
                        └──────────────────────────────────────────┘
```

### 4.3 处理流程（一个 TU 的完整生命周期）

```
S_IDLE      等待配置信息（it_info_vld 脉冲）
    │
S_CLEAR     清零 in_mem[0..total_points-1]（防止上一个 TU 的残留数据）
    │
S_LOAD      接收稀疏系数输入（只传非零值，每周期 1 个点）
    │        it_data_end 脉冲表示输入结束
    │
S_LFNST     (可选) 如果 lfnst_idx != 0，执行 LFNST 变换
    │        读取 in_mem 左上角 4x4 → LFNST 矩阵乘 → 写回 in_mem
    │        LFNST 激活时，强制主变换为 DCT2
    │
S_ROW_START 启动行变换引擎
S_ROW_RUN   逐行处理：读 in_mem → 1D 行变换 → 写 tp_buf
    │        每行完成后，如果还有下一行，回到 S_ROW_START
    │
S_COL_START 启动列变换引擎
S_COL_RUN   逐列处理：读 tp_buf → 1D 列变换 → 写 out_mem
    │        每列完成后，如果还有下一列，回到 S_COL_START
    │
S_OUT       从 out_mem 读出结果，打包成 40-bit（4×10-bit）输出
    │        支持反压（it_data_out_req 控制）
    │
S_DONE      发出 it_done 脉冲，回到 S_IDLE
```

---

## 第五章：逐模块详解

### 5.1 MAC 单元（its_mac.v，49 行）

这是最小的计算单元，做一次乘累加：

```
功能：result += a × b

2 级流水线：
  Stage 1: product = a × b（16-bit × 16-bit → 32-bit）
  Stage 2: result = result + sign_extend(product)（40-bit 累加器）

信号说明：
  clk, rst_n  — 时钟和复位
  en          — 使能（高电平时才做运算）
  clr         — 清零累加器（开始新的一行时用）
  a [15:0]    — 输入数据（系数值）
  b [15:0]    — 变换矩阵系数（从 ROM 来）
  result [39:0] — 累加结果
  valid       — 输出有效标志
```

### 5.2 变换引擎（its_transform_engine.v，628 行）

这是核心计算模块，做一维逆变换：`y = T^T × x`

```
内部结构：
┌─────────────────────────────────────────────┐
│                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │ MAC 0    │  │ MAC 1    │  │ MAC 2    │  │  ┌──────────┐
│  │          │  │          │  │          │  │  │ MAC 3    │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  │  └────┬─────┘
│       │             │             │         │       │
│  ┌────┴─────────────┴─────────────┴─────────┴───────┘
│  │
│  │  line_buf [0:63]    ← 存放输入数据
│  │  coeff_buf [0:255]  ← 存放变换矩阵系数（4 行 × N 列）
│  │  result_buf [0:63]  ← 存放 40-bit 累加结果
│  │
│  └──► ROM（共享）← 读取变换矩阵系数
│
└─────────────────────────────────────────────┘

FSM 状态：
  S_IDLE     → 等待 start
  S_LOAD     → 从外部读入 N 个系数到 line_buf
  S_PREFETCH → 从 ROM 预取 4 行系数到 coeff_buf
  S_COMPUTE  → 4 个 MAC 并行计算，每个周期处理 1 列
  S_OUTPUT   → 输出 4 个结果（截断为 16-bit）
  → 如果还有下一组 4 行，回到 S_PREFETCH
  → 全部完成，发出 done 信号
```

**关键设计点：4 并行 MAC**

```
对于 N=8 的变换，输出 8 个点：
  第 1 轮（4 MAC 并行）：计算 y[0], y[1], y[2], y[3]
  第 2 轮（4 MAC 并行）：计算 y[4], y[5], y[6], y[7]

每轮需要 N 个周期（8 个周期做 8 次乘累加）
总时间 = 2 轮 × 8 周期 = 16 周期
```

**ROM 地址计算**

```
ROM 存储了所有变换类型的矩阵系数，按以下布局：
  地址 = base_addr(tr_type, size) + row × size + col

base_addr 用 case 语句查表（组合逻辑）：
  DCT2-4:   base = 0
  DCT2-8:   base = 16
  DCT2-16:  base = 80
  DCT2-32:  base = 336
  DCT2-64:  base = 1360
  DST7-4:   base = 5456
  DST7-8:   base = 5472
  ...
  总共 8176 个系数
```

### 5.3 LFNST 模块（its_lfnst.v，373 行）

执行低频不可分变换：

```
功能：y[i] = clip3(-32768, 32767, (Σ_j T[i][j]×x[j] + 64) >> 7)

输入：TU 左上角 16 个系数（按对角扫描顺序）
输出：16 个（nTrs=16）或 48 个（nTrs=48）新系数

内部结构：
  in_buf [0:15]     ← 16 个输入系数
  coeff_buf [0:767] ← 变换矩阵（最多 48×16 = 768 个系数）
  1 个 MAC 单元     ← 串行计算（每次 1 个输出点）

FSM 状态：
  S_IDLE        → 等待 start
  S_LOAD        → 从 in_mem 读入 16 个系数
  S_PREFETCH    → 从 LFNST ROM 读取矩阵系数
  S_COMPUTE     → 逐行计算：y[i] = Σ_j coeff[i][j] × x[j]
  S_DRAIN       → 排空 MAC 流水线
  S_OUTPUT      → 输出结果（截断 + clip）
  S_DONE        → 完成

关键参数：
  nTrs = (tu_width >= 8 && tu_height >= 8) ? 48 : 16
  lfnst_tr_set_idx: 0~3（4 种变换集）
  lfnst_idx: 1 或 2（变换类型，0 表示不做 LFNST）
```

### 5.4 ROM（its_rom.v + its_lfnst_rom.v）

```
its_rom.v（变换核 ROM）：
  8176 个 16-bit 系数
  存储所有 DCT2/DCT8/DST7 矩阵
  同步读（1 周期延迟）
  由 gen_rom_coeffs.py 自动生成

its_lfnst_rom.v（LFNST ROM）：
  8192 个 16-bit 系数
  布局：
    [0..2047]   → nTrs=16：4 setIdx × 2 idx × 16×16 = 2048
    [2048..8191] → nTrs=48：4 setIdx × 2 idx × 48×16 = 6144
  同步读（1 周期延迟）
  由 gen_rom_coeffs.py 自动生成
```

### 5.5 顶层模块

**its_top.v（仿真用，607 行）**

```
用途：ModelSim 仿真 + 100MHz 全芯片综合
接口：直连端口（it_data_in, it_data_addr, it_data_end, ...）
存储：in_mem（寄存器数组，推断为分布式 RAM 或 BRAM）
特点：组合逻辑读取 in_mem（0 周期延迟），适合仿真
```

**its_core_500.v（500MHz 核心，789 行）**

```
用途：500MHz OOC 综合
接口：FIFO 接口（cmd_fifo, input_fifo, output_fifo）
存储：in_mem（显式 BRAM，1 周期同步读）
特点：
  - 12 处 ifdef SYNTHESIS 条件编译
  - LFNST overlay buffer（48-entry 小缓冲，避免写大 BRAM）
  - 3 级输出流水线（带 ready/valid hold 反压）
  - 所有关键路径都插入了寄存器
```

**its_top_500_wrapper.v（500MHz 完整系统，210 行）**

```
用途：500MHz 全芯片综合（含 CDC）
接口：赛题标准接口 + clk_core
内部：
  - 3 个 async_fifo（cmd/input/output，跨时钟域）
  - 2 个 rst_sync（IF 域 + 核心域复位同步）
  - 1 个 done_toggle CDC（toggle + 2-FF + 边沿检测）
  - 1 个 its_core_500 实例
```

**async_fifo.v（异步 FIFO，148 行）**

```
功能：跨时钟域数据传输
实现：Gray 码指针 + 2-FF 同步器
参数：DATA_WIDTH, ADDR_WIDTH（深度 = 2^ADDR_WIDTH）
```

**rst_sync.v（复位同步器，23 行）**

```
功能：异步置位，同步释放
实现：3 级触发器链
```

---

## 第六章：验证方法论

### 6.1 验证策略

```
           ┌──────────────────┐
           │  Python 参考模型  │  ← "黄金标准"
           │  (ref_model.py)  │
           └────────┬─────────┘
                    │ bit-exact 对比
                    ▼
┌─────────────────────────────────┐
│  Testbench (its_tb.v)           │
│  1. 发送 it_info 配置           │
│  2. 发送稀疏系数输入            │
│  3. 等待 it_done                │
│  4. 比较输出与 golden 数据      │
│  5. 检查协议合规（req=0→vld=0）│
└─────────────────────────────────┘
```

### 6.2 测试用例分类

| 类别 | 数量 | 说明 |
|------|------|------|
| DCT2 回归 | 225 | 25 种尺寸 × 9 种 LFNST 配置 |
| MTS 回归 | 1,152 | 16 种尺寸 × 8 种变换组合 × 9 种 LFNST 配置 |
| 连续 TU | 20 | 不复位，背靠背处理多个 TU |
| 反压 | 37 | 输出反压（3 拍高 / 2 拍低） |
| end 同周期 | 10 | it_data_end 与最后一个数据同周期 |
| **总计** | **1,444** | |

### 6.3 Python 参考模型

```python
# ref_model.py 核心流程
def its_inverse_transform(width, height, tr_hor, tr_ver, lfnst_set, lfnst_idx, coeffs):
    # 1. 解析稀疏输入，构建系数矩阵
    X = parse_sparse_input(width, height, coeffs)

    # 2. (可选) LFNST
    if lfnst_idx != 0:
        X = lfnst_inverse(X, lfnst_set, lfnst_idx, width, height)

    # 3. 行变换
    T_hor = get_transform_matrix(tr_hor, width)
    Z = matrix_multiply(T_hor.T, X)  # X 的每一行乘以 T_hor^T

    # 4. 列变换
    T_ver = get_transform_matrix(tr_ver, height)
    Y = matrix_multiply(T_ver.T, Z)  # Z 的每一列乘以 T_ver^T

    # 5. 截断到 10-bit
    return clip(Y, -512, 511)
```

### 6.4 仿真流程

```bash
# 在 ModelSim 中运行
cd D:/Workspace/its_vvc/sim
do run.do

# run.do 的核心内容：
# 1. 编译 RTL
vlog ../rtl/*.v
# 2. 编译 TB
vlog ../tb/its_tb.v
# 3. 仿真
vsim -t 1ps its_tb
# 4. 运行
run -all
```

---

## 第七章：综合与时序优化

### 7.1 综合流程

```
RTL 代码 (.v)
    │
    ▼
[Vivado 综合]  ← 把 Verilog 转换为门级网表
    │
    ▼
[布局布线]      ← 把逻辑门放到 FPGA 的具体位置，连接走线
    │
    ▼
[时序分析]      ← 检查每条路径的延迟是否满足时钟约束
    │
    ▼
报告：资源利用率、时序（WNS）、功耗
```

### 7.2 时序优化历程

本工程在 Artix-7 上做了 8 轮优化，累计改善 +0.556ns：

```
v3.2  -2.115ns  基线：BRAM in_mem + LFNST overlay + P0 流水
v3.3  -2.289ns  ifdef SYNTHESIS 分离（反而变差，因为增加了寄存器延迟）
v3.4  -2.020ns  LFNST 流水线拆分 + base_addr 寄存器 ← +0.269ns
v3.5  -2.081ns  输出控制链优化
v3.6  -1.859ns  列引擎 tp_buf 流水线 ← +0.222ns
v3.7  -1.881ns  ROM 地址累加器 + pf_ddly
v3.8  -1.736ns  mac_data_r 复制（fanout 60→15）← +0.145ns
v3.9  -1.733ns  mac_clr 寄存器（10 级链→4+6）← +0.003ns

结论：Artix-7 的物理极限是 -1.733ns（~362MHz），500MHz 需要 UltraScale+ 或 ASIC
```

### 7.3 500MHz 达标

```
v4.0  +0.030ns  零改动 RTL 移植 UltraScale+ xcku5p-2

关键发现：
  DSP48E2 (UltraScale+) 比 DSP48E1 (Artix-7) 快约 40%
  BRAM36E2 最低周期 1.8ns（556MHz）> 2ns（500MHz）✓
  最差路径：LFNST ROM (BRAM) → coeff_buf (DistRAM)，1.846ns
```

### 7.4 条件编译（ifdef SYNTHESIS）

```
仿真和综合的差异：
  ModelSim：数组读取是组合逻辑（0 周期延迟）
  Vivado：  BRAM 读取是同步逻辑（1 周期延迟）

解决方案：ifdef SYNTHESIS
  仿真路径：组合逻辑地址、直接使能
  综合路径：寄存器地址、延迟使能（补偿 BRAM 延迟）

its_transform_engine.v 中有 12 处条件编译，涉及：
  - ROM 地址累加器（组合 vs 寄存器）
  - MAC 使能延迟（直接 vs 2 周期延迟）
  - MAC 数据复制（共享 vs 每 MAC 独立副本）
  - 系数缓冲写地址（组合 vs 寄存器）
```

---

## 第八章：跨时钟域（CDC）

### 8.1 为什么需要 CDC

```
接口侧：100MHz（低速，与外部通信）
核心侧：500MHz（高速，做计算）

两个时钟域之间不能直接传信号，否则会产生亚稳态（metastability）。
解决方案：异步 FIFO + 复位同步器
```

### 8.2 异步 FIFO（async_fifo.v）

```
原理：
  写侧用 wr_clk，读侧用 rd_clk
  用 Gray 码编码指针（相邻值只有 1 bit 变化）
  用 2 级触发器同步指针到对面时钟域

Gray 码转换：
  000 → 000
  001 → 001
  010 → 011  ← 只有 1 bit 变化
  011 → 010
  100 → 110  ← 只有 1 bit 变化
  ...

本工程用了 3 个 async FIFO：
  cmd_fifo:   23-bit, depth 4   （命令：it_info）
  input_fifo: 29-bit, depth 16  （数据：last + addr + coeff）
  output_fifo: 40-bit, depth 16 （结果：4×10-bit）
```

### 8.3 复位同步器（rst_sync.v）

```
问题：异步复位信号在释放时可能违反建立时间
解决：异步置位（立即生效），同步释放（等时钟沿）

  async_rst_n ──→ [FF1] ──→ [FF2] ──→ [FF3] ──→ sync_rst_n
                        ↑        ↑        ↑
                       clk      clk      clk

复位释放时，sync_rst_n 延迟 3 个时钟周期才变高，
确保所有寄存器看到稳定的复位释放信号。
```

---

## 第九章：学习路线图

### 阶段 1：理解背景（1~2 天）

- [ ] 阅读本指南第一章（工程在做什么）
- [ ] 了解 VVC/H.266 视频编码的基本概念
- [ ] 理解 DCT/DST 变换的直觉（频率分析）
- [ ] 阅读赛题文档：`第九届中国研究生创芯大赛-华为赛题1.docx`

### 阶段 2：补数字电路基础（2~3 天）

- [ ] 学习 Verilog 基础语法（module, always, assign, wire, reg）
- [ ] 理解组合逻辑 vs 时序逻辑
- [ ] 学习 FSM 设计方法
- [ ] 了解 FPGA 内部结构（LUT, FF, BRAM, DSP）
- [ ] 推荐资源：《Verilog 数字系统设计教程》夏宇闻

### 阶段 3：理解变换数学（1~2 天）

- [ ] 理解 2D 可分变换 = 行变换 + 列变换
- [ ] 推导 DCT2 矩阵公式，手算 4x4 的例子
- [ ] 了解 DCT8/DST7 的公式和用途
- [ ] 理解 LFNST 的作用（低频系数额外变换）
- [ ] 阅读：`scripts/ref_model.py`（看 Python 实现）

### 阶段 4：逐模块读代码（3~5 天）

按以下顺序阅读，从底层到顶层：

```
Day 1: its_mac.v (49 行) ← 最简单，理解 MAC 流水线
       its_rom.v (26 行) ← 理解 ROM 结构
       its_lfnst_rom.v (26 行)

Day 2: its_transform_engine.v (628 行) ← 核心，重点理解 FSM + MAC 并行
       重点看：状态机、line_buf/coeff_buf/result_buf、ROM 地址计算

Day 3: its_lfnst.v (373 行) ← LFNST 模块
       重点看：nTrs 计算、ROM 地址布局、输出 clip

Day 4: its_top.v (607 行) ← 仿真顶层
       重点看：FSM 状态转换、行/列引擎调度、输出重排

Day 5: its_core_500.v (789 行) ← 500MHz 核心
       对比 its_top.v，理解每个时序优化点
       its_top_500_wrapper.v (210 行) ← CDC 系统
```

### 阶段 5：跑仿真（1~2 天）

- [ ] 安装 ModelSim SE-64 10.6e
- [ ] 在 `sim/` 目录下运行 `do run.do`
- [ ] 观察波形，理解信号时序关系
- [ ] 修改一个测试用例，重新生成 golden 数据，验证修改生效

### 阶段 6：理解综合与 PPA（1~2 天）

- [ ] 阅读 `doc/ppa_report.md`，理解资源利用率和时序
- [ ] 阅读 `doc/core_500mhz_timing_report.md`，理解优化历程
- [ ] 学习 Vivado 综合流程（`synth/` 目录下的 tcl 脚本）
- [ ] 理解 WNS、TNS、WHS 的含义

### 阶段 7：深入理解（持续）

- [ ] 阅读 `doc/design_doc.md`（完整设计文档）
- [ ] 阅读 `doc/fix_log.md`（理解踩过的坑）
- [ ] 阅读 `doc/verification_report.md`（验证方法论）
- [ ] 尝试自己写一个简单的变换模块（如 4x4 DCT2 only）

---

## 附录 A：关键术语表

| 术语 | 含义 |
|------|------|
| **TU** | Transform Unit，变换单元（一个 NxN 的系数块） |
| **DCT** | Discrete Cosine Transform，离散余弦变换 |
| **DST** | Discrete Sine Transform，离散正弦变换 |
| **LFNST** | Low-Frequency Non-Separable Transform，低频不可分变换 |
| **MTS** | Multiple Transform Selection，多变换选择 |
| **MAC** | Multiply-Accumulate，乘累加器 |
| **FSM** | Finite State Machine，有限状态机 |
| **BRAM** | Block RAM，块 RAM（FPGA 专用存储器） |
| **DSP** | Digital Signal Processing，数字信号处理单元 |
| **LUT** | Look-Up Table，查找表（FPGA 基本逻辑单元） |
| **FF** | Flip-Flop，触发器 |
| **CDC** | Clock Domain Crossing，跨时钟域 |
| **FWFT** | First Word Fall Through，首字直通（FIFO 模式） |
| **WNS** | Worst Negative Slack，最差负裕量（>0 表示时序满足） |
| **OOC** | Out-of-Context，离线综合（只综合核心，不含 I/O） |
| **PPA** | Power, Performance, Area，功耗/性能/面积 |
| **NBA** | Non-Blocking Assignment，非阻塞赋值（`<=`） |
| **Clip3** | 三参数截断：`Clip3(min, max, x) = max(min, min(max, x))` |

## 附录 B：推荐学习资源

| 主题 | 资源 |
|------|------|
| Verilog 入门 | 《Verilog 数字系统设计教程》夏宇闻 |
| FPGA 设计 | Xilinx UG901 (Vivado Synthesis Guide) |
| 时序分析 | Xilinx UG906 (Design Analysis) |
| VVC 标准 | ITU-T H.266 / ISO/IEC 23090-3 |
| DCT 变换 | 《数字图像处理》Gonzalez, Chapter 4 |
| CDC 设计 | Clifford Cummings, "Synthesis and Scripting Techniques" |
| 定点数 | Xilinx UG901, Chapter "Arithmetic" |
