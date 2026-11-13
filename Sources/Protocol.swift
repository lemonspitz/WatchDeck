// Huawei Link Protocol v2: TLV encoding, packet framing and crypto.
// Packet formats follow the open-source Gadgetbridge project's documentation of the protocol.
import Foundation
import CryptoKit
import CommonCrypto

// MARK: - Byte helpers

extension Data {
    var hex: String { map { String(format: "%02X", $0) }.joined() }

    init(hex: String) {
        var out = Data()
        var chars = Array(hex.filter { $0.isHexDigit })
        if chars.count % 2 == 1 { chars.insert("0", at: 0) }
        var i = 0
        while i < chars.count {
            out.append(UInt8(String(chars[i ... i + 1]), radix: 16) ?? 0)
            i += 2
        }
        self = out
    }

    static func random(_ n: Int) -> Data {
        var d = Data(count: n)
        d.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, n, $0.baseAddress!) }
        return d
    }

    static func be16(_ v: Int) -> Data { Data([UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]) }
    static func be32(_ v: Int) -> Data {
        Data([UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
    }
    static func be64(_ v: Int64) -> Data {
        Data((0 ..< 8).map { UInt8(truncatingIfNeeded: v >> (56 - 8 * Int64($0))) })
    }

    /// Big-endian unsigned integer from up to 8 bytes.
    var uint: Int { reduce(0) { ($0 << 8) | Int($1) } }
}

// MARK: - TLV

struct TLV {
    var items: [(tag: UInt8, value: Data)] = []

    init() {}

    init(_ data: Data) throws {
        let b = [UInt8](data)
        var i = 0
        while i < b.count {
            let tag = b[i]; i += 1
            if i == b.count, tag == 0 { break }
            var size = 0
            while true {
                guard i < b.count else { throw WatchError.protocolError("TLV truncated") }
                let c = b[i]; i += 1
                size = (size << 7) | Int(c & 0x7F)
                if c & 0x80 == 0 { break }
            }
            guard size <= b.count - i else { throw WatchError.protocolError("TLV length overrun") }
            items.append((tag, Data(b[i ..< i + size])))
            i += size
        }
    }

    static func varInt(_ n: Int) -> Data {
        var groups: [UInt8] = [UInt8(n & 0x7F)]
        var v = n >> 7
        while v > 0 { groups.insert(UInt8(v & 0x7F) | 0x80, at: 0); v >>= 7 }
        return Data(groups)
    }

    var data: Data {
        var out = Data()
        for (tag, value) in items {
            out.append(tag)
            out.append(TLV.varInt(value.count))
            out.append(value)
        }
        return out
    }

    @discardableResult mutating func put(_ tag: Int) -> TLV { items.append((UInt8(tag), Data())); return self }
    @discardableResult mutating func put(_ tag: Int, _ v: Data) -> TLV { items.append((UInt8(tag), v)); return self }
    @discardableResult mutating func put(_ tag: Int, byte v: Int) -> TLV { put(tag, Data([UInt8(truncatingIfNeeded: v)])) }
    @discardableResult mutating func put(_ tag: Int, _ v: Bool) -> TLV { put(tag, Data([v ? 1 : 0])) }
    @discardableResult mutating func put(_ tag: Int, short v: Int) -> TLV { put(tag, Data.be16(v)) }
    @discardableResult mutating func put(_ tag: Int, int v: Int) -> TLV { put(tag, Data.be32(v)) }
    @discardableResult mutating func put(_ tag: Int, _ v: String) -> TLV { put(tag, Data(v.utf8)) }
    @discardableResult mutating func put(_ tag: Int, _ v: TLV) -> TLV { put(tag, v.data) }

    // Builder-style (non-mutating) variants.
    func with(_ tag: Int) -> TLV { var t = self; t.put(tag); return t }
    func with(_ tag: Int, _ v: Data) -> TLV { var t = self; t.put(tag, v); return t }
    func with(_ tag: Int, byte v: Int) -> TLV { var t = self; t.put(tag, byte: v); return t }
    func with(_ tag: Int, _ v: Bool) -> TLV { var t = self; t.put(tag, v); return t }
    func with(_ tag: Int, short v: Int) -> TLV { var t = self; t.put(tag, short: v); return t }
    func with(_ tag: Int, int v: Int) -> TLV { var t = self; t.put(tag, int: v); return t }
    func with(_ tag: Int, _ v: String) -> TLV { var t = self; t.put(tag, v); return t }
    func with(_ tag: Int, _ v: TLV) -> TLV { var t = self; t.put(tag, v); return t }

    func bytes(_ tag: Int) -> Data? { items.first { $0.tag == UInt8(tag) }?.value }
    func has(_ tag: Int) -> Bool { bytes(tag) != nil }
    func int(_ tag: Int) -> Int? { bytes(tag).flatMap { $0.isEmpty || $0.count > 8 ? nil : $0.uint } }
    func string(_ tag: Int) -> String? { bytes(tag).map { String(decoding: $0, as: UTF8.self) } }
    func object(_ tag: Int) -> TLV? { bytes(tag).flatMap { try? TLV($0) } }
    func objects(_ tag: Int) -> [TLV] { items.filter { $0.tag == UInt8(tag) }.compactMap { try? TLV($0.value) } }

    var description: String {
        items.map { String(format: "%02X:", $0.tag) + $0.value.hex }.joined(separator: " ")
    }
}

// MARK: - Errors

enum WatchError: LocalizedError {
    case protocolError(String)
    case timeout(String)
    case notConnected
    case auth(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .protocolError(let s): return "Protocol error: \(s)"
        case .timeout(let s): return "The watch did not answer (\(s))"
        case .notConnected: return "Not connected to a watch"
        case .auth(let s): return "Pairing failed: \(s)"
        case .unsupported(let s): return "Not supported: \(s)"
        }
    }
}

