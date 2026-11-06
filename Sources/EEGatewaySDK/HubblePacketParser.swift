import Foundation

/// A parsed Hubble FCA6 advertisement frame.
///
/// `eidHex` is the server-side identity key: lowercase hex, NO leading-zero
/// padding, matching Python `format(eid, 'x')` on the Pi worker. A frame with
/// `eidHex == nil` must never be enqueued for upload: ee-web rejects the
/// entire batch with 422 if any packet lacks an eid (plan §1a).
struct ParsedPacket: Equatable {
    let version: Int
    let eidHex: String?
    /// The bytes that get base64-encoded into `payload_b64`.
    let payload: Data
}

/// Byte-exact port of pyhubblenetwork/ble.py packet parsing (plan §2).
/// Version is the top 6 bits of the first byte: `raw[0] >> 2`.
///
/// Extracted VERBATIM from gateway-ios HubblePacketParser.swift (branch
/// anonymous-first-onboarding, 131c3f5). Any divergence is a bug.
enum HubblePacketParser {

    static func parse(_ raw: Data) -> ParsedPacket? {
        guard !raw.isEmpty else { return nil }
        // Data slices retain source indices; rebase so subscripts are 0-based.
        let bytes = Data(raw)
        let version = Int(bytes[0] >> 2)

        switch version {
        case 0:
            // AES-CTR: hdr(1) + seq(1) + EID(4, big-endian) + auth_tag(4) + ciphertext.
            // Payload is the ENTIRE raw frame.
            var eidHex: String? = nil
            if bytes.count >= 6 {
                let eid = bytes[2..<6].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                eidHex = String(eid, radix: 16)
            }
            return ParsedPacket(version: 0, eidHex: eidHex, payload: bytes)

        case 1:
            // Unencrypted: 40-bit big-endian header, no EID. Payload is raw[5...].
            // No EID means this frame is dropped before the queue (§1a).
            guard bytes.count >= 5 else {
                return ParsedPacket(version: 1, eidHex: nil, payload: bytes)
            }
            return ParsedPacket(version: 1, eidHex: nil, payload: Data(bytes[5...]))

        case 2:
            // AES-EAX: ver(1) + salt(2) + EID(8, little-endian) + ciphertext(0-9) + tag(4).
            guard bytes.count >= 15 else {
                return ParsedPacket(version: 2, eidHex: nil, payload: bytes)
            }
            let eid = bytes[3..<11].enumerated().reduce(UInt64(0)) { acc, pair in
                acc | (UInt64(pair.element) << (8 * pair.offset))
            }
            let payload = Data(bytes[11..<(bytes.count - 4)])
            return ParsedPacket(version: 2, eidHex: String(eid, radix: 16), payload: payload)

        default:
            // Unknown version: no EID -> dropped before the queue (§1a).
            return ParsedPacket(version: version, eidHex: nil, payload: bytes)
        }
    }
}
