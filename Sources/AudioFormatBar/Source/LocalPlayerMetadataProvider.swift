import Foundation
import OSLog

@MainActor
final class LocalPlayerMetadataProvider {
    private struct Record {
        let message: PlayerMetadataMessage
        let receivedAt: Date
    }

    private var records: [String: Record] = [:]
    private let logger = Logger(
        subsystem: "com.bitbay.audioformatbar",
        category: "PlayerMetadata"
    )

    private lazy var server = LocalPlayerMetadataServer { [weak self] message in
        self?.handle(message)
    }

    func start() {
        server.start()
    }

    func stop() {
        server.stop()
    }

    func snapshot(coreAudio: CoreAudioSnapshot) -> AudioSourceSnapshot? {
        expireStaleRecords()

        let activeProcesses = coreAudio.devices.flatMap(\.activeProcesses)
        let activeProcessIDs = Set(activeProcesses.map(\.pid))
        let activeBundleIDs = Set(activeProcesses.compactMap(\.bundleIdentifier))
        let hogProcessIDs = Set(
            coreAudio.devices
                .filter(\.isHogged)
                .map(\.hogModePID)
        )

        let matched = records.values
            .filter { record in
                guard record.message.playback?.state != "stopped" else { return false }

                if let pid = record.message.player.pid,
                   activeProcessIDs.contains(pid) || hogProcessIDs.contains(pid) {
                    return true
                }

                if let audioPID = record.message.player.audioPid,
                   activeProcessIDs.contains(audioPID) || hogProcessIDs.contains(audioPID) {
                    return true
                }

                if let bundleIdentifier = record.message.player.bundleId,
                   activeBundleIDs.contains(bundleIdentifier) {
                    return true
                }

                return false
            }
            .max { lhs, rhs in
                timestamp(lhs) < timestamp(rhs)
            }

        guard let record = matched else { return nil }
        let snapshot = makeSnapshot(from: record.message)
        logger.debug("Using external player metadata from \(snapshot.applicationName, privacy: .public)")
        return snapshot
    }

    private func handle(_ message: PlayerMetadataMessage) {
        guard message.version == 1 else {
            logger.error("Ignored player metadata with unsupported version \(message.version)")
            return
        }

        let key = recordKey(for: message)
        guard !key.isEmpty else {
            logger.error("Ignored player metadata without bundle_id or pid")
            return
        }

        if message.type == "clear" {
            records.removeValue(forKey: key)
            logger.debug("Cleared external player metadata for \(key, privacy: .public)")
            return
        }

        guard message.type == "state" else {
            logger.error("Ignored player metadata with unsupported type")
            return
        }

        records[key] = Record(message: message, receivedAt: Date())
        logger.debug("Received external player state for \(key, privacy: .public)")
    }

    private func makeSnapshot(from message: PlayerMetadataMessage) -> AudioSourceSnapshot {
        let playback = message.playback
        let source = message.source
        let playerName = message.player.name
            ?? message.player.bundleId
            ?? "外部播放器"

        let format: AudioFileFormatSnapshot?
        if let source {
            format = AudioFileFormatSnapshot(
                codec: source.codec ?? "未知",
                sampleRate: source.sampleRate,
                bitDepth: source.bitDepth,
                channels: source.channels,
                isLossless: source.lossless ?? false,
                container: "Player"
            )
        } else {
            format = nil
        }

        return AudioSourceSnapshot(
            applicationName: playerName,
            trackTitle: playback?.track?.title,
            artist: playback?.track?.artist,
            location: playback?.track?.url,
            isPlaying: playback?.state == "playing",
            format: format,
            unavailableReason: format == nil ? "播放器当前没有发送音源格式。" : nil
        )
    }

    private func expireStaleRecords() {
        let now = Date()
        records = records.filter { _, record in
            let timeout = Double(record.message.expiresInMs ?? 12_000) / 1_000
            return now.timeIntervalSince(record.receivedAt) <= max(1, timeout)
        }
    }

    private func recordKey(for message: PlayerMetadataMessage) -> String {
        if let bundleIdentifier = message.player.bundleId, !bundleIdentifier.isEmpty {
            return "bundle:\(bundleIdentifier)"
        }
        if let pid = message.player.pid {
            return "pid:\(pid)"
        }
        return ""
    }

    private func timestamp(_ record: Record) -> Int64 {
        record.message.sentAtMs ?? Int64(record.receivedAt.timeIntervalSince1970 * 1_000)
    }
}