// MARK: - CRC16 (XMODEM, poly 0x1021, init 0)

func crc16(_ data: Data) -> UInt16 {
    var crc: UInt16 = 0
    for b in data {
        crc = (crc >> 8) | (crc << 8)
        crc ^= UInt16(b)
        crc ^= (crc & 0xFF) >> 4
        crc ^= crc << 12
        crc ^= (crc & 0xFF) << 5
    }
    return crc
}

// MARK: - Crypto

enum HWCrypto {
    static let secretKey1v1 = Data(hex: "6F756A796D777134636C76393337 3879")
    static let secretKey2v1 = Data(hex: "6231306A676664397937767375646139")
    static let secretKey1v23 = Data(hex: "555386FC632007AA86493522B86AE25C")
    static let secretKey2v23 = Data(hex: "33079BC57A886D3CF56137096F228000")
    static let digestSecretV1 = Data(hex: "70FB6C24035FDB552F38898AEEDE3F69")
    static let digestSecretV2 = Data(hex: "93ACDEF76ACB09857DBFE5261AABCD78")
    static let digestSecretV3 = Data(hex: "9C2763A9CCE134766DE3FF6118200553")

    static func sha256(_ d: Data) -> Data { Data(SHA256.hash(data: d)) }

    static func hmac(key: Data, _ message: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    }

    static func hkdf(key: Data, salt: Data, info: Data, length: Int) -> Data {
        let k = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: key), salt: salt, info: info, outputByteCount: length)
        return k.withUnsafeBytes { Data($0) }
    }

    static func pbkdf2(password: String, salt: Data, rounds: Int, length: Int) -> Data {
        var out = Data(count: length)
        let pw = Array(password.utf8CString.dropLast())
        _ = out.withUnsafeMutableBytes { o in
            salt.withUnsafeBytes { s in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw, pw.count,
                                     s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(rounds),
                                     o.bindMemory(to: UInt8.self).baseAddress, length)
            }
        }
        return out
    }

    static func aesCBC(_ input: Data, key: Data, iv: Data, encrypt: Bool) throws -> Data {
        var out = Data(count: input.count + kCCBlockSizeAES128)
        var moved = 0
        let status = out.withUnsafeMutableBytes { o in
            input.withUnsafeBytes { i in
                key.withUnsafeBytes { k in
                    iv.withUnsafeBytes { v in
                        CCCrypt(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding), k.baseAddress, key.count, v.baseAddress,
                                i.baseAddress, input.count, o.baseAddress, o.count, &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw WatchError.protocolError("AES-CBC failed (\(status))") }
        return out.prefix(moved)
    }

    /// AES-GCM where the 16-byte tag is appended to the ciphertext.
    static func gcmEncrypt(_ input: Data, key: Data, iv: Data, aad: Data? = nil) throws -> Data {
        let nonce = try AES.GCM.Nonce(data: iv)
        let box = try aad.map { try AES.GCM.seal(input, using: SymmetricKey(data: key), nonce: nonce, authenticating: $0) }
            ?? AES.GCM.seal(input, using: SymmetricKey(data: key), nonce: nonce)
        return box.ciphertext + box.tag
    }

    static func gcmDecrypt(_ input: Data, key: Data, iv: Data, aad: Data? = nil) throws -> Data {
        guard input.count >= 16 else { throw WatchError.protocolError("GCM data too short") }
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: input.dropLast(16), tag: input.suffix(16))
        if let aad { return try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: aad) }
        return try AES.GCM.open(box, using: SymmetricKey(data: key))
    }

    static func crypt(_ input: Data, key: Data, iv: Data, gcm: Bool, encrypt: Bool) throws -> Data {
        if gcm { return encrypt ? try gcmEncrypt(input, key: key, iv: iv) : try gcmDecrypt(input, key: key, iv: iv) }
        return try aesCBC(input, key: key, iv: iv, encrypt: encrypt)
    }
}

