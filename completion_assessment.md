# ITS 工程完成情况评估与后续建议

评估日期：2026-05-22

评估对象：

- 赛题文档：`第九届中国研究生创芯大赛-华为赛题1.docx`
- 工程目录：`D:/Workspace/its_vvc`

评估依据：

- 赛题文档中的功能、接口、性能、PPA、文档和验证交付要求
- 工程 README、RTL、testbench、脚本和已有 ModelSim transcript
- 当前机器尝试复跑 ModelSim 时，因 license 环境无效未能重新仿真

## 1. 总体结论

当前工程已经搭建了 VVC 反变换模块 ITS 的 RTL 原型，包含 DCT2、DCT8、DST7、LFNST、顶层控制、ROM 系数和 ModelSim 仿真脚本。

但是，工程目前不能认为已经和赛题要求一一对应。主要原因是：

- 顶层接口与赛题接口不一致。
- 稀疏输入场景下，未输入零点的清零依赖 testbench，不是 DUT 自身能力。
- 输出反压逻辑不完全满足赛题描述。
- 主 testbench 没有做黄金模型数值比对，只统计是否收到输出。
- LFNST 变换集和赛题表中的 nTrs/矩阵要求没有完整闭环。
- 没有综合、时序、资源、功耗、波形截图和正式设计/验证文档。

因此，该工程目前更接近“功能框架/原型”，还不是可直接提交的完整赛题作品。

## 2. 赛题要求对应情况

| 赛题要求 | 当前状态 | 评估 |
| --- | --- | --- |
| 支持 DCT2、DCT8、DST7 三种反变换 | 部分完成 | RTL 中有三类 transform type 和 ROM 地址映射，但矩阵来源与附件一致性未证明 |
| 支持 LFNST 反二次变换 | 部分完成 | 有 LFNST 模块，但 `lfnst_tr_set_idx` 未真正参与系数选择 |
| LFNST 后再做 DCT2 反变换 | 部分完成 | 当前顶层按 LFNST 后进入主变换流程，但没有完整数值验证 |
| 数据按 TU 光栅扫描输入，一拍一个点，只输入非零点 | 部分完成 | 支持地址写入非零点，但未输入零点清零依赖 testbench |
| 一拍计算四个点，支持流水 | 部分完成 | transform engine 有 4 个 MAC，但整体行列流程非连续流式吞吐，真实性能需量化 |
| 结果按 TU 光栅扫描输出，一拍 4 个点 | 部分完成 | 有 40-bit 打包输出，但未做完整数值比对 |
| Verilog 实现 | 基本完成 | 主要 RTL 使用 Verilog |
| 工作主频 500MHz | 未完成 | 无综合、约束、时序报告 |
| 追求面积和功耗最优 | 未完成 | 无资源/面积/功耗数据，也无优化对比 |
| 支持表格中所有块大小组合 | 部分完成 | 代码路径看似覆盖主要尺寸，但测试覆盖不足，特别是全组合未验证 |
| 赛题接口信号一致 | 不通过 | 顶层额外依赖 `it_data_in_last` |
| 完备验证方案、用例、数据和波形截图 | 未完成 | 现有验证弱，没有正式验证报告和波形截图 |
| 输出设计文档、RTL、验证环境、PPA 数据 | 未完成 | `doc/` 目录为空，缺少正式交付文档 |

## 3. 关键问题

### 3.1 顶层接口与赛题接口不一致

赛题接口表没有 `it_data_in_last`，但当前顶层 `its_top` 增加了该输入端口，并依赖它判断当前 TU 输入结束。

涉及位置：

- `rtl/its_top.v`：`it_data_in_last`
- `tb/its_tb.v`：`send_data(..., last)` 驱动该信号

影响：

- 无法直接按赛题接口交付。
- 如果外部系统只提供赛题规定信号，DUT 不知道何时开始计算。

建议：

- 删除顶层赛题外端口 `it_data_in_last`。
- 改为根据赛题可用信息设计输入结束机制，例如：
  - 由上游在 `it_info` 中补充非零点数量是不合规的，不建议。
  - 更合理的方式是确认赛题是否允许额外协议；若不允许，需要根据官方接口补充明确的输入结束判定方案。
  - 如无法从接口判断输入结束，应向赛题方确认接口表中是否遗漏 last/eob 类信号。

