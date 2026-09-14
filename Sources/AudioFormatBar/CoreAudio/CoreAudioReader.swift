import AppKit
import CoreAudio
import Foundation

final class CoreAudioReader {
    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private let globalScope = kAudioObjectPropertyScopeGlobal
    private let outputScope = kAudioObjectPropertyScopeOutput
    private let mainElement = kAudioObjectPropertyElementMain

    func snapshot() -> CoreAudioSnapshot {
        let processes = readProcesses()
        let defaultOutputID: AudioDeviceID? = readValue(
            systemObject,
            kAudioHardwarePropertyDefaultOutputDevice
        )

        let devices = readArray(
            systemObject,
            kAudioHardwarePropertyDevices,
            scope: globalScope,
            element: mainElement,
            as: AudioDeviceID.self
        )
        .compactMap { deviceID in
            readDevice(
                deviceID,
                isDefaultOutput: deviceID == defaultOutputID,
                processes: processes
            )
        }
        .sorted(by: deviceSort)

        return CoreAudioSnapshot(
            devices: devices,
            defaultOutputDeviceID: defaultOutputID,
            capturedAt: Date()
        )
    }

    private func readDevice(
        _ deviceID: AudioDeviceID,
        isDefaultOutput: Bool,
        processes: [AudioProcessSnapshot]
    ) -> AudioOutputDeviceSnapshot? {
        let streams: [AudioStreamID] = readArray(
            deviceID,
            kAudioDevicePropertyStreams,
            scope: outputScope,
            element: mainElement,
            as: AudioStreamID.self
        )

        guard !streams.isEmpty else { return nil }

        let uid = readString(deviceID, kAudioDevicePropertyDeviceUID) ?? "device-\(deviceID)"
        let name = readString(deviceID, kAudioObjectPropertyName)
            ?? readString(deviceID, kAudioDevicePropertyDeviceNameCFString)
            ?? "未命名设备 \(deviceID)"

        let transportValue: UInt32? = readValue(deviceID, kAudioDevicePropertyTransportType)
        let transport = AudioFormatting.transport(transportValue ?? 0)

        let isRunningValue: UInt32? = readValue(
            deviceID,
            kAudioDevicePropertyDeviceIsRunningSomewhere
        )

        let nominalRate: Double? = readValue(
            deviceID,
            kAudioDevicePropertyNominalSampleRate
        )

        let actualRate: Double? = readValue(
            deviceID,
            kAudioDevicePropertyActualSampleRate
        )

        let outputStreams = readStreamSnapshots(from: streams)
        let hogPID: pid_t = readValue(deviceID, kAudioDevicePropertyHogMode) ?? -1

        let activeProcesses = processes.filter { process in
            process.isRunningOutput && process.outputDeviceIDs.contains(deviceID)
        }

        let hogProcess = processes.first(where: { $0.pid == hogPID })
        let hogName = hogProcess?.displayName ?? processDisplayName(pid: hogPID)

        return AudioOutputDeviceSnapshot(
            id: deviceID,
            uid: uid,
            name: name,
            transport: transport,
            isDefaultOutput: isDefaultOutput,
            isRunningSomewhere: (isRunningValue ?? 0) != 0,
            nominalSampleRate: nominalRate,
            actualSampleRate: actualRate,
            outputStreams: outputStreams,
            hogModePID: hogPID,
            hogModeProcessName: hogName,
            activeProcesses: activeProcesses
        )
    }

    private func readStreamSnapshots(from streams: [AudioStreamID]) -> [AudioStreamSnapshot] {
        streams.compactMap { streamID in
            let activeValue: UInt32? = readValue(streamID, kAudioStreamPropertyIsActive)
            let startingChannel: UInt32? = readValue(
                streamID,
                kAudioStreamPropertyStartingChannel
            )
            let physicalDescription: AudioStreamBasicDescription? = readValue(
                streamID,
                kAudioStreamPropertyPhysicalFormat
            )
            let virtualDescription: AudioStreamBasicDescription? = readValue(
                streamID,
                kAudioStreamPropertyVirtualFormat
            )

            guard physicalDescription != nil || virtualDescription != nil else { return nil }

            return AudioStreamSnapshot(
                id: streamID,
                isActive: (activeValue ?? 1) != 0,
                startingChannel: startingChannel,
                physicalFormat: physicalDescription.map(AudioStreamFormat.init),
                virtualFormat: virtualDescription.map(AudioStreamFormat.init)
            )
        }
    }

