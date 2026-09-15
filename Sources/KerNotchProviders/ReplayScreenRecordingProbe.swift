import Darwin
import Foundation

/// Reads ReplayKit's open recording movie without asking for Screen Recording
/// permission. The system screenshot toolbar uses the same UI process as video
/// capture, but it never opens this movie, so this is the narrow signal that
/// separates a still screenshot from an active system screen recording.
@MainActor
final class ReplayScreenRecordingProbe {
    private static let replayDaemonPath = "/usr/libexec/replayd"
    private static let descriptorCapacity = 4_096
    private static let processCapacity = 4_096

    private var cachedReplayDaemonPID: pid_t?

    func isRecording() -> Bool {
        if let cachedReplayDaemonPID,
           let paths = openVnodePaths(for: cachedReplayDaemonPID)
        {
            return paths.contains(where: replayRecordingPathIsActive)
        }

        cachedReplayDaemonPID = replayDaemonPID()
        guard
            let cachedReplayDaemonPID,
            let paths = openVnodePaths(for: cachedReplayDaemonPID)
        else { return false }

        return paths.contains(where: replayRecordingPathIsActive)
    }

    private func replayDaemonPID() -> pid_t? {
        var processIdentifiers = [pid_t](repeating: 0, count: Self.processCapacity)
        let bytes = proc_listpids(
            UInt32(PROC_ALL_PIDS),
            0,
            &processIdentifiers,
            Int32(processIdentifiers.count * MemoryLayout<pid_t>.stride)
        )
        let count = max(Int(bytes) / MemoryLayout<pid_t>.stride, 0)

        return processIdentifiers.prefix(count).first { processPath(for: $0) == Self.replayDaemonPath }
    }

    private func processPath(for processIdentifier: pid_t) -> String? {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(processIdentifier, &path, UInt32(path.count))
        guard length > 0 else { return nil }

        let bytes = path.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// `nil` means the cached daemon vanished or became unreadable; an empty
    /// array means the daemon is alive but no recording movie is open.
    private func openVnodePaths(for processIdentifier: pid_t) -> [String]? {
        var descriptors = [proc_fdinfo](
            repeating: proc_fdinfo(),
            count: Self.descriptorCapacity
        )
        let bytes = proc_pidinfo(
            processIdentifier,
            PROC_PIDLISTFDS,
            0,
            &descriptors,
            Int32(descriptors.count * MemoryLayout<proc_fdinfo>.stride)
        )
        guard bytes > 0 else { return nil }

        let count = Int(bytes) / MemoryLayout<proc_fdinfo>.stride
        return descriptors.prefix(count).compactMap { descriptor in
            guard descriptor.proc_fdtype == PROX_FDTYPE_VNODE else { return nil }

            var information = vnode_fdinfowithpath()
            let result = proc_pidfdinfo(
                processIdentifier,
                descriptor.proc_fd,
                PROC_PIDFDVNODEPATHINFO,
                &information,
                Int32(MemoryLayout<vnode_fdinfowithpath>.stride)
            )
            guard result > 0 else { return nil }

            return withUnsafeBytes(of: &information.pvip.vip_path) { buffer in
                String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
            }
        }
    }
}

func replayRecordingPathIsActive(_ path: String) -> Bool {
    path.hasSuffix(".mov")
        && path.contains("/Library/Group Containers/group.com.apple.screencapture/ScreenRecordings/")
}
