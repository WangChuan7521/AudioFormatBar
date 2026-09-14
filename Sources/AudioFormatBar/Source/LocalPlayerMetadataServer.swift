import Darwin
import Foundation
import OSLog

final class LocalPlayerMetadataServer {
    static let defaultSocketPath: String = {
        if let override = ProcessInfo.processInfo.environment["AUDIOFORMATBAR_SOCKET_PATH"],
           !override.isEmpty {
            return override
        }

        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())

        return supportDirectory
            .appendingPathComponent("AudioFormatBar", isDirectory: true)
            .appendingPathComponent("player.sock")
            .path
    }()

    private let socketPath: String
    private let onMessage: (PlayerMetadataMessage) -> Void
    private let queue = DispatchQueue(label: "com.bitbay.audioformatbar.player-metadata")
    private let logger = Logger(
        subsystem: "com.bitbay.audioformatbar",
        category: "PlayerMetadata"
    )

    private var listenerFileDescriptor: Int32 = -1
    private var readSource: DispatchSourceRead?

    init(
        socketPath: String = LocalPlayerMetadataServer.defaultSocketPath,
        onMessage: @escaping (PlayerMetadataMessage) -> Void
    ) {
        self.socketPath = socketPath
        self.onMessage = onMessage
    }

    func start() {
        queue.async { [weak self] in
            self?.startLocked()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopLocked()
        }
    }

    private func startLocked() {
        guard listenerFileDescriptor < 0 else { return }

        guard socketPath.utf8.count < MemoryLayout<sockaddr_un>.size - 1 else {
            logger.error("Player metadata socket path is too long")
            return
        }

        let socketURL = URL(fileURLWithPath: socketPath)
        let directoryURL = socketURL.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            logger.error("Unable to create socket directory: \(error.localizedDescription, privacy: .public)")
            return
        }

        prepareSocketPath()

        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            logger.error("Unable to create UNIX socket: errno \(errno)")
            return
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let pathCopied = withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            socketPath.withCString { pointer in
                let source = UnsafeRawBufferPointer(
                    start: pointer,
                    count: socketPath.utf8.count + 1
                )
                guard source.count <= rawBuffer.count else { return false }
                rawBuffer.copyBytes(from: source)
                return true
            }
        }

        guard pathCopied else {
            close(fileDescriptor)
            logger.error("Unable to encode player metadata socket path")
            return
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(
                    fileDescriptor,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }

        guard bindResult == 0 else {
            close(fileDescriptor)
            logger.error("Unable to bind player metadata socket: errno \(errno)")
            return
        }

        chmod(socketPath, 0o600)
        _ = fcntl(fileDescriptor, F_SETFL, O_NONBLOCK)

        guard listen(fileDescriptor, 8) == 0 else {
            close(fileDescriptor)
            unlink(socketPath)
            logger.error("Unable to listen on player metadata socket: errno \(errno)")
            return
        }

        let source = DispatchSource.makeReadSource(
            fileDescriptor: fileDescriptor,
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.acceptConnectionsLocked()
        }

        listenerFileDescriptor = fileDescriptor
        readSource = source
        source.resume()

        logger.info("Player metadata socket listening at \(self.socketPath, privacy: .public)")
    }

    private func stopLocked() {
        readSource?.cancel()
        readSource = nil

        if listenerFileDescriptor >= 0 {
            close(listenerFileDescriptor)
            listenerFileDescriptor = -1
        }

        unlink(socketPath)
    }

    private func prepareSocketPath() {
        var fileInfo = stat()
        guard lstat(socketPath, &fileInfo) == 0 else { return }

        if (fileInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK) {
            unlink(socketPath)
        }
    }

    private func acceptConnectionsLocked() {
        while listenerFileDescriptor >= 0 {
            let clientFileDescriptor = accept(listenerFileDescriptor, nil, nil)

            if clientFileDescriptor < 0 {
                if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
                    logger.error("Unable to accept player metadata client: errno \(errno)")
                }
                return
            }

            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.readClient(fileDescriptor: clientFileDescriptor)
            }
        }
    }

    private func readClient(fileDescriptor: Int32) {
        defer { close(fileDescriptor) }

        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = read(fileDescriptor, &buffer, buffer.count)

            if count > 0 {
                pending.append(contentsOf: buffer[0..<count])
                consumeLines(from: &pending)
                continue
            }

            if count == 0 { return }

            if errno == EINTR { continue }
            return
        }
    }

    private func consumeLines(from pending: inout Data) {
        while let newlineIndex = pending.firstIndex(of: 0x0A) {
            let line = pending[..<newlineIndex]
            pending.removeSubrange(pending.startIndex...newlineIndex)

            guard !line.isEmpty else { continue }
            guard line.count <= 64 * 1024 else {
                logger.error("Ignored an oversized player metadata message")
                continue
            }

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let message = try decoder.decode(PlayerMetadataMessage.self, from: line)
                DispatchQueue.main.async { [weak self] in
                    self?.onMessage(message)
                }
            } catch {
                logger.error("Invalid player metadata JSON: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
