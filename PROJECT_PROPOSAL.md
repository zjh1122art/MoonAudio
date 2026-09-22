# MoonBit 原生 WAV / OGG 音频解码库

## 项目用途

本项目是 MoonBit 原生实现的 WAV PCM / OGG Vorbis 音频解码库，提供清晰的
“输入字节流 -> PCM 数据 -> WAV 字节流”边界。它适合音频分析、资源预处理、
媒体工具和需要跨运行时使用音频数据的 MoonBit 应用。

## 现有基础

- 已创建 `zjhdev/moon_audio` MoonBit 模块。
- 已实现 RIFF/WAVE PCM 解析、16-bit PCM WAV 输出、线性重采样和声道转换。
- 已实现 OGG 页解析、CRC 校验、packet 重组及 Vorbis setup/audio packet 的
  基础解码路径。
- 已加入 MIT 许可证、第三方来源说明、README、CI、命令行 demo 和测试。

## 本次开发内容

1. 完善 WAV 解析，覆盖 8/16/24/32-bit 整数和 32-bit IEEE float。
2. 实现 OGG Vorbis 的位读取、Huffman codebook、floor、residue、mapping、
   逆耦合、IMDCT 和窗函数。
3. 提供 `Pcm::resample`，支持采样率转换和 mono / multichannel 转换。
4. 提供命令行 demo：

   ```sh
   moon run cmd/main -- input.ogg output.wav
   moon run cmd/main -- --self-test output.wav
   ```

5. 提供 WAV、多位深、chunk 顺序、异常输入、重采样和 WAV round-trip 测试。

## 技术路线

项目采用 clean-room MoonBit 实现，参考 public domain 的 `stb_vorbis` 和
`dr_wav` 的公开算法与文件格式知识，不复制其源代码。核心实现只依赖
MoonBit；命令行文件读写使用 `moonbitlang/x/fs`。

## 功能边界

当前版本以可维护的基础实现为目标。WAV 路径和 PCM 输出已通过本地测试；
OGG 容器和 Vorbis 基础解码路径已实现，但尚未完成完整的 overlap-add、
end-granule trimming 和全部 Vorbis 兼容性验证，因此暂不宣称已经达到
完整 `stb_vorbis` 的生产级兼容范围。

## 测试与文档计划

- `moon check --target native`
- `moon test --target native`
- 命令行 self-test 输出 WAV
- 持续补充真实 OGG corpus、参考解码器对拍和性能基准
- 后续发布到 `mooncakes.io`，并继续完善多逻辑流、精确边界裁剪和全部
  Vorbis mapping 支持

## 参考项目与许可证

- `stb_vorbis`: public domain / dual-licensed MIT
- `dr_wav`: public domain / MIT-0

本项目采用 MIT 许可证。第三方来源和移植范围见 `NOTICE`。
