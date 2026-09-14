# AudioFormatBar

macOS 26 菜单栏音频输出格式监视器 Demo。本demo完全由DeepSeek V4.1F制作并发布，感谢鲸鱼小姐。

## 当前功能

- 枚举全部 CoreAudio 输出设备。
- 显示当前设备的采样率、物理位深、声道、传输类型。
- 识别 `kAudioDevicePropertyHogMode`，显示正在独占设备的 App。
- 使用 CoreAudio Process Object API 识别正在输出音频的 App。
- 自动跟随优先级：独占设备 → 活跃输出设备 → 系统默认设备。
- 支持手动固定某个设备，设置按设备 UID 持久化。
- 菜单栏实时显示紧凑格式，例如 `96k/24`。
- macOS 26 Glass 风格弹窗。
- VOX 当前曲目适配：读取 Track URL 后解析本地音源格式。
- 支持 FLAC、ALAC、WAV/AIFF、DSF 的采样率、位深和声道解析。
- 显示音源格式与 DAC 硬件格式是否一致。
- 多输出流设备会展开显示每一路的活动状态和物理格式。

## 明确不做

- 不播放、不录制、不处理音频。
- 不主动获取 Hog Mode。
- 不修改设备采样率或物理格式。
- 不抓取 VOX 或 Apple Music 的私有日志。
- 不记录格式变化历史。
- 不发送通知。
- 不提供高级诊断视图。
- Demo 阶段使用 1 秒轮询；后续可替换为 CoreAudio 属性监听。

## 安装

下载 Release 中的 DMG，打开后把 `AudioFormatBar.app` 拖入 `Applications`。

也可以在本地构建：

```bash
./scripts/build-app.sh
open dist/AudioFormatBar.app
```

发布版通用二进制：

```bash
./scripts/build-release.sh
```

## 开机自启

应用安装到 `Applications` 后，弹窗内会出现“开机自启”开关。

该功能使用 macOS 的 `SMAppService.mainApp`。如果系统提示需要批准，应用内会提供“打开系统设置”按钮。

## 说明

这里显示的是 DAC 当前物理输出格式，不等同于音源文件原始位深。  
`24-bit in 32-bit container`、系统混音器、音量和 DSP 都可能让二者不同，因此界面不会直接声明 Bit Perfect。

当 VOX 正在运行时，应用会请求 macOS 的“自动化”权限来读取 VOX 当前曲目地址。该权限只用于读取曲目信息和解析本地文件格式，不会控制 VOX 播放。

## 播放器元数据接口

自研播放器可以通过本机 UNIX Domain Socket 向 AudioFormatBar 发送当前音源信息。

- 默认 Socket：`~/Library/Application Support/AudioFormatBar/player.sock`
- 协议：UTF-8 JSON Lines
- 当前版本：v1
- 自动识别：CoreAudio 活跃输出进程和 Hog Mode 进程

完整字段、示例和生命周期说明：

[播放器元数据接口 v1](docs/PLAYER_METADATA_PROTOCOL.md)

测试客户端：

```bash
python3 docs/examples/player_metadata_client.py
```
