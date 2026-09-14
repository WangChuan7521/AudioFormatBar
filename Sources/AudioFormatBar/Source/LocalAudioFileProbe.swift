import AudioToolbox
import Foundation

enum LocalAudioFileProbe {
    static func probe(url: URL) -> AudioFileFormatSnapshot? {
        guard url.isFileURL else { return nil }

        if let dsf = probeDSF(url: url) {
            return dsf
        }

        var fileID: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &fileID) == noErr,
              let fileID else {
            return nil
        }
        defer { AudioFileClose(fileID) }

        var description = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileGetProperty(
            fileID,
            kAudioFilePropertyDataFormat,
            &size,
            &description
        ) == noErr else {
            return nil
        }

        let formatID = description.mFormatID
        let codec = codecName(formatID)
        let lossless = isLossless(formatID)

        var bitDepth = description.mBitsPerChannel
        if bitDepth == 0 {
            switch formatID {
            case kAudioFormatFLAC:
                bitDepth = FlacBitDepthReader.read(url: url) ?? 0
            case kAudioFormatAppleLossless:
                bitDepth = AlacBitDepthReader.read(url: url) ?? 0
            default:
                break
            }
        }

        let sampleRate = description.mSampleRate > 0
            ? description.mSampleRate
            : nil
        let channels = description.mChannelsPerFrame > 0
            ? description.mChannelsPerFrame
            : nil

        return AudioFileFormatSnapshot(
            codec: codec,
            sampleRate: sampleRate,
            bitDepth: bitDepth > 0 ? bitDepth : nil,
            channels: channels,
            isLossless: lossless,
            container: url.pathExtension.uppercased()
        )
    }

    private static func codecName(_ formatID: AudioFormatID) -> String {
        switch formatID {
        case kAudioFormatFLAC:
            return "FLAC"
        case kAudioFormatAppleLossless:
            return "ALAC"
        case kAudioFormatLinearPCM:
            return "PCM"
        case kAudioFormatMPEGLayer1:
            return "MP1"
        case kAudioFormatMPEGLayer2:
            return "MP2"
        case kAudioFormatMPEGLayer3:
            return "MP3"
        case kAudioFormatMPEG4AAC,
             kAudioFormatMPEG4AAC_HE,
             kAudioFormatMPEG4AAC_LD,
             kAudioFormatMPEG4AAC_ELD,
             kAudioFormatMPEG4AAC_ELD_SBR,
             kAudioFormatMPEG4AAC_ELD_V2,
             kAudioFormatMPEG4AAC_HE_V2,
             kAudioFormatMPEG4AAC_Spatial:
            return "AAC"
        case kAudioFormatOpus:
            return "Opus"
        case kAudioFormatAC3:
            return "AC-3"
        case kAudioFormatEnhancedAC3:
            return "E-AC-3"
        default:
            return fourCC(formatID)
        }
    }

    private static func isLossless(_ formatID: AudioFormatID) -> Bool {
        formatID == kAudioFormatFLAC
            || formatID == kAudioFormatAppleLossless
            || formatID == kAudioFormatLinearPCM
    }

    private static func probeDSF(url: URL) -> AudioFileFormatSnapshot? {
        guard let data = mappedData(url: url), data.count >= 52 else { return nil }
        guard data.starts(with: Data("DSD ".utf8)) else { return nil }

        let sampleRate = data.uint32LE(at: 44).map(Double.init)
        let channels = data.uint32LE(at: 40)

        return AudioFileFormatSnapshot(
            codec: "DSD",
            sampleRate: sampleRate,
            bitDepth: 1,
            channels: channels,
            isLossless: true,
            container: "DSF"
        )
    }

    fileprivate static func mappedData(url: URL) -> Data? {
        try? Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private static func fourCC(_ value: UInt32) -> String {
        let bytes: [UInt8] = [24, 16, 8, 0].map {
            UInt8((value >> UInt32($0)) & 0xff)
        }
        return String(bytes: bytes, encoding: .ascii) ?? "未知"
    }
}

private enum FlacBitDepthReader {
    static func read(url: URL) -> UInt32? {
        guard let data = LocalAudioFileProbe.mappedData(url: url),
              data.count >= 42,
              data.starts(with: Data("fLaC".utf8)) else {
            return nil
        }

        let blockType = data[4] & 0x7f
        guard blockType == 0 else { return nil }

        var reader = BitReader(data: data[8..<42])
        _ = reader.read(16)
        _ = reader.read(16)
        _ = reader.read(24)
        _ = reader.read(24)

        guard let _ = reader.read(20),
              let _ = reader.read(3),
              let bitsMinusOne = reader.read(5) else {
            return nil
        }

        return UInt32(bitsMinusOne + 1)
    }
}

private enum AlacBitDepthReader {
    static func read(url: URL) -> UInt32? {
        guard let data = LocalAudioFileProbe.mappedData(url: url) else { return nil }
        let marker = Data("alac".utf8)
        var searchRange = data.startIndex..<data.endIndex

        while let range = data.range(of: marker, options: [], in: searchRange) {
            let cookieStart = range.lowerBound + 8
            let cookieEnd = cookieStart + 24

            if cookieEnd <= data.endIndex {
                let bitDepth = UInt32(data[cookieStart + 5])
                let channels = UInt32(data[cookieStart + 9])
                let sampleRate = data.uint32BE(at: cookieStart + 20)

                if (1...32).contains(bitDepth),
                   (1...64).contains(channels),
                   let sampleRate,
                   sampleRate >= 8_000 {
                    return bitDepth
                }
            }

            searchRange = range.upperBound..<data.endIndex
        }

        return nil
    }
}

private struct BitReader {
    let data: Data
    let bitCount: Int
    var offset = 0

    init(data: Data) {
        self.data = Data(data)
        self.bitCount = data.count * 8
    }

    mutating func read(_ count: Int) -> UInt64? {
        guard offset + count <= bitCount else { return nil }
        var result: UInt64 = 0

        for _ in 0..<count {
            let byteIndex = offset / 8
            let bitIndex = 7 - (offset % 8)
            let bit = (data[byteIndex] >> UInt8(bitIndex)) & 1
            result = (result << 1) | UInt64(bit)
            offset += 1
        }

        return result
    }
}

private extension Data {
    func uint32LE(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            return UInt32(bytes[offset])
                | (UInt32(bytes[offset + 1]) << 8)
                | (UInt32(bytes[offset + 2]) << 16)
                | (UInt32(bytes[offset + 3]) << 24)
        }
    }

    func uint32BE(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            return (UInt32(bytes[offset]) << 24)
                | (UInt32(bytes[offset + 1]) << 16)
                | (UInt32(bytes[offset + 2]) << 8)
                | UInt32(bytes[offset + 3])
        }
    }
}
