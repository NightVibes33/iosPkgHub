import Foundation
import Network
import Darwin

/// iPhone-side file endpoint for the bundled PS4 payload. The payload enumerates
/// the connected iPhone through sceUsbd, establishes its USBMUX v2 transport,
/// then tunnels PKGBRIDGE/2 commands to this TCP listener over USB.
enum USBBridgeServerError: LocalizedError {
    case fileUnavailable(String)
    case listenerFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileUnavailable(let name):
            return "Could not open the selected PKG file: \(name)"
        case .listenerFailed(let message):
            return "USB bridge listener failed: \(message)"
        }
    }
}

struct USBTransferSnapshot {
    let fraction: Double
    let sentBytes: UInt64
    let totalBytes: UInt64
    let bytesPerSecond: Double
    let remainingSeconds: Double?
}

final class USBBridgeServer {
    static let shared = USBBridgeServer()

    private let queue = DispatchQueue(label: "PKGSender.USBBridge", qos: .userInitiated)
    private var listener: NWListener?
    private var listenerReady = false
    private var listenerGeneration = UUID()
    private var pendingStartCompletions: [(Result<Void, Error>) -> Void] = []
    private var selectedURL: URL?
    private var selectedFD: Int32 = -1
    private var selectedSize: UInt64 = 0
    private var hasSecurityScope = false
    private var transferArmed = false
    private var activeTransferID: UUID?
    private var byteCoverage = ByteRangeCoverage()
    private var transferStartedAt: Date?
    private var lastSampleAt: Date?
    private var lastSampleBytes: UInt64 = 0
    private var smoothedSpeed: Double = 0
    private var transferFinished = false
    private var transferObserver: ((USBTransferSnapshot) -> Void)?
    private(set) var port: UInt16 = 11112

    private init() {}
    deinit { closeSelectedFile() }

    func setTransferObserver(_ observer: ((USBTransferSnapshot) -> Void)?) {
        queue.async { [weak self] in self?.transferObserver = observer }
    }

    func start() {
        queue.async { [weak self] in self?.startLocked() }
    }

    /// Call whenever Home's primary PKG selection changes.
    func setSelectedFile(_ url: URL?) {
        queue.async { [weak self] in self?.setSelectedFileLocked(url) }
    }

    /// Opens the selected file, waits until the listener is ready, and only then
    /// arms INFO/READ requests from the PS4 payload.
    func prepareTransfer(
        fileURL: URL,
        transferID: UUID,
        observer: @escaping (USBTransferSnapshot) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            self.setSelectedFileLocked(fileURL)
            self.activeTransferID = transferID
            self.transferObserver = observer

            guard self.selectedFD >= 0, self.selectedSize > 0 else {
                self.activeTransferID = nil
                self.transferObserver = nil
                let error = USBBridgeServerError.fileUnavailable(fileURL.lastPathComponent)
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            self.startLocked { result in
                switch result {
                case .success:
                    guard self.activeTransferID == transferID else { return }
                    self.resetTransferMetricsLocked()
                    self.transferArmed = true
                    self.log("FILE armed for USB transfer")
                    DispatchQueue.main.async { completion(.success(())) }
                case .failure(let error):
                    guard self.activeTransferID == transferID else { return }
                    self.transferArmed = false
                    self.activeTransferID = nil
                    self.transferObserver = nil
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }
    }

    func disarm() {
        queue.async { [weak self] in
            self?.transferArmed = false
        }
    }

    /// Ends one USB transfer, closes the localhost listener, and releases the
    /// file descriptor/security scope before the next transfer cycle.
    func endTransferCycle() {
        queue.async { [weak self] in
            guard let self else { return }
            self.transferArmed = false
            self.activeTransferID = nil
            self.transferObserver = nil
            self.closeSelectedFile()
            self.stopListenerLocked()
        }
    }

    private func startLocked(completion: ((Result<Void, Error>) -> Void)? = nil) {
        if listenerReady {
            completion?(.success(()))
            return
        }

        if let completion {
            pendingStartCompletions.append(completion)
        }

        guard listener == nil else { return }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard port > 0, let listenPort = NWEndpoint.Port(rawValue: port) else {
                throw USBBridgeServerError.listenerFailed("Invalid bridge port: \(port)")
            }
            let generation = UUID()
            listenerGeneration = generation
            // USBMUX forwards the device-side port to loopback. Binding only
            // to 127.0.0.1 prevents peers on Wi-Fi/LAN from reading selected PKGs.
            params.requiredLocalEndpoint = .hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: listenPort
            )
            let newListener = try NWListener(using: params, on: listenPort)
            newListener.newConnectionHandler = { [weak self] connection in
                guard let self, self.listenerGeneration == generation else { return }
                self.accept(connection)
            }
            newListener.stateUpdateHandler = { [weak self] state in
                guard let self, self.listenerGeneration == generation else { return }
                switch state {
                case .ready:
                    self.listenerReady = true
                    self.log("READY tcp port=\(self.port)")
                    self.finishStartCompletions(.success(()))
                case .failed(let error):
                    self.listenerReady = false
                    self.listener = nil
                    self.log("LISTENER ERROR \(error)")
                    self.finishStartCompletions(.failure(
                        USBBridgeServerError.listenerFailed(error.localizedDescription)
                    ))
                case .cancelled:
                    self.listenerReady = false
                    self.listener = nil
                    self.finishStartCompletions(.failure(
                        USBBridgeServerError.listenerFailed("The listener was cancelled.")
                    ))
                default:
                    break
                }
            }
            listener = newListener
            newListener.start(queue: queue)
        } catch {
            listener = nil
            listenerReady = false
            log("LISTENER ERROR \(error)")
            finishStartCompletions(.failure(
                USBBridgeServerError.listenerFailed(error.localizedDescription)
            ))
        }
    }

