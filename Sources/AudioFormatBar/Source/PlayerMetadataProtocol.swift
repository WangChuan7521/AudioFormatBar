import Foundation

struct PlayerMetadataMessage: Decodable, Sendable {
    let version: Int
    let type: String
    let sentAtMs: Int64?
    let expiresInMs: Int?
    let sequence: Int64?
    let player: PlayerMetadataPlayer
    let playback: PlayerMetadataPlayback?
    let source: PlayerMetadataSource?
    let output: PlayerMetadataOutput?
}

struct PlayerMetadataPlayer: Decodable, Sendable {
    let bundleId: String?
    let name: String?
    let pid: Int32?
    let audioPid: Int32?
}

struct PlayerMetadataPlayback: Decodable, Sendable {
    let state: String
    let track: PlayerMetadataTrack?
}

struct PlayerMetadataTrack: Decodable, Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let url: String?
}

struct PlayerMetadataSource: Decodable, Sendable {
    let codec: String?
    let sampleRate: Double?
    let bitDepth: UInt32?
    let channels: UInt32?
    let lossless: Bool?
}

struct PlayerMetadataOutput: Decodable, Sendable {
    let deviceUid: String?
    let hogMode: Bool?
    let sampleRate: Double?
    let bitDepth: UInt32?
    let nonMixable: Bool?
    let dsp: Bool?
    let bitPerfect: Bool?
}
