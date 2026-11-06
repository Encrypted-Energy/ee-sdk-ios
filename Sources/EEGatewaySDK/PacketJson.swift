/// Ingest body builder for POST /api/v1/gateways/packets (plan §1a). Field
/// names and types mirror the iOS 1.2 wire format byte-for-byte:
/// unix-seconds integers for timestamp/position_at, doubles for
/// coords/accuracy, unpadded lowercase hex eid. accuracy_m is omitted when
/// the fix carried none.
///
/// Port of ee-sdk-android PacketJson; throws (instead of Kotlin's unchecked
/// IllegalArgumentException) on a non-finite coordinate — unreachable when
/// packets come through LocationFix.of, which is the only supported path.
enum PacketJson {

    static func body(_ packets: [UploadPacket]) throws -> String {
        let items = try packets.map { Json.Raw(text: try packet($0)) }
        return try Json.obj([("packets", Json.Raw(text: Json.arr(items)))])
    }

    static func packet(_ p: UploadPacket) throws -> String {
        var fields: [(String, Any)] = [
            ("payload_b64", p.payloadB64),
            ("rssi", p.rssi),
            ("timestamp", p.timestampSeconds),
            ("latitude", p.latitude),
            ("longitude", p.longitude),
            ("position_at", p.positionAtSeconds),
            ("eid", p.eidHex),
        ]
        if let accuracy = p.accuracyM {
            fields.append(("accuracy_m", accuracy))
        }
        return try Json.obj(fields)
    }
}