    private func finishStartCompletions(_ result: Result<Void, Error>) {
        let callbacks = pendingStartCompletions
        pendingStartCompletions.removeAll()
        callbacks.forEach { $0(result) }
    }

    private func stopListenerLocked() {
        let oldListener = listener
        listener = nil
        listenerReady = false
        listenerGeneration = UUID()
        oldListener?.cancel()
        finishStartCompletions(.failure(
            USBBridgeServerError.listenerFailed("The USB bridge was stopped before it became ready.")
        ))
    }

    private func closeSelectedFile() {
        if selectedFD >= 0 { Darwin.close(selectedFD); selectedFD = -1 }
        if hasSecurityScope { selectedURL?.stopAccessingSecurityScopedResource() }
        selectedURL = nil
        selectedSize = 0
        hasSecurityScope = false
        transferArmed = false
        activeTransferID = nil
        resetTransferMetricsLocked()
    }

    private func setSelectedFileLocked(_ url: URL?) {
        closeSelectedFile()
        guard let url else { log("FILE cleared"); return }
        let scoped = url.startAccessingSecurityScopedResource()
        let fd = Darwin.open(url.path, O_RDONLY)
        guard fd >= 0 else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            log("FILE open failed errno=\(errno) \(url.lastPathComponent)")
            return
        }
        var st = stat()
        guard fstat(fd, &st) == 0 else {
            Darwin.close(fd); if scoped { url.stopAccessingSecurityScopedResource() }
            log("FILE stat failed errno=\(errno)")
            return
        }
        selectedURL = url
        selectedFD = fd
        selectedSize = UInt64(max(0, st.st_size))
        hasSecurityScope = scoped
        log("FILE ready name=\(url.lastPathComponent) bytes=\(selectedSize)")
    }

    private func accept(_ c: NWConnection) {
        log("CLIENT accepted")
        c.start(queue: queue)
        receiveCommand(c, buffer: Data())
    }

    private func receiveCommand(
        _ c: NWConnection,
        buffer: Data,
        inputComplete: Bool = false
    ) {
        var pending = buffer

        // Drain buffered commands before receiving more bytes. A pipelined
        // peer may have delivered several commands in one TCP packet.
        if let newline = pending.firstIndex(of: 0x0A) {
            let lineData = pending[..<newline]
            pending.removeSubrange(...newline)
            guard lineData.count <= 4096 else {
                log("CLIENT command exceeded 4096 bytes")
                send(Data("ERR COMMAND\\n".utf8), on: c) { c.cancel() }
                return
            }

            let line = String(decoding: lineData, as: UTF8.self)
            handle(line: line, on: c) {
                if inputComplete {
                    if pending.isEmpty {
                        self.log("CLIENT closed")
                        c.cancel()
                    } else {
                        self.receiveCommand(c, buffer: pending, inputComplete: true)
                    }
                } else {
                    self.receiveCommand(c, buffer: pending)
                }
            }
            return
        }

        guard pending.count <= 4096 else {
            log("CLIENT command exceeded 4096 bytes")
            send(Data("ERR COMMAND\\n".utf8), on: c) { c.cancel() }
            return
        }
        guard !inputComplete else {
            log("CLIENT closed")
            c.cancel()
            return
        }

        c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let error {
                self.log("CLIENT receive error \\(error)")
                c.cancel()
                return
            }
            var received = pending
            if let data { received.append(data) }
            self.receiveCommand(c, buffer: received, inputComplete: complete)
        }
    }

    private func handle(line: String, on c: NWConnection, completion: @escaping () -> Void) {
        let parts = line.split(separator: " ")
        guard let cmd = parts.first else { completion(); return }

        if cmd == "HELLO" {
            send(Data("PKGBRIDGE/2 READY\n".utf8), on: c, completion: completion)
            return
        }
        if cmd == "INFO" {
            guard selectedFD >= 0, let url = selectedURL else {
                send(Data("ERR NO_FILE\n".utf8), on: c, completion: completion); return
            }
            guard transferArmed else {
                send(Data("WAIT NOT_ARMED\n".utf8), on: c, completion: completion); return
            }
            let safeName = url.lastPathComponent.replacingOccurrences(of: "\n", with: "_")
            send(Data("OK \(selectedSize) \(safeName)\n".utf8), on: c, completion: completion)
            return
        }
        if cmd == "READ", parts.count == 3,
           let off = UInt64(parts[1]), let requested = Int(parts[2]), requested > 0 {
            guard transferArmed, let requestTransferID = activeTransferID else {
                send(Data("WAIT NOT_ARMED\n".utf8), on: c, completion: completion)
                return
            }
            guard selectedFD >= 0, off < selectedSize else {
                send(Data("ERR RANGE\n".utf8), on: c, completion: completion)
                return
            }

            let count = min(requested, 16 * 1024 * 1024, Int(selectedSize - off))
            var data = Data(count: count)
            let got: Int = data.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.pread(selectedFD, base, count, off_t(off))
            }
            guard got > 0 else {
                let code = got < 0 ? errno : EIO
                send(Data("ERR READ \(code)\n".utf8), on: c, completion: completion)
                return
            }
            if got < data.count { data.removeSubrange(got..<data.count) }

            let header = Data("DATA \(off) \(got)\n".utf8)
            c.send(content: header, completion: .contentProcessed { [weak self] headerError in
                if let headerError {
                    self?.log("SEND header error \(headerError)")
                    c.cancel()
                    return
                }
                c.send(content: data, completion: .contentProcessed { [weak self] bodyError in
                    if let bodyError {
                        self?.log("SEND body error \(bodyError)")
                        c.cancel()
                        return
                    }
                    guard let self else { completion(); return }
                    self.queue.async {
                        self.recordTransferredRangeLocked(offset: off, count: got, transferID: requestTransferID)
                        completion()
                    }
                })
            })
            return
        }

        send(Data("ERR COMMAND\n".utf8), on: c, completion: completion)
    }

    private func resetTransferMetricsLocked() {
        byteCoverage.reset()
        transferStartedAt = nil
        lastSampleAt = nil
        lastSampleBytes = 0
        smoothedSpeed = 0
        transferFinished = false
    }

    /// Counts unique file bytes only after the corresponding response body has
    /// completed its Network.framework send callback.
    private func recordTransferredRangeLocked(offset: UInt64, count: Int, transferID: UUID) {
        guard transferArmed, activeTransferID == transferID, count > 0, selectedSize > 0 else { return }
        byteCoverage.add(start: offset, length: UInt64(count), limit: selectedSize)
        let coveredBytes = byteCoverage.coveredBytes

        let now = Date()
        if transferStartedAt == nil {
            transferStartedAt = now
            lastSampleAt = now
            lastSampleBytes = coveredBytes
        }

        if let sampleAt = lastSampleAt {
            let dt = now.timeIntervalSince(sampleAt)
            if dt >= 0.35 || coveredBytes >= selectedSize {
                let delta = coveredBytes >= lastSampleBytes ? coveredBytes - lastSampleBytes : 0
                let instant = dt > 0 ? Double(delta) / dt : 0
                if instant > 0 {
                    smoothedSpeed = smoothedSpeed > 0
                        ? (smoothedSpeed * 0.72 + instant * 0.28)
                        : instant
                }
                lastSampleAt = now
                lastSampleBytes = coveredBytes
            }
        }

        let fraction = min(1, Double(coveredBytes) / Double(selectedSize))
        let remaining = smoothedSpeed > 0
            ? Double(selectedSize - min(coveredBytes, selectedSize)) / smoothedSpeed
            : nil

        transferObserver?(USBTransferSnapshot(
            fraction: fraction,
            sentBytes: min(coveredBytes, selectedSize),
            totalBytes: selectedSize,
            bytesPerSecond: smoothedSpeed,
            remainingSeconds: remaining
        ))

        if fraction >= 1, !transferFinished {
            transferFinished = true
            log("TRANSFER COMPLETE bytes=\(coveredBytes) speed=\(Int(smoothedSpeed)) B/s")
        }
    }

    private func send(
        _ data: Data,
        on c: NWConnection,
        completion: @escaping () -> Void = {}
    ) {
        c.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.log("SEND error \(error)")
                c.cancel()
            }
            completion()
        })
    }

    private func log(_ s: String) {
        // Keep only lifecycle/failure diagnostics. READ/progress chatter is
        // intentionally excluded so logging never competes with USB transfer.
        let important = s.contains("ERROR") || s.contains("error") ||
            s.contains("failed") || s.contains("COMPLETE") || s.hasPrefix("READY")
        guard important else { return }

        let line = "[USBBridge] \(s)\n"
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let u = dir.appendingPathComponent("PKGSender-USBBridge.log")
        let d = Data(line.utf8)
        if FileManager.default.fileExists(atPath: u.path), let h = try? FileHandle(forWritingTo: u) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: d)
        } else {
            try? d.write(to: u, options: .atomic)
        }
    }
}
