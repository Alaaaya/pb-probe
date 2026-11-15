import Foundation

/// At most one scheduled main-queue delivery, not a task per native checkpoint.
/// Backpressure bounds pending text even if SwiftUI is slow to render.
final class ProbeLogBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""
    private var dropped = 0
    private var evidence = ""
    private var scheduled = false
    private let deliver: @Sendable (String) -> Void

    init(deliver: @escaping @Sendable (String) -> Void) { self.deliver = deliver }

    func submit(_ line: String) {
        lock.lock()
        // Reserve room for bounded access-test evidence independently of the
        // noisy native checkpoints. Flush it last, including under backpressure.
        if line.hasPrefix("INSTALL TEST") || line.hasPrefix("TEST ") || line.hasPrefix("ACCESS TEST COMPLETE") || line.hasPrefix("CLEANUP ERROR") {
            evidence += line + (line.hasSuffix("\n") ? "" : "\n")
            if evidence.utf8.count > 16_000 { evidence = String(evidence.suffix(8_000)) }
        } else if pending.utf8.count < 48_000 {
            pending += line + (line.hasSuffix("\n") ? "" : "\n")
        } else { dropped += 1 }
        let needsSchedule = !scheduled
        scheduled = true
        lock.unlock()
        if needsSchedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in flush() }
        }
    }

    func flush() {
        dispatchPrecondition(condition: .onQueue(.main))
        lock.lock()
        let batch = pending + (dropped > 0 ? "\nLOG BACKPRESSURE · \(dropped) checkpoint lines suppressed\n" : "") + evidence
        pending = ""
        evidence = ""
        dropped = 0
        scheduled = false
        lock.unlock()
        if !batch.isEmpty { deliver(batch) }
    }
}