### 3.2 稀疏输入清零不属于 DUT 自身功能

赛题要求只输入非零点，零数据跳过。当前 DUT 的 `in_mem` 在仿真 initial 中清零，但每个新 TU 开始时没有主动清空所有未输入位置。

testbench 通过 `force/release` 调用 `clear_in_mem()` 强行清 DUT 内部存储，这不属于真实硬件行为。

影响：

- 连续处理多个 TU 时，上一帧/TU 的残留数据可能污染当前 TU。
- 当前仿真通过并不能证明“只输入非零点”场景真实可用。

建议：

- 在 `it_info_vld` 后增加内部清零流程，按 `total_points` 清空 `in_mem`。
- 或维护有效位 bitmap，读出未写入地址时返回 0。
- 验证中必须加入连续 TU 测试，第二个 TU 只输入少量非零点，检查未输入位置是否为 0。

### 3.3 输出反压不完全符合赛题

赛题要求 `it_data_out_req=1` 时才允许输出，否则 `it_data_out_vld` 不能拉高。

当前 `out_vld_r` 只根据 `state == S_OUT && out_cnt < total_points` 拉高，没有用 `it_data_out_req` 门控。

影响：

- 当下游反压 `it_data_out_req=0` 时，`it_data_out_vld` 仍可能为 1。
- 不满足接口时序描述。

建议：

- 将 `it_data_out_vld` 改为只在 `it_data_out_req=1` 且有可输出数据时拉高。
- 补充随机反压测试，要求 req 拉低期间 vld 必须为 0，且输出数据顺序不丢不重。

### 3.4 主 testbench 没有数值正确性检查

当前 `tb/its_tb.v` 的主测试流程主要等待输出有效，只要收到输出就增加 `test_pass`。它没有把 `it_data_out` 与黄金模型结果逐点比较。

已有 transcript 中的 `1921 passed, 0 failed` 更准确地说是“收到 1921 次期望数量的输出”，不是“1921 个结果数值正确”。

影响：

- 系数矩阵错误、缩放错误、符号错误、扫描顺序错误都可能无法被发现。

建议：

- 建立 Python/C 黄金模型，使用赛题附件中的 `transMatrix` 和 `lowFreqTransMatrix`。
- testbench 读取输入和期望输出向量，对每个输出 word 的 4 个 10-bit 点逐点比较。
- 错误时打印 TU 类型、地址、期望值、实际值。

### 3.5 LFNST 支持不完整

当前 LFNST ROM 只按 `nonZeroSize` 和 `lfnst_idx` 选择 4 组矩阵，`lfnst_tr_set_idx` 没有参与 ROM base 选择。

赛题接口提供 `lfnst_tr_set_idx`，说明不同 transform set index 应对应不同 LFNST 变换集。

影响：

- 即使 LFNST idx=1/2 可运行，也不能证明覆盖赛题所需全部 LFNST 变换类型集。

建议：

- 从赛题附件生成完整 LFNST ROM。
- ROM 地址应包含 `lfnst_tr_set_idx`、`lfnst_idx`、nTrs/nonZeroSize、row/col。
- 补齐 `lfnst_tr_set_idx=0/1/2/3` 的测试。

### 3.6 系数来源与赛题附件未闭环

当前 `scripts/gen_rom_coeffs.py` 使用公式生成 DCT/DST 系数，LFNST 矩阵在脚本中手写。参考模型里也标注过 LFNST 是 placeholder 风险。

赛题明确要求不同 transform type 的 `transMatrix` 和 `lowFreqTransMatrix` 详见附件。

影响：

- 无法证明 RTL 系数与官方附件 bit-exact 一致。
- 评审若使用官方向量，可能出现数值不匹配。

建议：

- 下载并解析赛题附件矩阵。
- 生成 ROM hex、RTL 仿真黄金数据和文档中的矩阵说明都必须来自同一个官方数据源。
- 对 ROM 文件增加 checksum 或生成日志，便于交付说明。

### 3.7 缺少 500MHz 和 PPA 证据

