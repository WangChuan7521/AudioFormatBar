import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: AudioFormatBarModel

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    currentDeviceCard
                    sourceCard
                    deviceSection
                    footer
                }
                .padding(16)
                .frame(width: 430)
                .background(panelBackground)
            }
            .scrollIndicators(.hidden)
            .frame(width: 430, height: panelHeight)
            .clipped()
        }
    }

    private var panelHeight: CGFloat {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 700
        return min(600, max(420, visibleHeight - 96))
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.linearGradient(
                        colors: [.cyan.opacity(0.75), .blue.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 1) {
                Text("音频输出监视器")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(model.currentModeText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.followAutomatically()
            } label: {
                Label("自动跟随", systemImage: model.isFollowingAutomatically ? "scope" : "scope")
            }
            .buttonStyle(.glass)
            .disabled(model.isFollowingAutomatically)
            .help("优先跟随独占设备，其次跟随正在输出和系统默认设备")
        }
    }

    @ViewBuilder
    private var currentDeviceCard: some View {
        if let device = model.currentDevice {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    deviceIcon(device)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(device.name)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            CapabilityBadge(
                                title: device.stateText,
                                systemImage: device.isHogged ? "lock.fill" : "speaker.wave.2.fill",
                                tint: device.isHogged ? .orange : .blue
                            )

                            CapabilityBadge(
                                title: device.transport,
                                systemImage: "cable.connector",
                                tint: .secondary
                            )
                        }
                    }

                    Spacer(minLength: 8)
                }

                HStack(alignment: .bottom, spacing: 16) {
                    MetricView(
                        value: AudioFormatting.sampleRate(device.effectiveSampleRate),
                        label: "采样率",
                        tint: .primary
                    )

                    Divider()
                        .frame(height: 38)

                    MetricView(
                        value: device.physicalFormat?.bitDepthText ?? "未知",
                        label: "物理输出",
                        tint: device.isHogged ? .orange : .primary
                    )
                }

                HStack(spacing: 6) {
                    if let format = device.physicalFormat {
                        CapabilityBadge(
                            title: "\(format.channelsPerFrame) 声道",
                            systemImage: "hifispeaker.2.fill",
                            tint: .secondary
                        )
                        CapabilityBadge(
                            title: format.kindText,
                            systemImage: "number",
                            tint: .secondary
                        )
                        if format.isNonMixable {
                            CapabilityBadge(
                                title: "Non-Mixable",
                                systemImage: "checkmark.seal.fill",
                                tint: .green
                            )
                        }
                    } else {
                        CapabilityBadge(
                            title: "格式不可用",
                            systemImage: "exclamationmark.triangle.fill",
                            tint: .orange
                        )
                    }
                }

                if device.outputStreams.count > 1 {
                    outputStreamsSection(device)
                }

                if hasRateDifference(device) {
                    Text(rateDifferenceText(device))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .glassEffect(
                .regular
                    .tint(device.isHogged ? .orange.opacity(0.13) : .cyan.opacity(0.10))
                    .interactive(),
                in: .rect(cornerRadius: 24)
            )
        } else {
            ContentUnavailableView(
                "未找到输出设备",
                systemImage: "speaker.slash",
                description: Text("连接一个音频输出设备后会自动刷新。")
            )
            .frame(maxWidth: .infinity, minHeight: 190)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
    }

    @ViewBuilder
    private var sourceCard: some View {
        if let source = model.sourceSnapshot {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 11) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.linearGradient(
                                colors: [.purple.opacity(0.65), .indigo.opacity(0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                        Image(systemName: "music.note")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(source.displayTitle)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .lineLimit(2)

                        Text(sourceSubtitle(source))
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    CapabilityBadge(
                        title: source.isPlaying ? "\(source.applicationName) 播放中" : "\(source.applicationName) 已暂停",
                        systemImage: source.isPlaying ? "play.fill" : "pause.fill",
                        tint: source.isPlaying ? .purple : .secondary
                    )
                }

                if let format = source.format {
                    HStack(alignment: .bottom, spacing: 14) {
                        MetricView(
                            value: format.sampleRateText,
                            label: "音源采样率",
                            tint: .primary
                        )

                        Divider()
                            .frame(height: 34)

                        MetricView(
                            value: format.bitDepthText,
                            label: "音源位深",
                            tint: .primary
                        )
                    }

                    HStack(spacing: 6) {
                        CapabilityBadge(
                            title: format.codec,
                            systemImage: "doc.badge.gearshape",
                            tint: .purple
                        )
                        if let channels = format.channels {
                            CapabilityBadge(
                                title: "\(channels) 声道",
                                systemImage: "hifispeaker.2.fill",
                                tint: .secondary
                            )
                        }
                        if format.isLossless {
                            CapabilityBadge(
                                title: "Lossless",
                                systemImage: "checkmark.seal.fill",
                                tint: .green
                            )
                        }

                        sourceComparisonBadges
                    }
                } else if let reason = source.unavailableReason {
                    Label(reason, systemImage: "info.circle")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(15)
            .glassEffect(
                .regular
                    .tint(sourceMatchesHardware ? .green.opacity(0.10) : .purple.opacity(0.10))
                    .interactive(),
                in: .rect(cornerRadius: 22)
            )
        }
    }

    @ViewBuilder
    private var sourceComparisonBadges: some View {
        if let rateMatches = model.sourceSampleRateMatchesCurrentDevice {
            CapabilityBadge(
                title: rateMatches ? "采样率一致" : "采样率不一致",
                systemImage: rateMatches ? "equal.circle.fill" : "exclamationmark.triangle.fill",
                tint: rateMatches ? .green : .orange
            )
        }

        if let bitDepthMatches = model.sourceBitDepthMatchesCurrentDevice {
            CapabilityBadge(
                title: bitDepthMatches ? "位深一致" : "位深容器不同",
                systemImage: bitDepthMatches ? "equal.circle.fill" : "exclamationmark.triangle.fill",
                tint: bitDepthMatches ? .green : .orange
            )
        }
    }

    private var sourceMatchesHardware: Bool {
        let rateMatches = model.sourceSampleRateMatchesCurrentDevice ?? false
        let bitMatches = model.sourceBitDepthMatchesCurrentDevice ?? false
        return rateMatches && bitMatches
    }

    private func sourceSubtitle(_ source: AudioSourceSnapshot) -> String {
        var pieces: [String] = [source.applicationName]
        if let artist = source.artist, !artist.isEmpty {
            pieces.append(artist)
        }
        if let location = source.location {
            pieces.append(fileName(from: location))
        }
        return pieces.joined(separator: " · ")
    }

    private func fileName(from location: String) -> String {
        if let url = URL(string: location), url.isFileURL {
            return url.lastPathComponent
        }
        if location.hasPrefix("/") {
            return URL(fileURLWithPath: location).lastPathComponent
        }
        return location
    }

    private func outputStreamsSection(_ device: AudioOutputDeviceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader("输出流", detail: "\(device.outputStreams.count) 路")

            ForEach(Array(device.outputStreams.enumerated()), id: \.element.id) { index, stream in
                HStack(spacing: 8) {
                    Text("流 \(index + 1)")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .frame(width: 34, alignment: .leading)

                    CapabilityBadge(
                        title: stream.isActive ? "活动" : "未活动",
                        systemImage: stream.isActive ? "waveform" : "pause",
                        tint: stream.isActive ? .blue : .secondary
                    )

                    if let format = stream.physicalFormat {
                        Text("\(format.channelsPerFrame)ch · \(format.bitDepthText) · \(AudioFormatting.sampleRate(format.sampleRate))")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("格式未知")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.035), in: .rect(cornerRadius: 11))
            }
        }
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                "输出设备",
                detail: "刷新于 \(model.refreshTimestamp)"
            )

            VStack(spacing: 7) {
                automaticRow

                ForEach(model.snapshot.devices) { device in
                    DeviceRow(
                        device: device,
                        isSelected: model.isSelected(device),
                        action: { model.selectDevice(device) }
                    )
                }
            }
        }
        .padding(13)
        .glassEffect(.clear, in: .rect(cornerRadius: 22))
    }

    private var automaticRow: some View {
        Button {
            model.followAutomatically()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "scope")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 27)

                VStack(alignment: .leading, spacing: 2) {
                    Text("自动跟随")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("独占设备 → 活跃设备 → 系统默认")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if model.isFollowingAutomatically {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(.rect)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .background(
            model.isFollowingAutomatically ? Color.blue.opacity(0.10) : Color.primary.opacity(0.035),
            in: .rect(cornerRadius: 14)
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                model.refresh()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.glass)

            Button {
                model.openAudioMIDISetup()
            } label: {
                Label("音频 MIDI 设置", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.glass)

            Spacer()

            Button {
                model.quit()
            } label: {
                Label("退出", systemImage: "power")
            }
            .buttonStyle(.glass)
        }
    }

    private var panelBackground: some View {
        LinearGradient(
            colors: [
                Color.cyan.opacity(0.08),
                Color.blue.opacity(0.045),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func deviceIcon(_ device: AudioOutputDeviceSnapshot) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(device.isHogged ? Color.orange.opacity(0.17) : Color.blue.opacity(0.13))

            Image(systemName: device.isHogged ? "lock.fill" : "hifispeaker.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(device.isHogged ? .orange : .blue)
        }
        .frame(width: 42, height: 42)
    }

    private func hasRateDifference(_ device: AudioOutputDeviceSnapshot) -> Bool {
        guard let nominal = device.nominalSampleRate,
              let actual = device.actualSampleRate,
              nominal > 0,
              actual > 0 else {
            return false
        }
        return abs(nominal - actual) > 1
    }

    private func rateDifferenceText(_ device: AudioOutputDeviceSnapshot) -> String {
        "名义采样率 \(AudioFormatting.sampleRate(device.nominalSampleRate)) · 实测 \(AudioFormatting.sampleRate(device.actualSampleRate))"
    }
}

private struct DeviceRow: View {
    let device: AudioOutputDeviceSnapshot
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 27)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(device.name)
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .lineLimit(1)

                        if device.isDefaultOutput {
                            Text("默认")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.blue)
                        }

                        if device.isHogged {
                            Text("独占")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                        }
                    }

                    Text(detailText)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(.rect)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? Color.blue.opacity(0.10) : Color.primary.opacity(0.025),
            in: .rect(cornerRadius: 14)
        )
        .overlay {
            if device.isHogged {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.orange.opacity(0.28), lineWidth: 1)
            }
        }
    }

    private var detailText: String {
        let rate = AudioFormatting.sampleRate(device.effectiveSampleRate)
        let bits = device.physicalFormat?.bitDepthText ?? "未知位深"
        return "\(device.transport) · \(rate) · \(bits)"
    }

    private var iconName: String {
        if device.isHogged { return "lock.fill" }
        if device.isDefaultOutput { return "speaker.wave.2.fill" }
        if !device.activeProcesses.isEmpty { return "waveform" }
        return "hifispeaker"
    }

    private var iconColor: Color {
        if device.isHogged { return .orange }
        if device.isDefaultOutput { return .blue }
        return .secondary
    }
}
