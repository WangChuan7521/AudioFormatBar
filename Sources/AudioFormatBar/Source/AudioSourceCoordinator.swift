import Foundation

@MainActor
final class AudioSourceCoordinator {
    private let voxProvider = VoxSourceProvider()
    private let localPlayerProvider = LocalPlayerMetadataProvider()

    func start() {
        localPlayerProvider.start()
    }

    func stop() {
        localPlayerProvider.stop()
    }

    func snapshot(coreAudio: CoreAudioSnapshot) -> AudioSourceSnapshot? {
        if let localPlayer = localPlayerProvider.snapshot(coreAudio: coreAudio) {
            return localPlayer
        }

        if let vox = voxProvider.snapshot(coreAudio: coreAudio) {
            return vox
        }

        return nil
    }
}
