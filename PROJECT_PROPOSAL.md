# Moon Audio 项目申报书

## 基本信息

- 项目名称：Moon Audio：MoonBit 原生 WAV / OGG 音频解码库
- 参赛者：待填写
- 联系方式：待填写
- GitHub 仓库链接：待填写
- 项目方向：MoonBit 音频基础库 / 多媒体基础设施
- 是否为移植项目：否，采用 clean-room 方式实现，并参考公开的音频格式资料和 public domain 项目
- 项目许可证：MIT License

## 项目简介

Moon Audio 计划为 MoonBit 生态提供一个以 MoonBit 为主要实现语言的原生音频
解码库，核心覆盖 RIFF/WAVE PCM 解析、OGG 容器解析、Vorbis 音频包解码、
PCM 重采样、声道转换以及 WAV 输出。

项目采用清晰的“输入字节流 -> PCM 数据 -> 输出字节流”模型，不绑定音频设备、
线程、操作系统播放器或特定图形界面。应用开发者可以通过统一 API 将 WAV 或
OGG 音频解码为交错的 16-bit PCM，再交给音频播放、波形分析、机器学习预处理、
资源打包、媒体转换或其他上层工具使用。

Moon Audio 面向以下用户和场景：

- 需要在 MoonBit 中读取 WAV/OGG 资源的应用开发者；
- 需要构建音频分析、波形显示和媒体处理工具的开发者；
- 需要在 WASM、Native 等目标中处理音频数据的 MoonBit 项目；
- 希望在 MoonBit 生态中使用纯 MoonBit 音频基础能力的库作者。

## 核心功能范围

- 提供统一的 `decode(bytes)` 入口，根据文件头识别 WAV 或 OGG 音频；
- 支持 RIFF/WAVE PCM 文件解析，覆盖 8/16/24/32-bit 整数采样；
- 支持 32-bit IEEE 浮点 WAV 的转换；
- 支持 `fmt `、`data` 以及其他附加 chunk 的解析，并处理 chunk 顺序变化；
- 对 WAV 输入执行长度、块大小、采样率、声道数和截断输入检查；
- 提供 `Pcm` 数据结构，保存采样率、声道数和交错的 `Array[Int16]` 样本；
- 提供 `Pcm::frames()` 和 `Pcm::info()` 等音频数据查询接口；
- 提供线性重采样，支持采样率转换；
- 提供 mono 与多声道之间的基础声道转换；
- 提供 `Pcm::to_wav()`，将 PCM 数据输出为标准 16-bit WAV；
- 提供 OGG 页头解析、页序号检查、逻辑流检查和 OGG CRC 校验；
- 支持 OGG packet 的 lacing 重组和跨页 packet 处理；
- 提供 Vorbis identification/comment/setup header 解析；
- 提供 Vorbis codebook、Huffman、floor、residue、mapping、逆耦合、IMDCT
  和窗函数等基础解码模块；
- 提供命令行文件转换示例：

  ```sh
  moon run cmd/main -- input.ogg output.wav
  moon run cmd/main -- --self-test output.wav
  ```

- 提供可重复执行的 self-test，生成固定采样率和频率的 WAV 音频；
- 提供 README、项目申报书、许可证说明、NOTICE 和 GitHub Actions CI；
- 提供 WAV 多位深、chunk 顺序、WAV round-trip、重采样和异常输入测试。

## 项目现有基础

当前项目已经完成以下工程基础：

- 已建立 `zjhdev/moon_audio` MoonBit 模块；
- 已按照 MoonBit 包结构拆分 WAV、OGG、位读取、Vorbis 配置解析和解码模块；
- 已建立公共 API：`Pcm`、`AudioInfo`、`AudioError` 和 `decode`；
- 已加入 MIT License 和第三方参考项目说明；
- 已加入 `.github/workflows/ci.yml`，执行 `moon check` 和 `moon test`；
- 已提供 `cmd/main` 命令行 demo；
- 已生成 `examples/demo_self_test.wav` 示例输出；
- 本地 `moon check` 已通过；
- 本地 native 测试共 5 项，全部通过。

## 技术路线

项目采用 MoonBit 原生实现，整体分为以下层次：

1. **PCM 数据层**

   使用 `Pcm` 表示采样率、声道数和交错的 16-bit PCM 样本，作为所有解码和
   转换操作的统一输出类型。

2. **WAV 解析层**

   解析 RIFF/WAVE 文件头和 chunk，校验格式参数，根据采样位深将整数或 IEEE
   浮点采样转换为 `Int16`。

3. **OGG 容器层**

   解析 OGG page，执行 CRC 校验、页序号校验、逻辑流校验和 packet 重组，
   将 OGG 页面转换为 Vorbis packet 序列。

4. **Vorbis 配置解析层**

   使用 MoonBit 位读取器解析 identification、comment 和 setup header，
   构建 codebook、floor、residue、mapping、mode 等内部结构。

5. **Vorbis 音频解码层**

   使用 Huffman 解码、频谱恢复、floor/residue 处理、channel coupling、
   IMDCT 和窗口函数将 Vorbis 音频 packet 转换为 PCM 音频块。

6. **转换与输出层**

   对 PCM 执行重采样和声道转换，并通过 WAV writer 输出标准 16-bit WAV。

