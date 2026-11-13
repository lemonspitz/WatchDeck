// `WatchDeck --selftest` checks the protocol code without a watch.
import Foundation
import CryptoKit

func runSelfTest() -> Bool {
    var ok = true
    func check(_ name: String, _ cond: Bool) {
        print((cond ? "PASS  " : "FAIL  ") + name)
        if !cond { ok = false }
    }

    check("CRC16 XMODEM vector", crc16(Data("123456789".utf8)) == 0x31C3)
    check("VarInt 127", TLV.varInt(127) == Data([0x7F]))
    check("VarInt 128", TLV.varInt(128) == Data([0x81, 0x00]))
    check("VarInt 300", TLV.varInt(300) == Data([0x82, 0x2C]))

    let big = Data.random(300)
    let tlv = TLV().with(1).with(2, byte: 7).with(3, short: 0x1234).with(4, int: 100_000).with(5, "héllo").with(0x81, TLV().with(6, big))
    let back = try? TLV(tlv.data)
    check("TLV round trip", back?.int(2) == 7 && back?.int(3) == 0x1234 && back?.int(4) == 100_000
        && back?.string(5) == "héllo" && back?.object(0x81)?.bytes(6) == big && back?.has(1) == true)

    // Known frame: link-params request.
    let link = Packet.frameUnsliced(service: 1, command: 1, body: TLV().with(1).with(2).with(3).with(4).data)[0]
    check("Link params frame", link.hex.hasPrefix("5A000B0001010100020003000400") && link.count == 16)

    let params = LinkParams()
    let asm = PacketAssembler()
    let p1 = asm.feed(link, params: params)
    check("Parse unsliced", p1.count == 1 && p1[0].service == 1 && p1[0].command == 1 && p1[0].tlv.items.count == 4)

    // Sliced frames, delivered in awkward chunks.
    params.sliceSize = 0xF4
    let body = TLV().with(1, Data.random(900)).with(2, "tail").data
    let frames = Packet.frameSliced(service: 0x27, command: 0x02, body: body, sliceSize: params.sliceSize)
    var stream = Data(); frames.forEach { stream.append($0) }
    var got: [Packet] = []
    var pos = 0
    while pos < stream.count { let n = min(37, stream.count - pos); got += asm.feed(stream.subdata(in: pos ..< pos + n), params: params); pos += n }
    check("Sliced frames fit slice size", frames.count > 1 && frames.allSatisfy { $0.count <= 0xF4 })
    check("Parse sliced", got.count == 1 && got[0].raw == body && got[0].tlv.string(2) == "tail")

    // Encrypted round trip, CBC and GCM.
    for gcm in [false, true] {
        params.secretKey = Data.random(gcm ? 32 : 16)
        params.encryptMethod = gcm ? 1 : 0
        let plain = TLV().with(1, byte: 55).with(2, "secret")
        let enc = try? params.encrypt(plain.data)
        let f = Packet.frameSliced(service: 1, command: 8, body: enc?.data ?? Data(), sliceSize: params.sliceSize)
        let r = f.flatMap { asm.feed($0, params: params) }
        check("Encrypted round trip (\(gcm ? "GCM" : "CBC"))", r.count == 1 && r[0].tlv.int(1) == 55 && r[0].tlv.string(2) == "secret")
    }

    // Published test vectors for the primitives.
    check("HMAC-SHA256 RFC 4231 #2", HWCrypto.hmac(key: Data("Jefe".utf8), Data("what do ya want for nothing?".utf8)).hex
        == "5BDCC146BF60754E6A042426089575C75A003F089D2739839DEC58B964EC3843")
    check("PBKDF2-SHA256 vector", HWCrypto.pbkdf2(password: "password", salt: Data("salt".utf8), rounds: 2, length: 32).hex
        == "AE4D0C95AF6B46D32D0ADFF928F06DD02A303F8EF3C251DFD6E2D85A95474C43")
    check("HKDF-SHA256 RFC 5869 #1", HWCrypto.hkdf(key: Data(repeating: 0x0B, count: 22), salt: Data(hex: "000102030405060708090A0B0C"),
                                                    info: Data(hex: "F0F1F2F3F4F5F6F7F8F9"), length: 42).hex
        == "3CB25F25FAACD57A90434F64D0362F2A2D2D0A90CF1A5A4C5DB02D56ECC4C5BF34007208D5B887185865")
    let k = Data.random(32), iv = Data.random(12), aad = Data("hichain_iso_exchange".utf8)
    let g = try? HWCrypto.gcmEncrypt(Data("challenge".utf8), key: k, iv: iv, aad: aad)
    check("GCM with AAD", g.flatMap { try? HWCrypto.gcmDecrypt($0, key: k, iv: iv, aad: aad) } == Data("challenge".utf8))

    // Auth digests are deterministic and 64 bytes.
    params.authVersion = 3; params.authMode = 0
    let d = try? params.digestChallenge(key: nil, nonce: Data(count: 32))
    check("Challenge digest shape", d?.count == 64 && d == (try? params.digestChallenge(key: nil, nonce: Data(count: 32))))
    check("Bonding wrap key", params.bondingWrapKey(mac: "A1:B2:C3:D4:E5:F6").count == 16)

    let sample = WatchSession.parseStepData(Data([0x4E, 0x00, 0x64, 0x00, 0x05, 0x00, 0x46, 0x48]), time: Date())
    check("Step sample parse", sample?.steps == 100 && sample?.calories == 5 && sample?.distance == 70 && sample?.heartRate == 72)

    // HiChain PAKE known-answer vectors (from the Gadgetbridge test suite).
    let h2c = [("0000000000000000000000000000000000000000000000000000000000000001", "8488ac5e043ea853cd14e1a0d9b13abf534298f96509d669b0ea87cbf09bb673"),
               ("0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20", "4e4c39ac31d3b3b16617427847178670e6afce5430eaa6aa41166cd7b1552525"),
               ("deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef00", "281f4575bc3210b5e6031561b1dfdacfadd91220fad52dab911c99e7e8e92d56"),
               ("fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0", "39cefaa8000c28b1501cee3f00eb5b997e897979a0c854ff5924f32de8103a7e"),
               ("abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789", "d3e239d7180ca04349edbd3751eca41fd3c2856bc64319cd5d9649764651a87d")]
    check("PAKE hash-to-curve (5 vectors)", h2c.allSatisfy { Pake.lowerHex(Pake.hashToCurve(Data(hex: $0.0))) == $0.1 })
    let xs = try? Pake.x25519(Data(hex: "a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4"),
                              Data(hex: "e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c"))
    check("X25519 RFC 7748", xs.map(Pake.lowerHex) == "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552")
    check("PAKE PIN", Pake.derivePin(Data(hex: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789")) == "ABCDEF012345")
    let seedA = Data(hex: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
    let seedB = Data(hex: "a1b2c3d4e5f60718293a4b5c6d7e8f900f1e2d3c4b5a69788796a5b4c3d2e1f0")
    let edA = try? Curve25519.Signing.PrivateKey(rawRepresentation: seedA)
    check("Ed25519 public key RFC 8032", edA.map { Pake.lowerHex($0.publicKey.rawRepresentation) } == "03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8")
    let msg = Data(hex: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
    let refSig = Data(hex: "3771fe931eacab89e3f74565a75c44ee25722c0c0f5359b01c48f35d419c6940f4966019fad4f4db18ca85e6724062735722465dea3450d758a916c8f1c2130f")
    check("Ed25519 verifies reference signature", edA.map { $0.publicKey.isValidSignature(refSig, for: msg) } == true)
    let ourSig = try? edA?.signature(for: msg)
    check("Ed25519 own signature verifies", ourSig.map { edA!.publicKey.isValidSignature($0, for: msg) } == true)
    var conv = true
    for seed in [seedA, seedB] {
        let k = try! Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        let fromPriv = try? Pake.x25519Base(Pake.ed25519PrivateToX25519(seed))
        if fromPriv != Pake.ed25519PublicToX25519(k.publicKey.rawRepresentation) { conv = false }
    }
    check("Ed25519 to X25519 conversion", conv)
    let pubA = edA!.publicKey.rawRepresentation, pubB = try! Curve25519.Signing.PrivateKey(rawRepresentation: seedB).publicKey.rawRepresentation
    let pskA = try? Pake.x25519(Pake.ed25519PrivateToX25519(seedA), Pake.ed25519PublicToX25519(pubB))
    let pskB = try? Pake.x25519(Pake.ed25519PrivateToX25519(seedB), Pake.ed25519PublicToX25519(pubA))
    check("Reconnect PSK agreement", pskA != nil && pskA == pskB && pskA != Data(count: 32))
    check("Model lookup", ModelInfo.match("HUAWEI WATCH FIT-5F9")?.id == "huaweiwatchfit" && ModelInfo.match("HUAWEI WATCH FIT 2-AB1")?.id == "huaweiwatchfit2"
        && ModelInfo.match("HONOR Watch 5-1A2")?.pake == true && ModelInfo.match("HONOR Band 9-77")?.honorUUIDs == true)

    // GPS file: start at 52.0 N, 13.0 E, then 3 points each 100 m north, 1 s apart; the last flagged as a pause.
    var gps = Data(count: 0x20)
    gps.append(0x00)
    withUnsafeBytes(of: Int32(1_700_000_000).littleEndian) { gps.append(contentsOf: $0) }
    withUnsafeBytes(of: (13.0).bitPattern.littleEndian) { gps.append(contentsOf: $0) }
    withUnsafeBytes(of: (52.0).bitPattern.littleEndian) { gps.append(contentsOf: $0) }
    gps.append(Data(count: 62 - gps.count))
    for k in 0 ..< 4 {
        withUnsafeBytes(of: Int16(1).littleEndian) { gps.append(contentsOf: $0) }
        gps.append(Data(count: 2))
        withUnsafeBytes(of: Float(0).bitPattern.littleEndian) { gps.append(contentsOf: $0) }
        withUnsafeBytes(of: Float(100).bitPattern.littleEndian) { gps.append(contentsOf: $0) }
        gps.append(contentsOf: [0, 0, k == 2 ? 1 : 0])
    }
    let pts = parseHuaweiGPS(gps)
    check("GPS track decode", pts.count == 3 && abs(pts[0].lon - 13.0) < 1e-5 && pts[1].lat > pts[0].lat && pts[2].pause
          && abs(haversine(pts[0], pts[1]) - 100) < 2 && pts[2].t.timeIntervalSince1970 == 1_700_000_003)
    let wsHeader = Data([0, 1, 0, 0, 0x65, 0x53, 0xF1, 0x00, 1, 0, 2, 4, 0, 0x05])
    let ws = parseWorkoutSamples(TLV().with(4, wsHeader).with(5, Data([120, 150, 0, 0, 130, 160, 0, 0])))
    check("Workout sample decode", ws.count == 2 && ws[0].hr == 120 && ws[0].cadence == 150 && ws[1].hr == 130)

    print(ok ? "All self-tests passed." : "Some self-tests FAILED.")
    return ok
}
