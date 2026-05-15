# 录制模块调试记录 (2026-04-29)

## 背景

将录制方案从 `ebml-go/webm` 实时 mux 改为 **IVF + Ogg Opus 临时文件 + ffmpeg remux** 方案。新方案先写临时文件（IVF 视频 + 原始 Opus 音频），录制结束时用 ffmpeg 将其混合成最终 WebM。

## 遇到的问题及解决

### 1. Ogg CRC 算法错误

**错误信息**: `[in#1] CRC mismatch!`

**原因**: Ogg 规范要求 **non-reflected** CRC-32（多项式 0x04C11DB7，MSB 优先），但实现时用了常见的 reflected CRC-32（多项式 0xEDB88320，LSB 优先）。

**解决**: 重写 `oggCRCTab` 和 `oggCRC` 函数，使用 MSB-first 算法。

### 2. VP8 分辨率解析返回垃圾值

**错误信息**: `Picture size 65520x65520 is invalid`

**原因**: VP8 关键帧头部在起始码（0x9D, 0x01, 0x2A）之后还有大量可变长 bool 编码字段（segmentation、loop filter 等），帧尺寸字段并不在固定偏移位置。简单 bool 解码器读到了错误位置的数据，返回 65520x65520（4095×16）。

**解决**: 在写入 IVF 头部时增加合理性检查（16~7680 × 16~4320），超出范围则使用 1280x720 默认值。

### 3. Ogg Opus granule position 计算错误

**错误信息**: `Header processing failed: Invalid data found when processing input`

**原因**: Granule position 计算公式为 `tsUs * 48 / 1_000_000`，除以了 100 万而不是 1000。Opus 采样率 48kHz 的转换公式应为 `tsUs * 48 / 1000`，结果少了 1000 倍（例如 4 秒音频 ~194 而不是 ~194880），ffmpeg 发现 granule 与实际音频数据量严重不符而拒绝文件。

**解决**: `p.tsUs * 48 / 1_000_000` → `p.tsUs * 48 / 1000`。

### 4. OpusHead 和 OpusTags 未分页

**错误信息**: `Header processing failed: Invalid data found when processing input`

**原因**: RFC 7845 §3 规定 **OpusHead 必须独占 Ogg 第一页**，OpusTags 必须在第二页。实现时将两者放在同一页，ffmpeg 的 Ogg Opus demuxer 严格遵循此规范。

**解决**: 将 `writeOggPage` 调用拆分为两次：
- 第 0 页: BOS + OpusHead（单独）
- 第 1 页: OpusTags（无特殊标志）
- 第 2 页+: 音频数据

### 5. Ogg segment 数量溢出

**错误信息**: `CRC mismatch!`，且 Ogg 文件末尾有多余数据

**原因**: Ogg 规范限制每页最多 **255 个 segment**。9 秒录音有 ~479 个 Opus 包，`byte(len(segTable))` 截断成了 223。未包含在 segment table 中的 256 个包变为孤儿数据，CRC 也因数据不完整而错误。

**解决**: 在页面累积循环中增加 `maxSegmentsPerPage = 255` 限制，达到上限时自动分页。

### 6. 关键帧等待导致画面卡死

**错误信息**: 录制视频在 ~19s 到 ~37s 之间完全没有帧（18 秒空白）

**原因**: 在 RTP 序列号乱序时重置了 `firstKeyFrameSeen = false`，等待下一个关键帧。但 WebRTC 发送端不会自动发送关键帧（需要 PLI 请求），导致录制暂停 18 秒直到下一个周期关键帧到来。

**解决**: 去除序列号乱序时对 `firstKeyFrameSeen` 的重置，仅重置帧缓冲区，继续写入后续帧。

### 7. 丢包后画面花屏

**现象**: 修复卡死后，丢包导致 P 帧引用丢失数据，画面出现花屏

**原因**: RTP 丢包后写入的 P 帧引用已丢失的参考帧数据，解码器无法正确解码。

**解决**: 增加 **PLI（Picture Loss Indication）** 机制。在 `IVFRecorderWriter` 中增加 `pliFn` 回调，检测到丢包时自动向发送端发送 RTCP PLI 请求，让对方立即产生一个新的关键帧。PLI 回调在录制启动和新增轨道（如屏幕共享）时自动配置。

## 最终架构

```
录制开始
  │
  ├─ 视频：从 RTP 接收 VP8 → 解包 → 重组帧 → 写入 IVF 临时文件
  ├─ 音频：从 RTP 接收 Opus → 写入原始 Opus 临时文件（带时间戳）
  │
录制结束
  │
  ├─ 读取原始 Opus → 生成 Ogg Opus 文件
  ├─ ffmpeg -i temp.ivf -i temp.opus -c copy -f webm output.webm
  └─ 清理临时文件
```
