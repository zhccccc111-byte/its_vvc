# its_core_500 vs its_top: LFNST/Row Engine 差异分析

## 差异 1: LFNST 输入路径

### its_top (组合读)
```
lfnst_rd_addr (reg) → lfnst_rd_mem_addr (comb) → in_mem[addr] (comb read)
data_in_vld = (state == S_LFNST && lfnst_data_in_req)  // 组合，同拍
```
- 地址 + 数据 + valid 三者同拍对齐
- in_mem 是分布式 RAM（LUTRAM），组合读

### its_core_500 (BRAM 流水)
```
lfnst_rd_addr (reg) → lfnst_rd_mem_addr (comb)
                     → in_mem_rd_addr_r (reg, +1 cycle)
                     → in_mem[addr] → in_mem_dout_r (reg, +1 cycle)
data_in_vld_d  = (state == S_LFNST && lfnst_data_in_req)  // +1 cycle
data_in_vld_dd = data_in_vld_d                              // +2 cycles
```
- 地址经 2 级寄存后到达 BRAM，数据经 BRAM 输出寄存共 2 cycle
- valid 延 2 拍对齐 BRAM 输出
- **时序上应该等价**，但多了 `in_mem_rd_addr_r` mux 阶段可能引入首周期偏差

## 差异 2: LFNST 结果存储

### its_top: 直接写回 in_mem
```
in_mem[lfnst_wr_mem_addr] <= lfnst_data_out  // S_LFNST 期间写回
行变换直接读 in_mem → 组合读，零额外延迟
```

### its_core_500: overlay buffer
```
lfnst_out_buf[lfnst_wr_addr] <= lfnst_data_out  // 写入小缓冲区(0:47)
行变换时：
  overlay_hit = lfnst_active && overlay_row_ok && overlay_col_ok
  row_in_mem_data = overlay_hit_r ? overlay_data : in_mem_dout_r
  row_in_mem_data_r <= row_in_mem_data  // 再加 1 级流水
```
- overlay 大小仅 48 个 entry
- `overlay_row_ok`: nTrs=48 时 row<12, nTrs=16 时 row<4
- `overlay_col_ok`: col_in_row < 4
- **风险点**：overlay 地址映射、nTrs=48 时 row/col 计算

## 差异 3: 行变换引擎数据路径

### its_top (0 级流水)
```
data_in = in_mem[row_base_addr + row_eng_rd_addr]  // 组合读
data_in_vld = (state == S_ROW_RUN)                  // 组合
```

### its_core_500 (2 级流水)
```
in_mem[addr] → in_mem_dout_r (BRAM, +1)
             → row_in_mem_data = overlay_hit_r ? overlay : in_mem_dout_r
             → row_in_mem_data_r (+1) → data_in
row_data_in_vld_r = (state == S_ROW_RUN) registered (+1)
```
- 总计 2 cycle 延迟，data 和 valid 同步

## 关键待验证问题

1. **LFNST 输入首周期**：in_mem_rd_addr_r 在进入 S_LFNST 时仍持有 S_LOAD 末尾的地址，
   第 1 拍 LFNST 请求时 BRAM 输出的是旧地址数据，而非 in_mem[0]。
   需要确认 lfnst_data_in_vld_dd 是否精确跳过了这 1 拍。

2. **overlay 地址映射**：overlay_idx = {row_idx[5:0], 2'b00} + col_in_row[1:0]
   即 row*4+col。当 nTrs=48 时，row<12, col<4 → 最大 idx=47+3=50? 不对，12*4=48
   但 lfnst_out_buf 只有 0:47。row=11,col=3 → idx=47 ✓
   但 row=11,col=3 是 12*4-1=47，刚好在范围内。

3. **LFNST 写入 overlay 的地址**：lfnst_wr_addr 从 0 递增，写入 lfnst_out_buf[lfnst_wr_addr]
   行变换读取时用 overlay_idx = row*4+col。
   需要确认 lfnst 输出顺序与 row-major 顺序一致。

4. **col_in_row 计算**：col_in_row = row_in_mem_addr - row_base_addr
   row_in_mem_addr 是当前行变换引擎的读地址（绝对地址）
   如果 row_in_mem_addr < row_base_addr（边界条件），col_in_row 会下溢