工程目录没有发现 Vivado/Pango 工程、约束文件、综合脚本、时序报告、资源报告或功耗报告。

影响：

- 无法证明 500MHz。
- 无法参与面积、功耗、性能归一化评分。

建议：

- 明确目标平台：FPGA 还是 ASIC。
- 若用 FPGA，至少提供：
  - 工具版本
  - device 型号
  - 时钟约束
  - resource utilization
  - timing summary
  - power report
- 若用 ASIC，需提供：
  - 工艺库名称
  - 约束
  - 综合面积
  - timing slack
  - power estimate

## 4. 当前已有成果

当前工程已有以下内容，可作为后续整改基础：

- `rtl/its_top.v`：ITS 顶层控制和行列 2D 反变换流程。
- `rtl/its_transform_engine.v`：1D transform engine，4 MAC 并行结构。
- `rtl/its_lfnst.v`：LFNST 原型模块。
- `rtl/its_rom.v`、`rtl/its_lfnst_rom.v`：系数 ROM。
- `scripts/gen_rom_coeffs.py`：ROM 系数生成脚本。
- `scripts/ref_model.py`：Python 参考模型雏形。
- `tb/its_tb.v`：基础 testbench。
- `sim/run_debug.do`：ModelSim 编译和运行脚本。
- `sim/transcript`：一次已有仿真记录，显示当前 23 个用例收到预期数量输出。

这些内容说明工程不是空壳，但离赛题交付还需要系统性补齐。

## 5. 后续整改优先级

### P0：接口和真实功能闭环

1. 处理 `it_data_in_last` 与赛题接口不一致问题。
2. 解决每个 TU 的输入缓存清零或有效位问题。
3. 修复输出反压：`it_data_out_req=0` 时 `it_data_out_vld` 不得拉高。
4. 删除 testbench 对 DUT 内部 `in_mem` 的 `force/release` 依赖。

### P1：数值验证闭环

1. 使用赛题附件生成官方矩阵 ROM。
2. 建立 bit-exact 黄金模型。
3. testbench 对所有输出逐点比较。
4. 覆盖所有 DCT2/DCT8/DST7 表格尺寸组合。
5. 覆盖 LFNST 的 nTrs、`lfnst_idx`、`lfnst_tr_set_idx` 组合。
6. 加入连续 TU、随机稀疏输入、边界值、全零、最大/最小值测试。
7. 加入随机输入/输出反压测试。

### P2：综合、时序和 PPA

1. 建立 Vivado/Pango/ASIC 综合工程。
2. 添加 500MHz 时钟约束。
3. 跑综合、实现或后端评估。
4. 输出资源、时序、功耗报告。
5. 根据报告优化关键路径、ROM/MAC 数量、存储结构和门控策略。

### P3：交付文档

1. 编写 ITS 详细设计文档。
2. 编写量化定标和误差分析说明。
3. 编写验证方案、用例覆盖表、仿真结果和波形截图。
4. 编写 PPA 报告，说明工具版本、device/工艺库、约束和结果。
5. README 与真实实现保持一致，不再声明尚未验证的能力为“已完成”。

## 6. 建议的最小可提交标准

在考虑提交前，至少应满足以下条件：

- 顶层端口严格匹配赛题接口，或有官方确认的接口补充说明。
- 所有官方要求尺寸组合都有自动化回归测试。
- 每个输出点与官方矩阵黄金模型 bit-exact 对比通过。
- 输入稀疏零点不依赖 testbench 内部 force。
- 输入/输出反压协议有断言或自检。
- 有 500MHz 时序报告。
- 有资源/面积和功耗报告。
- 有设计文档、验证报告、验证数据和波形截图。

## 7. 当前风险判断

如果以当前状态直接提交，主要风险如下：

- 接口不合规导致评审无法接入。
- 官方测试向量数值不匹配。
- 连续 TU 或稀疏输入场景出现残留数据错误。
- 随机反压测试失败。
- 500MHz/PPA 无数据，相关评分缺失。
- 文档和验证材料不足，影响评审完整性。

综合判断：当前完成度约为原型级，建议先按 P0 和 P1 修到功能和接口可信，再进入 P2/P3。
