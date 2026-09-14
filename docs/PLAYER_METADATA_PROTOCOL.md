# AudioFormatBar 播放器元数据接口 v1

本文档定义自研播放器向 AudioFormatBar 菜单栏应用发送当前音源信息时使用的本机接口。

该接口只用于传递播放状态和格式信息，不传递音频采样数据，也不控制播放器。

## 1. 传输方式

- 类型：UNIX Domain Socket
- Socket 类型：`SOCK_STREAM`
- 默认路径：

```text
~/Library/Application Support/AudioFormatBar/player.sock
```

- 数据编码：UTF-8
- 消息格式：JSON Lines，每条 JSON 后必须发送一个换行符 `\n`
- 单条消息最大长度：64 KiB
- 权限：AudioFormatBar 会创建 `0700` 目录和 `0600` Socket，仅允许当前用户访问

开发阶段可以通过环境变量覆盖路径：

```text
AUDIOFORMATBAR_SOCKET_PATH=/tmp/audioformatbar-dev.sock
```

该环境变量必须同时设置给 AudioFormatBar 和播放器。

## 2. 生命周期

播放器应在以下时机连接并发送消息：

1. 开始播放时立即发送完整 `state`。
2. 切换曲目时立即发送完整 `state`。
3. 播放、暂停、停止状态变化时发送完整 `state`。
4. 音源格式、输出设备或 DSP 状态变化时发送完整 `state`。
5. 播放或暂停期间，每 2 秒发送一次心跳 `state`。
6. 完全停止播放或退出前，发送 `clear`。

播放器可以保持 Socket 连接。AudioFormatBar 会逐行读取消息，不要求每次重连。

如果播放器没有发送 `clear`，AudioFormatBar 会在消息过期后自动隐藏音源信息。默认有效期为 12 秒，可以通过 `expires_in_ms` 修改。

## 3. 自动识别规则

AudioFormatBar 不会只因为收到消息就显示音源信息。它会使用 CoreAudio 实测状态进行校验：

1. 优先匹配 `player.audio_pid`。
2. 其次匹配 `player.pid`。
3. 然后匹配 `player.bundle_id` 与当前正在输出的进程。
4. Hog Mode 持有进程也会参与匹配。
5. 只有在播放器确实与 CoreAudio 活跃输出关联时，音源卡片才会显示。

因此建议同时发送正确的 `bundle_id`、`pid` 和必要的 `audio_pid`。

## 4. 顶层消息

```json
{
  "version": 1,
  "type": "state",
  "sent_at_ms": 1789300000000,
  "expires_in_ms": 5000,
  "sequence": 42,
  "player": {},
  "playback": {},
  "source": {},
  "output": {}
}
```

| 字段 | 类型 | 必需 | 说明 |
|---|---|---:|---|
| `version` | integer | 是 | 当前固定为 `1` |
| `type` | string | 是 | `state` 或 `clear` |
| `sent_at_ms` | integer | 否 | Unix Epoch 毫秒，建议发送 |
| `expires_in_ms` | integer | 否 | 有效期，默认 12000，最小 1000 |
| `sequence` | integer | 否 | 单调递增序号，用于调试和乱序检测 |
| `player` | object | 是 | 播放器身份 |
| `playback` | object | `state` 时是 | 播放状态和曲目 |
| `source` | object | 否 | 音源格式 |
| `output` | object | 否 | 播放器自身的输出状态，当前保留 |

## 5. player

```json
{
  "bundle_id": "com.example.Player",
  "name": "My Player",
  "pid": 12345,
  "audio_pid": 12345
}
```

| 字段 | 类型 | 必需 | 说明 |
|---|---|---:|---|
| `bundle_id` | string | 强烈建议 | 播放器 Bundle Identifier |
| `name` | string | 否 | UI 显示名称 |
| `pid` | integer | 强烈建议 | 主播放器进程 PID |
| `audio_pid` | integer | 否 | 实际向 CoreAudio 输出音频的 PID |

如果音频输出发生在 Helper 进程中，`audio_pid` 应填写 Helper 的真实 PID。

## 6. playback

```json
{
  "state": "playing",
  "track": {
    "title": "Example Track",
    "artist": "Example Artist",
    "album": "Example Album",
    "url": "file:///Users/example/Music/example.flac"
  }
}
```

| 字段 | 类型 | 必需 | 说明 |
|---|---|---:|---|
| `state` | string | 是 | `playing`、`paused` 或 `stopped` |
| `track.title` | string | 否 | 曲目标题 |
| `track.artist` | string | 否 | 艺术家 |
| `track.album` | string | 否 | 专辑 |
| `track.url` | string | 否 | 当前音源 URL，本地文件建议使用 `file://` |

`stopped` 会使音源卡片立即隐藏。

## 7. source

`source` 表示音源文件或解码前的真实格式。

```json
{
  "codec": "FLAC",
  "sample_rate": 96000,
  "bit_depth": 24,
  "channels": 2,
  "lossless": true
}
```

