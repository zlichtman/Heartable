import Foundation
import os

/// Physical memory the process is charged for, and how much headroom iOS says
/// is left. Memory-limit terminations leave no crash log, so the footprint at
/// the end of a library sync is the evidence a tester can actually hand over.
enum MemoryFootprint {
    private static let log = Logger(subsystem: "com.zlichtman.heartable", category: "memory")

    /// `phys_footprint`, the number jetsam compares against the limit.
    static func current() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return info.phys_footprint
    }

    /// Bytes the process may still allocate before iOS terminates it.
    static func available() -> Int {
        os_proc_available_memory()
    }

    static func megabytes(_ bytes: UInt64) -> Int { Int(bytes / 1_048_576) }

    /// Log a checkpoint, and keep it in Diagnostics when headroom has dropped
    /// below the footprint itself: past that point the next big decode is what
    /// ends the process, and the record must exist before it does.
    static func checkpoint(_ label: String) {
        let footprint = current()
        let headroom = available()
        log.notice("\(label, privacy: .public): footprint \(megabytes(footprint)) MB, available \(headroom / 1_048_576) MB")
        guard headroom > 0, UInt64(headroom) < footprint else { return }
        let summary = "\(label): footprint \(megabytes(footprint)) MB with \(headroom / 1_048_576) MB left"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        Task { await DiagnosticsStore.shared.record(kind: "footprint", build: build, summary: summary, payloadJSON: "{}") }
    }
}
