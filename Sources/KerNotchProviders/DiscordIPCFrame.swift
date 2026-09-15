import Foundation

/// The kinds of packet Discord's local IPC socket carries.
enum DiscordIPCOpcode: UInt32, Sendable {
    case handshake = 0
    case frame = 1
    case close = 2
    case ping = 3
    case pong = 4
}

/// One packet on Discord's IPC socket: a little-endian `UInt32` opcode, a
/// little-endian `UInt32` payload length, then that many bytes of UTF-8 JSON.
struct DiscordIPCFrame: Equatable, Sendable {
    static let headerLength = 8

    let opcode: DiscordIPCOpcode
    let payload: Data

    var encoded: Data {
        var data = Data(capacity: Self.headerLength + payload.count)
        withUnsafeBytes(of: opcode.rawValue.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(payload.count).littleEndian) { data.append(contentsOf: $0) }
        data.append(payload)
        return data
    }
}

enum DiscordIPCFrameError: Error, Equatable {
    case unknownOpcode(UInt32)
    case oversizedPayload(UInt32)
}

/// Reassembles frames from a byte stream that arrives in arbitrary pieces.
///
/// A stream socket owes no alignment between reads and frames: one read can end
/// mid-header, and one can carry several frames. Buffering here keeps that out
/// of everything above the transport.
struct DiscordIPCFrameDecoder {
    /// Far above anything Discord sends — a full voice-settings payload is a few
    /// kilobytes — and low enough that a corrupt length cannot make KerNotch
    /// buffer without limit.
    static let maximumPayloadLength: UInt32 = 1 << 20

    private var buffer = Data()

    mutating func append(_ bytes: Data) throws -> [DiscordIPCFrame] {
        buffer.append(bytes)

        var frames: [DiscordIPCFrame] = []
        while let frame = try nextFrame() {
            frames.append(frame)
        }
        return frames
    }

    private mutating func nextFrame() throws -> DiscordIPCFrame? {
        guard buffer.count >= DiscordIPCFrame.headerLength else { return nil }

        let rawOpcode = readUInt32(at: 0)
        let length = readUInt32(at: 4)

        guard let opcode = DiscordIPCOpcode(rawValue: rawOpcode) else {
            throw DiscordIPCFrameError.unknownOpcode(rawOpcode)
        }
        guard length <= Self.maximumPayloadLength else {
            throw DiscordIPCFrameError.oversizedPayload(length)
        }

        let frameLength = DiscordIPCFrame.headerLength + Int(length)
        guard buffer.count >= frameLength else { return nil }

        let start = buffer.startIndex
        let payload = Data(buffer[(start + DiscordIPCFrame.headerLength)..<(start + frameLength)])
        buffer.removeFirst(frameLength)
        return DiscordIPCFrame(opcode: opcode, payload: payload)
    }

    private func readUInt32(at offset: Int) -> UInt32 {
        let start = buffer.startIndex + offset
        return buffer[start..<(start + 4)].enumerated().reduce(UInt32(0)) { value, byte in
            value | UInt32(byte.element) << (8 * UInt32(byte.offset))
        }
    }
}
