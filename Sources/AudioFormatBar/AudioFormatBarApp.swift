import AppKit
import Darwin
import ServiceManagement
import SwiftUI

@main
@MainActor
struct AudioFormatBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AudioFormatBarModel

    init() {
        if CommandLine.arguments.contains("--dump") {
            Self.dumpCoreAudioSnapshot()
            exit(EXIT_SUCCESS)
        }

        if let index = CommandLine.arguments.firstIndex(of: "--parse-source"),
           CommandLine.arguments.indices.contains(index + 1) {
            Self.parseSourceFile(CommandLine.arguments[index + 1])
            exit(EXIT_SUCCESS)
        }

        if CommandLine.arguments.contains("--login-item-status") {
            print(Self.loginItemStatusText)
            exit(EXIT_SUCCESS)
        }

        if CommandLine.arguments.contains("--enable-login-item") {
            do {
                try SMAppService.mainApp.register()
                print(Self.loginItemStatusText)
                exit(EXIT_SUCCESS)
            } catch {
                fputs("Unable to enable login item: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }

        if CommandLine.arguments.contains("--disable-login-item") {
            do {
                if SMAppService.mainApp.status != .notRegistered {
                    try SMAppService.mainApp.unregister()
                }
                print(Self.loginItemStatusText)
                exit(EXIT_SUCCESS)
            } catch {
                fputs("Unable to disable login item: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }

        let model = AudioFormatBarModel()
        _model = StateObject(wrappedValue: model)
        model.start()
    }

    private static var loginItemStatusText: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "enabled"
        case .requiresApproval:
            return "requires-approval"
        case .notRegistered:
            return "not-registered"
        case .notFound:
            return "not-found"
        @unknown default:
            return "unknown"
        }
    }

    private static func dumpCoreAudioSnapshot() {
        let snapshot = CoreAudioReader().snapshot()
        print("Captured: \(snapshot.capturedAt)")
        print("Devices: \(snapshot.devices.count)")

        for device in snapshot.devices {
            let rate = AudioFormatting.sampleRate(device.effectiveSampleRate)
            let bits = device.physicalFormat?.bitDepthText ?? "unknown"
            print("")
            print("[\(device.id)] \(device.name)")
            print("  UID: \(device.uid)")
            print("  Transport: \(device.transport)")
            print("  Default: \(device.isDefaultOutput)")
            print("  Running: \(device.isRunningSomewhere)")
            print("  Format: \(rate), \(bits)")
            print("  Output streams: \(device.outputStreams.count)")
            for (index, stream) in device.outputStreams.enumerated() {
                let streamBits = stream.physicalFormat?.bitDepthText ?? "unknown"
                let streamRate = AudioFormatting.sampleRate(stream.physicalFormat?.sampleRate)
                print("    \(index + 1): active=\(stream.isActive), \(streamRate), \(streamBits)")
            }
            print("  Hog PID: \(device.hogModePID), process: \(device.hogModeProcessName ?? "-")")
            print("  Active processes: \(device.activeProcessNames.joined(separator: ", "))")
        }
    }

    private static func parseSourceFile(_ path: String) {
        let url = URL(fileURLWithPath: path)
        guard let format = LocalAudioFileProbe.probe(url: url) else {
            print("Unable to parse: \(path)")
            return
        }

        print("Path: \(path)")
        print("Codec: \(format.codec)")
        print("Sample rate: \(format.sampleRateText)")
        print("Bit depth: \(format.bitDepthText)")
        print("Channels: \(format.channels.map(String.init) ?? "unknown")")
        print("Lossless: \(format.isLossless)")
        print("Container: \(format.container)")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.statusBarSymbol)
                Text(model.statusBarText)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
