import AppKit
import Foundation

@MainActor
final class VoxSourceProvider {
    private let voxBundleIdentifier = "com.coppertino.Vox"
    private let separator = "|~|"

    private var lastLocation: String?
    private var lastFormat: AudioFileFormatSnapshot?
    private var lastProbeFailure: String?

    func snapshot(coreAudio: CoreAudioSnapshot) -> AudioSourceSnapshot? {
        guard isActiveInCoreAudio(coreAudio) else {
            resetCache()
            return nil
        }

        guard let track = readCurrentTrack() else {
            return AudioSourceSnapshot(
                applicationName: "VOX",
                trackTitle: nil,
                artist: nil,
                location: nil,
                isPlaying: false,
                format: nil,
                unavailableReason: "无法读取 VOX 播放信息；首次使用时需要允许“自动化”权限。"
            )
        }

        var format: AudioFileFormatSnapshot?
        var unavailableReason: String?

        if let location = track.location, !location.isEmpty {
            if location != lastLocation {
                lastLocation = location
                lastFormat = probe(location: location)
                lastProbeFailure = lastFormat == nil
                    ? "当前音源不是可解析的本地 PCM/DSD 文件。"
                    : nil
            }
            format = lastFormat
            unavailableReason = lastProbeFailure
        } else {
            unavailableReason = "VOX 当前没有可读取的曲目地址。"
        }

        return AudioSourceSnapshot(
            applicationName: "VOX",
            trackTitle: track.title,
            artist: track.artist,
            location: track.location,
            isPlaying: track.isPlaying,
            format: format,
            unavailableReason: unavailableReason
        )
    }

    private func isActiveInCoreAudio(_ snapshot: CoreAudioSnapshot) -> Bool {
        let activeProcesses = snapshot.devices.flatMap(\.activeProcesses)
        if activeProcesses.contains(where: { process in
            process.bundleIdentifier == voxBundleIdentifier
                || NSRunningApplication(processIdentifier: process.pid)?
                    .bundleIdentifier == voxBundleIdentifier
        }) {
            return true
        }

        let hogProcessIDs = snapshot.devices
            .filter(\.isHogged)
            .map(\.hogModePID)

        return hogProcessIDs.contains { pid in
            NSRunningApplication(processIdentifier: pid)?
                .bundleIdentifier == voxBundleIdentifier
        }
    }

    private func readCurrentTrack() -> (isPlaying: Bool, location: String?, title: String?, artist: String?)? {
        let source = """
        tell application "VOX"
            set stateValue to player state
            set urlValue to trackUrl
            set titleValue to track
            set artistValue to artist
            return (stateValue as text) & "\(separator)" & urlValue & "\(separator)" & titleValue & "\(separator)" & artistValue
        end tell
        """

        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil, let text = result.stringValue else { return nil }

        let parts = text.components(separatedBy: separator)
        guard parts.count >= 4 else { return nil }

        let state = Int(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let location = normalized(parts[1])
        let title = normalized(parts[2])
        let artist = normalized(parts[3])

        return (
            isPlaying: state == 1,
            location: location,
            title: title,
            artist: artist
        )
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "missing value" else { return nil }
        return trimmed
    }

    private func probe(location: String) -> AudioFileFormatSnapshot? {
        let url: URL?
        if location.hasPrefix("file://") {
            url = URL(string: location)
        } else if location.hasPrefix("/") {
            url = URL(fileURLWithPath: location)
        } else {
            url = URL(string: location)
        }

        guard let url, url.isFileURL else { return nil }
        return LocalAudioFileProbe.probe(url: url)
    }

    private func resetCache() {
        lastLocation = nil
        lastFormat = nil
        lastProbeFailure = nil
    }
}
