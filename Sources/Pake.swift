// HiChain PAKE (EC-SPEKE over Curve25519) used by Honor Watch 5 / 5 Pro / 6.
// Follows the OpenHarmony device_auth flow as documented by the Gadgetbridge project.
import Foundation
import CryptoKit

// MARK: - Minimal unsigned big integer (only what Curve25519 field arithmetic needs)

struct BigUInt: Equatable, Comparable {
    private(set) var limbs: [UInt32]      // little-endian, no trailing zero limbs

    init(_ v: UInt64 = 0) { limbs = [UInt32(truncatingIfNeeded: v), UInt32(truncatingIfNeeded: v >> 32)]; normalize() }
    init(limbs: [UInt32]) { self.limbs = limbs; normalize() }

    /// Big-endian bytes.
    init(be: Data) {
        var l: [UInt32] = []
        let b = [UInt8](be)
        var i = b.count
        while i > 0 {
            var w: UInt32 = 0
            for k in 0 ..< 4 where i - 1 - k >= 0 { w |= UInt32(b[i - 1 - k]) << (8 * UInt32(k)) }
            l.append(w); i -= 4
        }
        self.init(limbs: l)
    }
    init(le: Data) { self.init(be: Data(le.reversed())) }

    private mutating func normalize() { while let last = limbs.last, last == 0 { limbs.removeLast() } }

    var isZero: Bool { limbs.isEmpty }
    var bitWidth: Int { limbs.isEmpty ? 0 : (limbs.count - 1) * 32 + (32 - limbs.last!.leadingZeroBitCount) }
    func bit(_ i: Int) -> Bool { i / 32 < limbs.count && (limbs[i / 32] >> UInt32(i % 32)) & 1 == 1 }

    /// Minimal big-endian bytes (empty for zero).
    var beMinimal: Data {
        var out = Data()
        for w in limbs.reversed() { out.append(contentsOf: [UInt8(w >> 24), UInt8(w >> 16 & 255), UInt8(w >> 8 & 255), UInt8(w & 255)]) }
        while let f = out.first, f == 0 { out.removeFirst() }
        return out
    }
    func be(_ len: Int) -> Data { let m = beMinimal; return Data(repeating: 0, count: max(0, len - m.count)) + m.suffix(len) }
    func le(_ len: Int) -> Data { Data(be(len).reversed()) }

    static func < (a: BigUInt, b: BigUInt) -> Bool {
        if a.limbs.count != b.limbs.count { return a.limbs.count < b.limbs.count }
        for i in stride(from: a.limbs.count - 1, through: 0, by: -1) where a.limbs[i] != b.limbs[i] { return a.limbs[i] < b.limbs[i] }
        return false
    }

    static func + (a: BigUInt, b: BigUInt) -> BigUInt {
        var r = [UInt32](repeating: 0, count: max(a.limbs.count, b.limbs.count) + 1)
        var carry: UInt64 = 0
        for i in 0 ..< r.count - 1 {
            let s = UInt64(i < a.limbs.count ? a.limbs[i] : 0) + UInt64(i < b.limbs.count ? b.limbs[i] : 0) + carry
            r[i] = UInt32(truncatingIfNeeded: s); carry = s >> 32
        }
        r[r.count - 1] = UInt32(carry)
        return BigUInt(limbs: r)
    }

    /// a - b, requires a >= b.
    static func - (a: BigUInt, b: BigUInt) -> BigUInt {
        var r = a.limbs
        var borrow: Int64 = 0
        for i in 0 ..< r.count {
            var d = Int64(r[i]) - Int64(i < b.limbs.count ? b.limbs[i] : 0) - borrow
            if d < 0 { d += 1 << 32; borrow = 1 } else { borrow = 0 }
            r[i] = UInt32(d)
        }
        return BigUInt(limbs: r)
    }