项目参考 `stb_vorbis` 和 `dr_wav` 的公开算法思想、文件格式定义和测试思路，
但不直接复制上游源文件。核心音频处理代码由 MoonBit 独立实现。

## 预期目标

本次项目的目标是形成一个具备实际复用价值的 MoonBit 音频基础库：

- 建立 MoonBit 生态中清晰、可复用的 WAV/OGG 音频输入接口；
- 让 MoonBit 应用可以在不依赖系统播放器的情况下读取 PCM 音频；
- 为后续音频播放、波形分析、音频特征提取和媒体工具提供基础数据层；
- 验证 MoonBit 在位级解析、Huffman 解码、信号变换和数值处理方面的工程能力；
- 提供清晰的错误边界、可测试的输入输出接口和便于维护的模块结构；
- 为后续发布到 `mooncakes.io` 和接入更多 MoonBit 项目打下基础。

## 当前版本功能边界

当前版本优先保证工程结构清晰和 WAV/PCM 路径可测试。OGG Vorbis 已实现基础
解码路径，但仍属于持续完善中的实验性功能。

当前明确的限制包括：

- 尚未完成完整的 Vorbis overlap-add；
- 尚未完成基于 end granule 的精确尾部裁剪；
- 尚未完成全部 Vorbis 兼容性和参考解码器对拍；
- 暂不支持 chained OGG logical streams；
- 暂不支持除 mapping 0 以外的完整多声道 mapping 组合；
- 暂不支持非 PCM WAV 压缩格式；
- 暂不承诺已经达到完整 `stb_vorbis` 的生产级兼容范围。

这些限制已经在 README 和项目文档中公开说明，后续将通过真实 OGG corpus、
参考解码器对比和更多回归测试逐步收敛。

## 测试、示例与文档计划

项目提供以下验收材料：

- `README.mbt.md`：项目用途、API、构建、测试和命令行示例；
- `PROJECT_PROPOSAL.md`：项目申报材料；
- `NOTICE`：参考项目、来源和许可证说明；
- `LICENSE`：MIT 许可证全文；
- `.github/workflows/ci.yml`：持续集成配置；
- `cmd/main`：命令行 demo；
- `examples/demo_self_test.wav`：可直接检查的 WAV 示例；
- `moon_audio_test.mbt`：公共 API 测试；
- `moon_audio_wbtest.mbt`：内部实现测试入口。

当前测试覆盖：

- 16-bit WAV 解码和 WAV round-trip；
- 8/24/32-bit 整数 WAV 解码；
- IEEE float WAV 解码；
- WAV chunk 重排；
- 重采样和 downmix；
- 截断输入、未知格式和非法参数；
- native 目标 `moon check` 和 `moon test`。

后续测试计划：

- 增加真实 OGG/Vorbis 样例文件；
- 与系统参考解码器进行 PCM 输出对拍；
- 增加 floor、residue、coupling 和 block 边界专项测试；
- 增加 OGG CRC、跨页 packet 和多逻辑流边界测试；
- 增加性能基准和内存使用记录；
- 发布第一个稳定版本并准备 `mooncakes.io` 包发布材料。

## 移植或参考说明

本项目不是将某个 C/C++ 项目直接复制到 MoonBit，而是采用 clean-room 的
独立实现方式。

参考项目如下：

- 原项目名称：`stb_vorbis`
- 原项目链接：[https://github.com/nothings/stb](https://github.com/nothings/stb)
- 原项目许可证：Public Domain / dual-licensed MIT

- 原项目名称：`dr_wav`
- 原项目链接：[https://github.com/mackron/dr_libs](https://github.com/mackron/dr_libs)
- 原项目许可证：Public Domain / MIT-0

本项目对参考项目的处理方式：

- 仅参考公开的文件格式、算法说明和 API 设计思路；
- 不复制上游源文件；
- 不保留上游项目的 C 语言实现结构；
- 使用 MoonBit 类型、包结构、错误模型和测试机制重新组织；
- WAV 解析、OGG page 解析、位读取、Huffman 和 Vorbis 结构均以 MoonBit
  代码独立实现；
- 参考项目中与系统文件、线程、设备播放和平台绑定相关的内容不纳入核心库。

## 开源与合规说明

- 本项目采用 OSI 认可的 MIT License；
- 核心代码为本项目的 MoonBit 实现；
- 参考项目均为 public domain 或允许 MIT/MIT-0 使用的项目；
- 项目在 `NOTICE` 中保留参考项目名称、链接和许可证说明；
- 项目不包含私有代码、商业闭源代码或来源不明的素材；
- `moonbitlang/x/fs` 仅用于命令行 demo 的文件读写，核心解码器仍保持
  内存输入输出边界。

## 后续维护价值

Moon Audio 的长期维护方向包括：

- 完善 Vorbis block overlap-add 和 granule 裁剪；
- 增加更多 Vorbis floor、residue、mapping 兼容性；
- 增加流式 packet 解码接口；
- 增加 WAV 流式读取和增量输出；
- 提供音频格式探测、时长估算和波形摘要接口；
- 增加更多平台目标和 WASM 使用示例；
- 发布到 `mooncakes.io`，持续维护版本、变更日志和回归测试。
