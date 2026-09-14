import CoreAudio
import Foundation

struct AudioStreamFormat: Equatable, Sendable {
    let sampleRate: Double
    let bitsPerChannel: UInt32
    let channelsPerFrame: UInt32
    let bytesPerFrame: UInt32
    let isFloat: Bool
    let isSignedInteger: Bool
    let isNonMixable: Bool
    let isPacked: Bool
    let isBigEndian: Bool

    var bitDepthText: String {
        guard bitsPerChannel > 0 else { return "未知位深" }
        if isFloat {
            return "\(bitsPerChannel)-bit Float"
        }
        return "\(bitsPerChannel)-bit"
    }

    var kindText: String {
        if isFloat { return "Float" }
        if isSignedInteger { return "Integer" }
        if bitsPerChannel > 0 { return "PCM" }
        return "未知格式"
    }
}

struct AudioStreamSnapshot: Identifiable, Equatable, Sendable {
    let id: AudioStreamID
    let isActive: Bool
    let startingChannel: UInt32?
    let physicalFormat: AudioStreamFormat?
    let virtualFormat: AudioStreamFormat?
}

struct AudioProcessSnapshot: Identifiable, Equatable, Sendable {
    let id: AudioObjectID
    let pid: pid_t
    let bundleIdentifier: String?
    let name: String?
    let outputDeviceIDs: [AudioDeviceID]
    let isRunningOutput: Bool

    var displayName: String {
        name ?? bundleIdentifier ?? "PID \(pid)"
    }
}

struct AudioOutputDeviceSnapshot: Identifiable, Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: String
    let isDefaultOutput: Bool
    let isRunningSomewhere: Bool
    let nominalSampleRate: Double?
    let actualSampleRate: Double?
    let outputStreams: [AudioStreamSnapshot]
    let hogModePID: pid_t
    let hogModeProcessName: String?
    let activeProcesses: [AudioProcessSnapshot]

    var isHogged: Bool {
        hogModePID > 0
    }

    var primaryOutputStream: AudioStreamSnapshot? {
        outputStreams.first(where: \.isActive) ?? outputStreams.first
    }

    var physicalFormat: AudioStreamFormat? {
        primaryOutputStream?.physicalFormat
    }

    var virtualFormat: AudioStreamFormat? {
        primaryOutputStream?.virtualFormat
    }

    var effectiveSampleRate: Double? {
        if let actualSampleRate, actualSampleRate > 0 {
            return actualSampleRate
        }
        if let nominalSampleRate, nominalSampleRate > 0 {
            return nominalSampleRate
        }
        return physicalFormat?.sampleRate
    }

    var bitDepth: UInt32? {
        guard let bits = physicalFormat?.bitsPerChannel, bits > 0 else { return nil }
        return bits
    }

    var activeProcessNames: [String] {
        activeProcesses.map(\.displayName)
    }

    var stateText: String {
        if let hogModeProcessName {
            return "\(hogModeProcessName) 独占"
        }
        if isHogged {
            return "独占中"
        }
        if isDefaultOutput {
            return "系统默认"
        }
        if !activeProcesses.isEmpty {
            return "正在使用"
        }
        if isRunningSomewhere {
            return "设备运行中"
        }
        return "已选择"
    }
}


struct AudioFileFormatSnapshot: Equatable, Sendable {
    let codec: String
    let sampleRate: Double?
    let bitDepth: UInt32?
    let channels: UInt32?
    let isLossless: Bool
    let container: String

    var sampleRateText: String {
        AudioFormatting.sampleRate(sampleRate)
    }

    var bitDepthText: String {
        guard let bitDepth, bitDepth > 0 else {
            return isLossless ? "位深未知" : "有损格式"
        }
        return "\(bitDepth)-bit"
    }
}

struct AudioSourceSnapshot: Equatable, Sendable {
    let applicationName: String
    let trackTitle: String?
    let artist: String?
    let location: String?
    let isPlaying: Bool
    let format: AudioFileFormatSnapshot?
    let unavailableReason: String?

    var displayTitle: String {
        if let trackTitle, !trackTitle.isEmpty {
            return trackTitle
        }
        return "未检测到当前曲目"
    }
}

struct CoreAudioSnapshot: Equatable, Sendable {
    let devices: [AudioOutputDeviceSnapshot]
    let defaultOutputDeviceID: AudioDeviceID?
    let capturedAt: Date

    static let empty = CoreAudioSnapshot(
        devices: [],
        defaultOutputDeviceID: nil,
        capturedAt: .distantPast
    )
}

enum AudioFormatting {
    static func sampleRate(_ value: Double?) -> String {
        guard let value, value > 0 else { return "未知" }
        let kHz = value / 1_000

        if abs(kHz.rounded() - kHz) < 0.0001 {
            return "\(Int(kHz.rounded())) kHz"
        }
        return String(format: "%.1f kHz", kHz)
    }

    static func compactSampleRate(_ value: Double?) -> String {
        guard let value, value > 0 else { return "--" }
        let kHz = value / 1_000

        if abs(kHz.rounded() - kHz) < 0.0001 {
            return "\(Int(kHz.rounded()))k"
        }
        return String(format: "%.1fk", kHz)
    }

    static func compactBitDepth(_ format: AudioStreamFormat?) -> String {
        guard let format, format.bitsPerChannel > 0 else { return "--" }
        return "\(format.bitsPerChannel)"
    }

    static func transport(_ value: UInt32) -> String {
        switch value {
        case kAudioDeviceTransportTypeBuiltIn:
            return "内置"
        case kAudioDeviceTransportTypeUSB:
            return "USB"
        case kAudioDeviceTransportTypeBluetooth:
            return "Bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE:
            return "Bluetooth LE"
        case kAudioDeviceTransportTypeHDMI:
            return "HDMI"
        case kAudioDeviceTransportTypeDisplayPort:
            return "DisplayPort"
        case kAudioDeviceTransportTypeThunderbolt:
            return "Thunderbolt"
        case kAudioDeviceTransportTypeFireWire:
            return "FireWire"
        case kAudioDeviceTransportTypePCI:
            return "PCI"
        case kAudioDeviceTransportTypeVirtual:
            return "虚拟设备"
        case kAudioDeviceTransportTypeAggregate:
            return "聚合设备"
        case kAudioDeviceTransportTypeAirPlay:
            return "AirPlay"
        case kAudioDeviceTransportTypeAVB:
            return "AVB"
        default:
            return "其他"
        }
    }
}