    private func readProcesses() -> [AudioProcessSnapshot] {
        let processObjects: [AudioObjectID] = readArray(
            systemObject,
            kAudioHardwarePropertyProcessObjectList,
            scope: globalScope,
            element: mainElement,
            as: AudioObjectID.self
        )

        return processObjects.compactMap { processObject in
            guard let pid: pid_t = readValue(processObject, kAudioProcessPropertyPID) else {
                return nil
            }

            let outputDeviceIDs: [AudioDeviceID] = readArray(
                processObject,
                kAudioProcessPropertyDevices,
                scope: outputScope,
                element: mainElement,
                as: AudioDeviceID.self
            )

            let runningValue: UInt32? = readValue(
                processObject,
                kAudioProcessPropertyIsRunningOutput
            )

            let isRunningOutput = (runningValue ?? 0) != 0
            guard isRunningOutput || !outputDeviceIDs.isEmpty else { return nil }

            let bundleIdentifier = readString(processObject, kAudioProcessPropertyBundleID)
            let name = processDisplayName(pid: pid)

            return AudioProcessSnapshot(
                id: processObject,
                pid: pid,
                bundleIdentifier: bundleIdentifier,
                name: name,
                outputDeviceIDs: outputDeviceIDs,
                isRunningOutput: isRunningOutput
            )
        }
    }

    private func processDisplayName(pid: pid_t) -> String? {
        guard pid > 0 else { return nil }

        if let application = NSRunningApplication(processIdentifier: pid) {
            if let name = application.localizedName, !name.isEmpty {
                return name
            }
            if let bundleIdentifier = application.bundleIdentifier, !bundleIdentifier.isEmpty {
                return bundleIdentifier
            }
        }

        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let result = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        guard result > 0 else { return nil }

        let path = String(cString: pathBuffer)
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func deviceSort(
        _ lhs: AudioOutputDeviceSnapshot,
        _ rhs: AudioOutputDeviceSnapshot
    ) -> Bool {
        let lhsScore = devicePriority(lhs)
        let rhsScore = devicePriority(rhs)

        if lhsScore != rhsScore { return lhsScore > rhsScore }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private func devicePriority(_ device: AudioOutputDeviceSnapshot) -> Int {
        var score = 0
        if device.isHogged { score += 1_000 }
        if !device.activeProcesses.isEmpty { score += 100 }
        if device.isDefaultOutput { score += 10 }
        if device.isRunningSomewhere { score += 1 }
        return score
    }

    private func readValue<T>(
        _ objectID: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope? = nil,
        element: AudioObjectPropertyElement? = nil
    ) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope ?? globalScope,
            mElement: element ?? mainElement
        )
        var size = UInt32(MemoryLayout<T>.size)
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<T>.size,
            alignment: MemoryLayout<T>.alignment
        )
        defer { raw.deallocate() }

        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &size,
            raw
        )

        guard status == noErr, size == UInt32(MemoryLayout<T>.size) else { return nil }
        return raw.load(as: T.self)
    }

    private func readString(
        _ objectID: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope? = nil,
        element: AudioObjectPropertyElement? = nil
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope ?? globalScope,
            mElement: element ?? mainElement
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?

        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &size,
                pointer
            )
        }

        guard status == noErr, let value else { return nil }
        return value as String
    }

    private func readArray<T>(
        _ objectID: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement,
        as type: T.Type
    ) -> [T] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
        var size: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<T>.stride) else {
            return []
        }

        let count = Int(size) / MemoryLayout<T>.stride
        guard count > 0 else { return [] }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<T>.alignment
        )
        defer { raw.deallocate() }

        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &size,
            raw
        )

        guard status == noErr else { return [] }
        let buffer = UnsafeBufferPointer(
            start: raw.assumingMemoryBound(to: T.self),
            count: count
        )
        return Array(buffer)
    }
}

private extension AudioStreamFormat {
    init(_ description: AudioStreamBasicDescription) {
        let flags = description.mFormatFlags
        self.init(
            sampleRate: description.mSampleRate,
            bitsPerChannel: description.mBitsPerChannel,
            channelsPerFrame: description.mChannelsPerFrame,
            bytesPerFrame: description.mBytesPerFrame,
            isFloat: (flags & kAudioFormatFlagIsFloat) != 0,
            isSignedInteger: (flags & kAudioFormatFlagIsSignedInteger) != 0,
            isNonMixable: (flags & kAudioFormatFlagIsNonMixable) != 0,
            isPacked: (flags & kAudioFormatFlagIsPacked) != 0,
            isBigEndian: (flags & kAudioFormatFlagIsBigEndian) != 0
        )
    }
}
