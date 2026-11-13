// Every Huawei and Honor wearable the app knows, matched by the Bluetooth name the watch advertises.
// The table is generated from the open-source Gadgetbridge device list (name prefix, link type and protocol flags).
import Foundation

enum LinkKind: String { case ble, aw, br }

struct ModelInfo {
    var prefix: String          // lower-case advertised name prefix, e.g. "huawei watch fit-"
    var id: String
    var link: LinkKind          // ble / aw: Bluetooth LE; br: classic Bluetooth
    var honorUUIDs: Bool        // newer Honor bands use their own GATT service
    var pake: Bool              // Honor Watch 5 / 5 Pro / 6 pair with HiChain PAKE
    var encrypted: Bool         // some models expect unencrypted commands

    var usesLE: Bool { link != .br }

    /// "huawei watch fit 2-" -> "HUAWEI WATCH FIT 2"
    var displayName: String { prefix.trimmingCharacters(in: CharacterSet(charactersIn: "- ")).uppercased() }

    static func match(_ name: String) -> ModelInfo? {
        let n = name.lowercased()
        return knownModels.filter { n.hasPrefix($0.prefix) }.max { $0.prefix.count < $1.prefix.count }
    }
}

/// Screen sizes Huawei and Honor use for watch faces (code -> width x height).
struct ScreenSpec {
    var code: String
    var width: Int
    var height: Int
    var round: Bool
    var label: String { "\(width) × \(height)" }
}

let screenSpecs: [ScreenSpec] = [
    ScreenSpec(code: "HWHD01", width: 390, height: 390, round: true),
    ScreenSpec(code: "HWHD02", width: 454, height: 454, round: true),
    ScreenSpec(code: "HWHD03", width: 120, height: 240, round: false),
    ScreenSpec(code: "HWHD04", width: 80, height: 160, round: false),
    ScreenSpec(code: "HWHD05", width: 188, height: 460, round: false),
    ScreenSpec(code: "HWHD06", width: 280, height: 456, round: false),
    ScreenSpec(code: "HWHD07", width: 194, height: 368, round: false),
    ScreenSpec(code: "HWHD08", width: 320, height: 320, round: true),
    ScreenSpec(code: "HWHD09", width: 466, height: 466, round: true),
    ScreenSpec(code: "HWHD10", width: 320, height: 360, round: false),
    ScreenSpec(code: "HWHD11", width: 336, height: 480, round: false),
    ScreenSpec(code: "HWHD12", width: 240, height: 240, round: true),
    ScreenSpec(code: "HWHD13", width: 408, height: 480, round: false),
    ScreenSpec(code: "HWHD14", width: 286, height: 482, round: false),
    ScreenSpec(code: "HNHD01", width: 466, height: 466, round: true),
    ScreenSpec(code: "HNHD02", width: 194, height: 368, round: false),
    ScreenSpec(code: "HNHD03", width: 390, height: 450, round: false),
    ScreenSpec(code: "HNHD04", width: 454, height: 454, round: true),
    ScreenSpec(code: "HNHD05", width: 256, height: 402, round: false),
    ScreenSpec(code: "QXHD01", width: 256, height: 402, round: false),
    ScreenSpec(code: "QXHD02", width: 410, height: 502, round: false),
]

