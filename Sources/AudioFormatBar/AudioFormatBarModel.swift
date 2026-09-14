import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class AudioFormatBarModel: ObservableObject {
    @Published private(set) var snapshot: CoreAudioSnapshot = .empty
    @Published private(set) var isFollowingAutomatically: Bool
    @Published private(set) var pinnedDeviceUID: String?
    @Published private(set) var lastRefreshError: String?
    @Published private(set) var sourceSnapshot: AudioSourceSnapshot?
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginRequiresApproval = false
    @Published private(set) var launchAtLoginError: String?

    private let reader = CoreAudioReader()
    private let sourceCoordinator = AudioSourceCoordinator()
    private var timer: Timer?
    private let defaults = UserDefaults.standard

    private enum DefaultsKey {
        static let followsAutomatically = "followsAutomatically"
        static let pinnedDeviceUID = "pinnedDeviceUID"
    }

    init() {
        let hasStoredPreference = defaults.object(forKey: DefaultsKey.followsAutomatically) != nil
        let follows = hasStoredPreference
            ? defaults.bool(forKey: DefaultsKey.followsAutomatically)
            : true

        self.isFollowingAutomatically = follows
        self.pinnedDeviceUID = defaults.string(forKey: DefaultsKey.pinnedDeviceUID)
    }

    func start() {
        guard timer == nil else { return }
        sourceCoordinator.start()
        refreshLaunchAtLoginStatus()
        refresh()

        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        timer.tolerance = 2.0
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        sourceCoordinator.stop()
    }

    func refresh() {
        let coreAudioSnapshot = reader.snapshot()
        let deviceInformationChanged = coreAudioSnapshot.devices != snapshot.devices
            || coreAudioSnapshot.defaultOutputDeviceID != snapshot.defaultOutputDeviceID

        if deviceInformationChanged {
            snapshot = coreAudioSnapshot
        }

        let newSourceSnapshot = sourceCoordinator.snapshot(coreAudio: coreAudioSnapshot)
        if newSourceSnapshot != sourceSnapshot {
            sourceSnapshot = newSourceSnapshot
        }

        lastRefreshError = nil
    }

    var isInstalledInApplications: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    var launchAtLoginStatusText: String {
        if !isInstalledInApplications {
            return "请先安装到 Applications"
        }
        if launchAtLoginRequiresApproval {
            return "需要在系统设置中批准"
        }
        if let launchAtLoginError {
            return launchAtLoginError
        }
        return launchAtLoginEnabled ? "已开启" : "未开启"
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard isInstalledInApplications else {
            launchAtLoginError = "请先把应用拖入 Applications 文件夹"
            launchAtLoginEnabled = false
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled
                        || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }

        refreshLaunchAtLoginStatus()
    }

    func refreshLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = status == .enabled
        launchAtLoginRequiresApproval = status == .requiresApproval
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func selectDevice(_ device: AudioOutputDeviceSnapshot) {
        isFollowingAutomatically = false
        pinnedDeviceUID = device.uid
        persistPreferences()
    }

    func followAutomatically() {
        isFollowingAutomatically = true
        pinnedDeviceUID = nil
        persistPreferences()
    }

    var currentDevice: AudioOutputDeviceSnapshot? {
        guard !snapshot.devices.isEmpty else { return nil }

        if !isFollowingAutomatically,
           let pinnedDeviceUID,
           let pinned = snapshot.devices.first(where: { $0.uid == pinnedDeviceUID }) {
            return pinned
        }

        return snapshot.devices.max { lhs, rhs in
            automaticPriority(lhs) < automaticPriority(rhs)
        }
    }

    var isPinnedDeviceMissing: Bool {
        guard !isFollowingAutomatically, let pinnedDeviceUID else { return false }
        return !snapshot.devices.contains(where: { $0.uid == pinnedDeviceUID })
    }

    var statusBarText: String {
        guard let device = currentDevice else { return "Audio" }
        let rate = AudioFormatting.compactSampleRate(device.effectiveSampleRate)
        let bits = AudioFormatting.compactBitDepth(device.physicalFormat)

        if rate == "--" && bits == "--" {
            return "Audio"
        }
        if bits == "--" {
            return rate
        }
        return "\(rate)/\(bits)"
    }

    var statusBarSymbol: String {
        guard let device = currentDevice else { return "waveform.slash" }
        if device.isHogged { return "lock.fill" }
        if !device.activeProcesses.isEmpty { return "waveform" }
        return "speaker.wave.2.fill"
    }

    var sourceSampleRateMatchesCurrentDevice: Bool? {
        guard let sourceRate = sourceSnapshot?.format?.sampleRate,
              let deviceRate = currentDevice?.effectiveSampleRate else {
            return nil
        }
        return abs(sourceRate - deviceRate) < 1
    }

    var sourceBitDepthMatchesCurrentDevice: Bool? {
        guard let sourceBits = sourceSnapshot?.format?.bitDepth,
              let deviceBits = currentDevice?.physicalFormat?.bitsPerChannel else {
            return nil
        }
        return sourceBits == deviceBits
    }

    var refreshTimestamp: String {
        guard snapshot.capturedAt != .distantPast else { return "等待刷新" }
        return snapshot.capturedAt.formatted(date: .omitted, time: .standard)
    }

    var currentModeText: String {
        if isPinnedDeviceMissing {
            return "固定设备已断开，正在临时回退"
        }
        return isFollowingAutomatically ? "自动跟随" : "固定设备"
    }

    func isSelected(_ device: AudioOutputDeviceSnapshot) -> Bool {
        guard !isFollowingAutomatically else {
            return currentDevice?.uid == device.uid
        }
        return pinnedDeviceUID == device.uid
    }

    func openAudioMIDISetup() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app")
        NSWorkspace.shared.open(url)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func automaticPriority(_ device: AudioOutputDeviceSnapshot) -> Int {
        var score = 0
        if device.isHogged { score += 1_000 }
        if !device.activeProcesses.isEmpty { score += 100 * device.activeProcesses.count }
        if device.isDefaultOutput { score += 20 }
        if device.isRunningSomewhere { score += 2 }
        return score
    }

    private func persistPreferences() {
        defaults.set(isFollowingAutomatically, forKey: DefaultsKey.followsAutomatically)
        if let pinnedDeviceUID {
            defaults.set(pinnedDeviceUID, forKey: DefaultsKey.pinnedDeviceUID)
        } else {
            defaults.removeObject(forKey: DefaultsKey.pinnedDeviceUID)
        }
    }
}
