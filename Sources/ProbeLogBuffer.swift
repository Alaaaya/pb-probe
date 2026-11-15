import Foundation

/// At most one scheduled main-queue delivery, not a task per native checkpoint.
/// Backpressure bounds pending text even if SwiftUI is slow to render.
final class ProbeLogBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""
    private var dropped = 0
    private var scheduled = false
    private let deliver: @Sendable (String) -> Void

    init(deliver: @escaping @Sendable (String) -> Void) { self.deliver = deliver }

    func submit(_ line: String) {
        lock.lock()
        if pending.utf8.count < 48_000 {
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
        let batch = pending + (dropped > 0 ? "\nLOG BACKPRESSURE · \(dropped) checkpoint lines suppressed\n" : "")
        pending = ""
        dropped = 0
        scheduled = false
        lock.unlock()
        if !batch.isEmpty { deliver(batch) }
    }
}