// Generated from Gadgetbridge's device list: 69 name patterns.
let knownModels: [ModelInfo] = [
    ModelInfo(prefix: "honor band 10-", id: "honorband10", link: .ble, honorUUIDs: true, pake: false, encrypted: true),
    ModelInfo(prefix: "honor band 3-", id: "honorband3", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "honor band 4-", id: "honorband4", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "honor band 5-", id: "honorband5", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "honor band 6-", id: "honorband6", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "honor band 7-", id: "honorband7", link: .ble, honorUUIDs: true, pake: false, encrypted: true),
    ModelInfo(prefix: "honor band 9-", id: "honorband9", link: .ble, honorUUIDs: true, pake: false, encrypted: true),
    ModelInfo(prefix: "honor Watch-", id: "honormagicwatch", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "honor magicwatch 2-", id: "honormagicwatch2", link: .br, honorUUIDs: false, pake: false, encrypted: false),
    ModelInfo(prefix: "honor watch 4-", id: "honorwatch4", link: .br, honorUUIDs: false, pake: false, encrypted: false),
    ModelInfo(prefix: "honor watch 4 pro-", id: "honorwatch4", link: .br, honorUUIDs: false, pake: false, encrypted: false),
    ModelInfo(prefix: "honor watch 5-", id: "honorwatch5", link: .br, honorUUIDs: false, pake: true, encrypted: false),
    ModelInfo(prefix: "honor watch 5 pro-", id: "honorwatch5pro", link: .br, honorUUIDs: false, pake: true, encrypted: false),
    ModelInfo(prefix: "honor watch 6-", id: "honorwatch6", link: .br, honorUUIDs: false, pake: true, encrypted: false),
    ModelInfo(prefix: "honor watch gs 3-", id: "honorwatchgs3", link: .br, honorUUIDs: false, pake: false, encrypted: false),
    ModelInfo(prefix: "honor watch gs pro-", id: "honorwatchgspro", link: .br, honorUUIDs: false, pake: false, encrypted: false),
    ModelInfo(prefix: "huawei band 10-", id: "huaweiband10", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei band 11-", id: "huaweiband11", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei band 11 pro-", id: "huaweiband11pro", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei band 2-", id: "huaweiband2pro", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei band 2 pro-", id: "huaweiband2pro", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei band 3-", id: "huaweiband3pro", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei band 3 pro-", id: "huaweiband3pro", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei band 4-", id: "huaweiband4pro", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei band 4 pro-", id: "huaweiband4pro", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei band 6-", id: "huaweiband6", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei band 7-", id: "huaweiband7", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei band 8-", id: "huaweiband8", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei band 9-", id: "huaweiband9", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei band a2-", id: "huaweibanda2", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei band 3e-", id: "huaweibandaw70", link: .aw, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei band 4e-", id: "huaweibandaw70", link: .aw, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei b6-", id: "huaweitalkbandb6", link: .br, honorUUIDs: false, pake: false, encrypted: false),
    ModelInfo(prefix: "huawei b7-", id: "huaweitalkbandb7", link: .br, honorUUIDs: false, pake: false, encrypted: false),
    ModelInfo(prefix: "huawei watch 3-", id: "huaweiwatch3", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch 3 pro-", id: "huaweiwatch3", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch 4-", id: "huaweiwatch4pro", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch 4 pro-", id: "huaweiwatch4pro", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch 5-", id: "huaweiwatch5", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch 6 pro-", id: "huaweiwatch6", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch 6-", id: "huaweiwatch6", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch d2-", id: "huaweiwatchd2", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch d3-", id: "huaweiwatchd3", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch fit-", id: "huaweiwatchfit", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch fit 2-", id: "huaweiwatchfit2", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch fit 3-", id: "huaweiwatchfit3", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch fit 4-", id: "huaweiwatchfit4pro", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch fit 4 pro-", id: "huaweiwatchfit4pro", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch fit 5-", id: "huaweiwatchfit5", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch fit 5 pro-", id: "huaweiwatchfit5pro", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch gt-", id: "huaweiwatchgt", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch gt 2-", id: "huaweiwatchgt2", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch gt 2 pro-", id: "huaweiwatchgt2", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch gt 2e-", id: "huaweiwatchgt2e", link: .ble, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch gt 3-", id: "huaweiwatchgt3", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch gt 3 pro-", id: "huaweiwatchgt3", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch gt 3 se-", id: "huaweiwatchgt3", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch gt 4-", id: "huaweiwatchgt4", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch gt 5-", id: "huaweiwatchgt5", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch gt 5 pro-", id: "huaweiwatchgt5", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch gt 6-", id: "huaweiwatchgt6", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch gt 6 pro-", id: "huaweiwatchgt6", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch gt 7 pro-", id: "huaweiwatchgt7", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch gt 7-", id: "huaweiwatchgt7", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch gt cyber-", id: "huaweiwatchgtcyber", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch gt runner-", id: "huaweiwatchgtrunner", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "watch gt runner 2-", id: "huaweiwatchgtrunner2", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "huawei watch ultimate-", id: "huaweiwatchultimate", link: .br, honorUUIDs: false, pake: false, encrypted: true),
    ModelInfo(prefix: "watch ultimate 2-", id: "huaweiwatchultimate2", link: .br, honorUUIDs: false, pake: false, encrypted: true),
]