    static func * (a: BigUInt, b: BigUInt) -> BigUInt {
        if a.isZero || b.isZero { return BigUInt() }
        var r = [UInt32](repeating: 0, count: a.limbs.count + b.limbs.count)
        for i in 0 ..< a.limbs.count {
            var carry: UInt64 = 0
            let ai = UInt64(a.limbs[i])
            for j in 0 ..< b.limbs.count {
                let t = ai * UInt64(b.limbs[j]) + UInt64(r[i + j]) + carry
                r[i + j] = UInt32(truncatingIfNeeded: t); carry = t >> 32
            }
            r[i + b.limbs.count] = UInt32(carry)
        }
        return BigUInt(limbs: r)
    }

    func shiftedLeft1(_ low: Bool) -> BigUInt {
        var r = limbs + [0]
        var carry: UInt32 = low ? 1 : 0
        for i in 0 ..< r.count { let n = r[i] >> 31; r[i] = r[i] << 1 | carry; carry = n }
        return BigUInt(limbs: r)
    }

    /// Bit-by-bit long division remainder (plenty fast for 512-bit operands).
    static func % (a: BigUInt, m: BigUInt) -> BigUInt {
        if a < m { return a }
        var r = BigUInt()
        for i in stride(from: a.bitWidth - 1, through: 0, by: -1) {
            r = r.shiftedLeft1(a.bit(i))
            if !(r < m) { r = r - m }
        }
        return r
    }

    static func modPow(_ base: BigUInt, _ exp: BigUInt, _ m: BigUInt) -> BigUInt {
        var result = BigUInt(1) % m
        var b = base % m
        for i in 0 ..< exp.bitWidth {
            if exp.bit(i) { result = (result * b) % m }
            b = (b * b) % m
        }
        return result
    }
}

// MARK: - Curve25519 field (p = 2^255 - 19)

enum F25519 {
    static let p = BigUInt(be: Data(hex: "7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFED"))
    static let A = BigUInt(486662)
    static func add(_ a: BigUInt, _ b: BigUInt) -> BigUInt { (a + b) % p }
    static func sub(_ a: BigUInt, _ b: BigUInt) -> BigUInt { ((a % p) + p - (b % p)) % p }
    static func mul(_ a: BigUInt, _ b: BigUInt) -> BigUInt { (a * b) % p }
    static func neg(_ a: BigUInt) -> BigUInt { sub(BigUInt(), a) }
    static func inv(_ a: BigUInt) -> BigUInt { BigUInt.modPow(a, p - BigUInt(2), p) }
}

enum Pake {
    static let baseInfo = Data("hichain_speke_base_info".utf8)
    static let sessionKeyInfo = Data("hichain_speke_sessionkey_info".utf8)
    static let tmpAuthKeyInfo = Data("hichain_tmp_auth_enc_key".utf8)
    static let exchangeRequestAAD = Data("hichain_exchange_request".utf8)
    static let exchangeResponseAAD = Data("hichain_exchange_response".utf8)