// MARK: - Link parameters shared by all packets of one connection

final class LinkParams {
    var authVersion = 0
    var deviceSupportType = 0
    var authAlgo = 0
    var encryptMethod = 0
    var authMode = 0
    var sliceSize = 0xF4
    var mtu = 65535
    var secretKey: Data?
    var firstKey: Data?
    var pinCode: Data?
    var encryptionCounter: UInt32 = 0
    var serverNonce = Data(count: 16)
    /// Some models (several Honor watches, TalkBand) expect commands unencrypted.
    var crypted = true

    var useGCM: Bool { encryptMethod == 1 || deviceSupportType == 4 }

    var digestSecret: Data {
        switch authVersion {
        case 1, 4: return HWCrypto.digestSecretV1
        case 2: return HWCrypto.digestSecretV2
        default: return HWCrypto.digestSecretV3
        }
    }

    func nextIV() -> Data {
        if deviceSupportType == 4 { return Data.random(16) }
        encryptionCounter = encryptionCounter == 0xFFFF_FFFF ? 1 : encryptionCounter + 1
        return Data.random(12) + Data.be32(Int(encryptionCounter))
    }

    func encrypt(_ payload: Data) throws -> TLV {
        guard let key = secretKey else { throw WatchError.auth("no session key") }
        let iv = nextIV()
        let cipher = try HWCrypto.crypt(payload, key: key, iv: iv, gcm: useGCM, encrypt: true)
        return TLV().with(0x7C, byte: 1).with(0x7D, iv).with(0x7E, cipher)
    }

    func decrypt(_ tlv: TLV) throws -> Data {
        guard let key = secretKey, let iv = tlv.bytes(0x7D), let cipher = tlv.bytes(0x7E) else {
            throw WatchError.protocolError("cannot decrypt")
        }
        return try HWCrypto.crypt(cipher, key: key, iv: iv, gcm: useGCM, encrypt: false)
    }

    // --- Authentication digests ---

    private func computeDigest(_ message: Data, nonce: Data) -> Data {
        let step1 = HWCrypto.hmac(key: digestSecret + message, nonce)
        return HWCrypto.hmac(key: step1, nonce) + step1
    }

    private func computeDigestHiChainLite(_ message: Data, key: Data, nonce: Data) -> Data {
        let hashKey = HWCrypto.sha256(Data(key.hex.utf8))
        let secret = Data(zip(digestSecret, hashKey).map { $0 ^ $1 })
        let msg = secret + message
        let step1 = authAlgo == 1
            ? HWCrypto.pbkdf2(password: msg.hex, salt: nonce, rounds: 1000, length: 32)
            : HWCrypto.hmac(key: msg, nonce)
        return HWCrypto.hmac(key: step1, nonce) + step1
    }

    private func digest(_ message: Data, key: Data?, nonce: Data) throws -> Data {
        if authMode == 2 {
            guard let key else { throw WatchError.auth("missing key") }
            if authVersion == 2 {
                let k = key + message
                return HWCrypto.hmac(key: k, nonce) + k
            }
            return computeDigestHiChainLite(message, key: key, nonce: nonce)
        }
        return computeDigest(message, nonce: nonce)
    }

    func digestChallenge(key: Data?, nonce: Data) throws -> Data {
        let msg = authMode != 2 && authVersion == 4 ? Data([0x04, 0x00]) : Data([0x01, 0x00])
        return try digest(msg, key: key, nonce: nonce)
    }

    func digestResponse(key: Data?, nonce: Data) throws -> Data {
        try digest(Data([0x01, 0x10]), key: key, nonce: nonce)
    }