| 字段 | 类型 | 必需 | 说明 |
|---|---|---:|---|
| `codec` | string | 建议 | 例如 `FLAC`、`ALAC`、`PCM`、`WAV`、`AIFF`、`DSD`、`AAC`、`MP3` |
| `sample_rate` | number | 建议 | 采样率，单位 Hz；DSD 填原始 DSD 位率 |
| `bit_depth` | integer | 建议 | 音源位深；DSD 可填 `1` |
| `channels` | integer | 否 | 音源声道数 |
| `lossless` | boolean | 否 | 是否为无损音源 |

如果没有发送 `source`，AudioFormatBar 仍会显示播放器和曲目，但音源格式会显示为未知。

## 8. output

`output` 是可选扩展字段。当前版本会解析该对象，但 UI 暂不展示全部内容。

```json
{
  "device_uid": "AppleUSBAudioEngine:...",
  "hog_mode": true,
  "sample_rate": 96000,
  "bit_depth": 32,
  "non_mixable": true,
  "dsp": false,
  "bit_perfect": true
}
```

AudioFormatBar 始终以 CoreAudio 实测设备状态为准。播放器上报的 `output` 不会覆盖系统实测值。

## 9. 最小可用消息

```json
{"version":1,"type":"state","sent_at_ms":1789300000000,"player":{"bundle_id":"com.example.Player","name":"My Player","pid":12345},"playback":{"state":"playing","track":{"title":"Example Track","artist":"Example Artist"}},"source":{"codec":"FLAC","sample_rate":96000,"bit_depth":24,"channels":2,"lossless":true}}
```

## 10. 完整消息

```json
{
  "version": 1,
  "type": "state",
  "sent_at_ms": 1789300000000,
  "expires_in_ms": 5000,
  "sequence": 42,
  "player": {
    "bundle_id": "com.example.Player",
    "name": "My Player",
    "pid": 12345,
    "audio_pid": 12345
  },
  "playback": {
    "state": "playing",
    "track": {
      "title": "Example Track",
      "artist": "Example Artist",
      "album": "Example Album",
      "url": "file:///Users/example/Music/example.flac"
    }
  },
  "source": {
    "codec": "FLAC",
    "sample_rate": 96000,
    "bit_depth": 24,
    "channels": 2,
    "lossless": true
  },
  "output": {
    "device_uid": "AppleUSBAudioEngine:...",
    "hog_mode": true,
    "sample_rate": 96000,
    "bit_depth": 32,
    "non_mixable": true,
    "dsp": false,
    "bit_perfect": true
  }
}
```

## 11. 暂停

```json
{"version":1,"type":"state","sent_at_ms":1789300001000,"player":{"bundle_id":"com.example.Player","name":"My Player","pid":12345},"playback":{"state":"paused","track":{"title":"Example Track","artist":"Example Artist"}},"source":{"codec":"FLAC","sample_rate":96000,"bit_depth":24,"channels":2,"lossless":true}}
```

## 12. 清除

```json
{"version":1,"type":"clear","sent_at_ms":1789300002000,"player":{"bundle_id":"com.example.Player","name":"My Player","pid":12345}}
```

## 13. 心跳

推荐在播放和暂停期间每 2 秒发送一次完整 `state`。

如果网络流或解码状态没有变化，可以复用上一次 JSON，只需更新：

- `sent_at_ms`
- `sequence`

## 14. 错误处理

AudioFormatBar 会忽略：

- `version` 不是 `1` 的消息
- `type` 不是 `state` 或 `clear` 的消息
- 没有 `bundle_id` 和 `pid` 的消息
- 无效 JSON
- 超过 64 KiB 的单行消息
- 超过有效期的状态
- 无法与当前 CoreAudio 活跃进程匹配的消息

Socket 断开不会让播放器崩溃。播放器可以随时重新连接。

## 15. Swift 发送示例

```swift
import Darwin
import Foundation

func sendPlayerMetadata(_ object: [String: Any], socketPath: String) throws {
    let data = try JSONSerialization.data(withJSONObject: object)
    var payload = data
    payload.append(0x0A)

    let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fileDescriptor >= 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { close(fileDescriptor) }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)

    guard socketPath.utf8.count < MemoryLayout<sockaddr_un>.size - 1 else {
        throw POSIXError(.ENAMETOOLONG)
    }

    _ = withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
        socketPath.withCString { pointer in
            rawBuffer.copyBytes(
                from: UnsafeRawBufferPointer(
                    start: pointer,
                    count: socketPath.utf8.count + 1
                )
            )
        }
    }

    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(
                fileDescriptor,
                $0,
                socklen_t(MemoryLayout<sockaddr_un>.size)
            )
        }
    }

    guard result == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    payload.withUnsafeBytes { rawBuffer in
        _ = write(
            fileDescriptor,
            rawBuffer.baseAddress,
            rawBuffer.count
        )
    }
}
```

## 16. 测试客户端

项目提供了一个 Python 测试客户端：

```bash
python3 docs/examples/player_metadata_client.py
```

它会向默认 Socket 发送一条示例状态消息。
