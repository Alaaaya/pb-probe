import Foundation

// One in-memory permission, minted only after a successful copy and lease close.
// Never persisted: relaunching must never restart the respring payload.
struct ProbeRefreshGate {
    private(set) var awaitingConfirmation = false
    private(set) var running = false

    mutating func copyFinished(success: Bool) {
        awaitingConfirmation = success
        running = false
    }
    mutating func decide(confirmed: Bool) -> Bool {
        guard awaitingConfirmation, !running else { return false }
        awaitingConfirmation = false
        running = confirmed
        return confirmed
    }
    mutating func stop() { running = false }
}

// Independent, app-local evidence. No PosterBoard lease or datastore changes.
enum ProbeRefreshEvidence {
    static func record(_ text: String) throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try record(text, documents: documents)
    }
    static func record(_ text: String, documents: URL) throws {
        let file = documents.appendingPathComponent("LastRefreshAttempt.txt")
        var bytes = (try? Data(contentsOf: file)) ?? Data()
        guard bytes.count < 128_000 else {
            throw NSError(domain: "PBProbe.Refresh", code: 1, userInfo: [NSLocalizedDescriptionKey: "Refresh evidence is full. Preserve LastRefreshAttempt.txt before another test."])
        }
        bytes.append(Data(("\(Date()) · " + text + "\n").utf8))
        try bytes.write(to: file, options: .atomic)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.synchronize()
    }
    static func previous() -> String? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let file = documents.appendingPathComponent("LastRefreshAttempt.txt")
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 128_000 else { return nil }
        return try? String(contentsOf: file, encoding: .utf8)
    }
}