    /// Key used to wrap the bonding key in "normal" mode, derived from the watch's MAC address.
    func bondingWrapKey(mac: String) -> Data {
        let k1 = authVersion == 1 ? HWCrypto.secretKey1v1 : HWCrypto.secretKey1v23
        let k2 = authVersion == 1 ? HWCrypto.secretKey2v1 : HWCrypto.secretKey2v23
        let macKey = Data((mac.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").uppercased() + "0000").utf8)
        let mixed = Data((0 ..< 16).map { UInt8(truncatingIfNeeded: (Int(k1[$0]) << 4) ^ Int(k2[$0])) })
        let mixedHash = HWCrypto.sha256(mixed)
        let final = Data((0 ..< 16).map { (mixedHash[$0] >> 6) ^ macKey[$0] })
        return HWCrypto.sha256(final).prefix(16)
    }
}

// MARK: - Packets

struct Packet {
    var service: UInt8
    var command: UInt8
    var tlv = TLV()
    /// Raw payload after service/command bytes (used by file-transfer commands that are not TLV).
    var raw = Data()

    var id: String { String(format: "%02X/%02X", service, command) }

    static func frameUnsliced(service: UInt8, command: UInt8, body: Data) -> [Data] {
        var buf = Data([0x5A])
        buf.append(Data.be16(body.count + 3))
        buf.append(0x00)
        buf.append(service)
        buf.append(command)
        buf.append(body)
        buf.append(Data.be16(Int(crc16(buf))))
        return [buf]
    }

    static func frameSliced(service: UInt8, command: UInt8, body: Data, sliceSize: Int) -> [Data] {
        let header = 5, footer = 2
        let maxBody = sliceSize - header - footer
        let count = Int((Double(body.count + 2) / Double(maxBody)).rounded(.up))
        if count <= 1 { return frameUnsliced(service: service, command: command, body: body) }
        var out: [Data] = []
        var pos = 0
        var slice: UInt8 = 1
        for i in 0 ..< count {
            let remaining = body.count - pos
            let packetSize = min(sliceSize, remaining + header + footer)
            var content = packetSize - header - footer
            if i == count - 1 { slice = 3 }
            var p = Data([0x5A])
            p.append(Data.be16(packetSize - header))
            p.append(slice)
            p.append(UInt8(truncatingIfNeeded: i))
            if slice == 1 {
                p.append(service)
                p.append(command)
                slice = 2
                content -= 2
            }
            content = max(0, min(content, remaining))
            p.append(body.subdata(in: body.startIndex + pos ..< body.startIndex + pos + content))
            pos += content
            // Length field covers everything after it except the CRC.
            let len = p.count - 3
            p.replaceSubrange(1 ..< 3, with: Data.be16(len))
            p.append(Data.be16(Int(crc16(p))))
            out.append(p)
        }
        return out
    }
}

/// Reassembles the byte stream from the watch into complete packets.
final class PacketAssembler {
    private var buffer = Data()
    private var sliced = Data()

    func reset() { buffer.removeAll(); sliced.removeAll() }

    func feed(_ data: Data, params: LinkParams) -> [Packet] {
        buffer.append(data)
        var out: [Packet] = []
        while true {
            // Resynchronise on the magic byte.
            while let first = buffer.first, first != 0x5A { buffer.removeFirst() }
            guard buffer.count >= 5 else { break }
            let b = [UInt8](buffer.prefix(3))
            let len = Int(b[1]) << 8 | Int(b[2])
            let total = len + 5
            guard buffer.count >= total else { break }
            let frame = Data(buffer.prefix(total))
            buffer.removeFirst(total)
            let f = [UInt8](frame)
            let crc = UInt16(f[total - 2]) << 8 | UInt16(f[total - 1])
            guard crc16(frame.prefix(total - 2)) == crc else { continue }
            let sliceFlag = f[3]
            var payload: Data
            if (1 ... 3).contains(sliceFlag) {
                sliced.append(Data(f[5 ..< total - 2]))
                if sliceFlag != 3 { continue }
                payload = sliced
                sliced = Data()
            } else {
                payload = Data(f[4 ..< total - 2])
            }
            guard payload.count >= 2 else { continue }
            let p = [UInt8](payload)
            var packet = Packet(service: p[0], command: p[1])
            packet.raw = Data(p[2...])
            let rawOnly = (p[0] == 0x0A && p[1] == 0x05) || (p[0] == 0x28 && p[1] == 0x06)
                || (p[0] == 0x2C && p[1] == 0x05) || (p[0] == 0x1C && p[1] == 0x05)
            if !rawOnly, var tlv = try? TLV(packet.raw) {
                if tlv.int(0x7C) == 1, let plain = try? params.decrypt(tlv), let inner = try? TLV(plain) {
                    tlv = inner
                    packet.raw = plain
                }
                packet.tlv = tlv
            }
            out.append(packet)
        }
        return out
    }
}