    /// X25519 with an arbitrary base point (CryptoKit clamps the scalar as RFC 7748 requires).
    static func x25519(_ scalar: Data, _ u: Data) throws -> Data {
        var uu = [UInt8](u) + [UInt8](repeating: 0, count: max(0, 32 - u.count))
        uu = Array(uu.prefix(32)); uu[31] &= 0x7F
        let priv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: scalar.prefix(32))
        let pub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: Data(uu))
        return try priv.sharedSecretFromKeyAgreement(with: pub).withUnsafeBytes { Data($0) }
    }

    static func x25519Base(_ scalar: Data) throws -> Data {
        try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: scalar).publicKey.rawRepresentation
    }

    /// Elligator2 map used by OpenHarmony's hash-to-point (byte layout reproduced exactly).
    static func hashToCurve(_ secret: Data) -> Data {
        var h = [UInt8](secret.prefix(32)) + [UInt8](repeating: 0, count: max(0, 32 - secret.count))
        h[31] &= 0x3F
        let r = BigUInt(le: Data(h))
        let denom = F25519.add(BigUInt(1), F25519.mul(BigUInt(2), F25519.mul(r, r)))
        let b = F25519.mul(F25519.neg(F25519.A), F25519.inv(denom))
        let b2 = F25519.mul(b, b), b3 = F25519.mul(b2, b)
        let a = F25519.add(F25519.add(b3, F25519.mul(F25519.A, b2)), b)
        let legendre = BigUInt.modPow(a, BigUInt(limbs: (F25519.p - BigUInt(1)).limbs).halved, F25519.p)
        let x = (a.isZero || legendre == BigUInt(1)) ? b : F25519.sub(F25519.neg(b), F25519.A)
        let be = x.beMinimal
        var buf = [UInt8](repeating: 0, count: 32)
        for (i, v) in be.prefix(32).enumerated() { buf[i] = v }
        return Data(buf.reversed())
    }

    static func ed25519PublicToX25519(_ pub: Data) -> Data {
        var c = [UInt8](pub.prefix(32)); c[31] &= 0x7F
        let y = BigUInt(le: Data(c))
        let u = F25519.mul(F25519.add(BigUInt(1), y), F25519.inv(F25519.sub(BigUInt(1), y)))
        return u.le(32)
    }

    static func ed25519PrivateToX25519(_ seed: Data) -> Data {
        var a = [UInt8](Data(SHA512.hash(data: seed)).prefix(32))
        a[0] &= 0xF8; a[31] &= 0x7F; a[31] |= 0x40
        return Data(a)
    }

    static func derivePin(_ shared: Data) -> String { shared.prefix(6).map { String(format: "%02X", $0) }.joined() }

    static func lowerHex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

    /// AES-GCM with the 12-byte IV prepended to ciphertext||tag.
    static func seal(_ plain: Data, key: Data, aad: Data) throws -> Data {
        let iv = Data.random(12)
        return iv + (try HWCrypto.gcmEncrypt(plain, key: key, iv: iv, aad: aad))
    }

    static func open(_ data: Data, key: Data, aad: Data) throws -> Data {
        guard data.count > 12 else { throw WatchError.auth("PAKE payload too short") }
        return try HWCrypto.gcmDecrypt(data.dropFirst(12), key: key, iv: data.prefix(12), aad: aad)
    }

    /// SPEKE key agreement state for one bind or reconnect run.
    struct Speke {
        var selfChallenge = Data.random(16)
        var peerChallenge = Data()
        var selfPublic = Data()
        var sessionKey = Data()
        var kcfKey = Data()

        /// From the PIN and the watch's challenge, salt and ephemeral key: our public value, session and proof keys.
        init(pinHex: String, peerChallenge: Data, salt: Data, peerEpk: Data) throws {
            self.peerChallenge = peerChallenge
            let passwordKey = HWCrypto.hkdf(key: Data(pinHex.utf8), salt: salt, info: Pake.baseInfo, length: 32)
            let base = Pake.hashToCurve(passwordKey)
            let priv = Data.random(32)
            selfPublic = try Pake.x25519(priv, base)
            let shared = try Pake.x25519(priv, peerEpk)
            let tmp = HWCrypto.hkdf(key: shared, salt: salt, info: Pake.sessionKeyInfo, length: 48)
            sessionKey = tmp.prefix(16)
            kcfKey = tmp.subdata(in: 16 ..< 48)
        }

        var proof: Data { HWCrypto.hmac(key: kcfKey, selfChallenge + peerChallenge) }
        func verifyServer(_ kcf: Data) -> Bool { HWCrypto.hmac(key: kcfKey, peerChallenge + selfChallenge) == kcf }
    }
}

extension BigUInt {
    var halved: BigUInt {
        var r = limbs
        var carry: UInt32 = 0
        for i in stride(from: r.count - 1, through: 0, by: -1) { let n = r[i] & 1; r[i] = r[i] >> 1 | carry << 31; carry = n }
        return BigUInt(limbs: r)
    }
}

/// Tiny ordered JSON writer: the watch is given keys in the same order the official app uses.
func orderedJSON(_ pairs: [(String, Any)]) -> String {
    func enc(_ v: Any) -> String {
        switch v {
        case let s as String:
            return "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        case let b as Bool: return b ? "true" : "false"
        case let i as Int: return String(i)
        case let o as [(String, Any)]: return orderedJSON(o)
        default: return "null"
        }
    }
    return "{" + pairs.map { "\"\($0.0)\":" + enc($0.1) }.joined(separator: ",") + "}"
}
