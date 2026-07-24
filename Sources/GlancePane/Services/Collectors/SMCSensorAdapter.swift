import Darwin
import Foundation
import IOKit

struct SMCEncodedValue: Equatable {
    var dataType: String
    var bytes: [UInt8]
}

protocol SMCValueReading: AnyObject {
    func availableKeys() -> Set<String>
    func readValue(for key: String) -> SMCEncodedValue?
    func reconnect()
}

enum SMCValueDecoder {
    static func decode(_ value: SMCEncodedValue) -> Double? {
        let bytes = value.bytes
        switch value.dataType {
        case "ui8 ":
            guard let byte = bytes.first else { return nil }
            return Double(byte)
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(unsigned16(bytes))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            let raw = UInt32(bytes[0]) << 24 |
                UInt32(bytes[1]) << 16 |
                UInt32(bytes[2]) << 8 |
                UInt32(bytes[3])
            return Double(raw)
        case "sp1e": return signedFixedPoint(bytes, fractionalBits: 14)
        case "sp3c": return signedFixedPoint(bytes, fractionalBits: 12)
        case "sp4b": return signedFixedPoint(bytes, fractionalBits: 11)
        case "sp5a": return signedFixedPoint(bytes, fractionalBits: 10)
        case "sp69": return signedFixedPoint(bytes, fractionalBits: 9)
        case "sp78": return signedFixedPoint(bytes, fractionalBits: 8)
        case "sp87": return signedFixedPoint(bytes, fractionalBits: 7)
        case "sp96": return signedFixedPoint(bytes, fractionalBits: 6)
        case "spa5": return signedFixedPoint(bytes, fractionalBits: 5)
        case "spb4": return signedFixedPoint(bytes, fractionalBits: 4)
        case "spf0": return signedFixedPoint(bytes, fractionalBits: 0)
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double(unsigned16(bytes)) / 4
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) |
                UInt32(bytes[1]) << 8 |
                UInt32(bytes[2]) << 16 |
                UInt32(bytes[3]) << 24
            let result = Double(Float(bitPattern: bits))
            return result.isFinite ? result : nil
        default:
            return nil
        }
    }

    private static func unsigned16(_ bytes: [UInt8]) -> UInt16 {
        UInt16(bytes[0]) << 8 | UInt16(bytes[1])
    }

    private static func signedFixedPoint(_ bytes: [UInt8], fractionalBits: Int) -> Double? {
        guard bytes.count >= 2 else { return nil }
        let signed = Int16(bitPattern: unsigned16(bytes))
        return Double(signed) / Double(1 << fractionalBits)
    }
}

final class SMCSensorAdapter {
    private let reader: SMCValueReading
    private let chipName: String?
    private var selection: SensorSelection?
    private var retriedEmptySample = false

    init(reader: SMCValueReading = AppleSMCReader(), chipName: String? = nil) {
        self.reader = reader
        self.chipName = chipName ?? Self.currentChipName()
    }

    func sample() -> ThermalStats {
        let selection = resolvedSelection()
        let result = read(selection)
        if result.hasAnyValue {
            retriedEmptySample = false
            return result
        }

        guard selection.hasKeys, !retriedEmptySample else {
            return result
        }

        retriedEmptySample = true
        reader.reconnect()
        self.selection = nil
        return read(resolvedSelection())
    }

    func resetConnection() {
        reader.reconnect()
        selection = nil
        retriedEmptySample = false
    }

    static func isValidTemperature(_ value: Double) -> Bool {
        value.isFinite && (10...120).contains(value)
    }

    static func isValidFanSpeed(_ value: Double) -> Bool {
        value.isFinite && (0...20_000).contains(value)
    }

    static func isValidPower(_ value: Double) -> Bool {
        value.isFinite && value > 0 && value <= 500
    }

    private func resolvedSelection() -> SensorSelection {
        if let selection { return selection }
        let value = SensorSelection(availableKeys: reader.availableKeys(), chipName: chipName)
        selection = value
        return value
    }

    private static func currentChipName() -> String? {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 1 else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        return String(cString: buffer)
    }

    private func read(_ selection: SensorSelection) -> ThermalStats {
        ThermalStats(
            isEnabled: true,
            cpuTemperatureCelsius: maximumValue(for: selection.cpuTemperatureKeys, validator: Self.isValidTemperature),
            gpuTemperatureCelsius: maximumValue(for: selection.gpuTemperatureKeys, validator: Self.isValidTemperature),
            socTemperatureCelsius: maximumValue(for: selection.socTemperatureKeys, validator: Self.isValidTemperature),
            gpuUsage: nil,
            gpuFrequencyMHz: nil,
            fanSpeedRPM: maximumValue(for: selection.fanSpeedKeys, validator: Self.isValidFanSpeed),
            powerWatts: firstValue(for: selection.powerKeys, validator: Self.isValidPower)
        )
    }

    private func maximumValue(for keys: [String], validator: (Double) -> Bool) -> Double? {
        keys.compactMap(readDecodedValue).filter(validator).max()
    }

    private func firstValue(for keys: [String], validator: (Double) -> Bool) -> Double? {
        for key in keys {
            if let value = readDecodedValue(key), validator(value) {
                return value
            }
        }
        return nil
    }

    private func readDecodedValue(_ key: String) -> Double? {
        reader.readValue(for: key).flatMap(SMCValueDecoder.decode)
    }
}

struct SensorSelection: Equatable {
    var cpuTemperatureKeys: [String]
    var gpuTemperatureKeys: [String]
    var socTemperatureKeys: [String]
    var fanSpeedKeys: [String]
    var powerKeys: [String]

    init(availableKeys: Set<String>, chipName: String?) {
        cpuTemperatureKeys = Self.orderedIntersection(Self.cpuTemperatureCatalog(for: chipName), availableKeys)
        gpuTemperatureKeys = Self.orderedIntersection(Self.gpuTemperatureCatalog(for: chipName), availableKeys)
        socTemperatureKeys = Self.orderedIntersection(Self.socTemperatureCatalog, availableKeys)
        fanSpeedKeys = availableKeys.filter(Self.isFanSpeedKey).sorted()
        powerKeys = Self.orderedIntersection(Self.totalPowerCatalog, availableKeys)
    }

    var hasKeys: Bool {
        !cpuTemperatureKeys.isEmpty ||
            !gpuTemperatureKeys.isEmpty ||
            !socTemperatureKeys.isEmpty ||
            !fanSpeedKeys.isEmpty ||
            !powerKeys.isEmpty
    }

    private static func orderedIntersection(_ catalog: [String], _ keys: Set<String>) -> [String] {
        catalog.filter(keys.contains)
    }

    private static func isFanSpeedKey(_ key: String) -> Bool {
        let characters = Array(key)
        return characters.count == 4 &&
            characters[0] == "F" &&
            characters[1].isNumber &&
            characters[2] == "A" &&
            characters[3] == "c"
    }

    private static func cpuTemperatureCatalog(for chipName: String?) -> [String] {
        guard let chipName else { return intelCPUTemperatureCatalog }
        if chipName.hasPrefix("Apple M1") { return m1CPUTemperatureCatalog }
        if chipName.hasPrefix("Apple M2") { return m2CPUTemperatureCatalog }
        if chipName.hasPrefix("Apple M3") { return m3CPUTemperatureCatalog }
        if chipName.hasPrefix("Apple M4") { return m4CPUTemperatureCatalog }
        if chipName.hasPrefix("Apple M5") { return m5CPUTemperatureCatalog }
        return chipName.hasPrefix("Apple ") ? [] : intelCPUTemperatureCatalog
    }

    private static func gpuTemperatureCatalog(for chipName: String?) -> [String] {
        guard let chipName else { return intelGPUTemperatureCatalog }
        if chipName.hasPrefix("Apple M1") { return m1GPUTemperatureCatalog }
        if chipName.hasPrefix("Apple M2") { return m2GPUTemperatureCatalog }
        if chipName.hasPrefix("Apple M3") { return m3GPUTemperatureCatalog }
        if chipName.hasPrefix("Apple M4") { return m4GPUTemperatureCatalog }
        if chipName.hasPrefix("Apple M5") { return m5GPUTemperatureCatalog }
        return chipName.hasPrefix("Apple ") ? [] : intelGPUTemperatureCatalog
    }

    private static let intelCPUTemperatureCatalog = ["TCAD", "TC0D", "TC0E", "TC0F", "TC0H", "TC0P"]
    private static let intelGPUTemperatureCatalog = ["TCGC", "TG0D", "TG0H", "TG0P", "TGDD"]

    private static let m1CPUTemperatureCatalog = [
        "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"
    ]
    private static let m1GPUTemperatureCatalog = ["Tg05", "Tg0D", "Tg0L", "Tg0T"]

    private static let m2CPUTemperatureCatalog = [
        "Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"
    ]
    private static let m2GPUTemperatureCatalog = ["Tg0f", "Tg0j"]

    private static let m3CPUTemperatureCatalog = [
        "Te05", "Te0L", "Te0P", "Te0S",
        "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"
    ]
    private static let m3GPUTemperatureCatalog = ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"]

    private static let m4CPUTemperatureCatalog = [
        "Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"
    ]
    private static let m4GPUTemperatureCatalog = [
        "Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"
    ]

    private static let m5CPUTemperatureCatalog = [
        "Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K",
        "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"
    ]
    private static let m5GPUTemperatureCatalog = ["Tg0U", "Tg0X", "Tg0d", "Tg0g", "Tg0j", "Tg1Y", "Tg1c", "Tg1g"]

    private static let socTemperatureCatalog: [String] = []
    private static let totalPowerCatalog = ["PSTR", "PDTR"]
}

private final class AppleSMCReader: SMCValueReading {
    private let lock = NSLock()
    private var connection: io_connect_t = 0

    init() {
        connection = Self.openConnection()
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    func availableKeys() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        guard connection != 0,
              let countValue = readValueUnlocked(for: "#KEY").flatMap(SMCValueDecoder.decode)
        else { return [] }

        let count = Int(countValue)
        guard count > 0, count < 100_000 else { return [] }
        var keys = Set<String>()
        for index in 0..<count {
            var input = SMCKeyData()
            var output = SMCKeyData()
            input.data8 = SMCCommand.readIndex.rawValue
            input.data32 = UInt32(index)
            guard call(input: &input, output: &output) == kIOReturnSuccess else { continue }
            let key = Self.string(from: output.key)
            if key.count == 4 { keys.insert(key) }
        }
        return keys
    }

    func readValue(for key: String) -> SMCEncodedValue? {
        lock.lock()
        defer { lock.unlock() }
        return readValueUnlocked(for: key)
    }

    func reconnect() {
        lock.lock()
        defer { lock.unlock() }
        if connection != 0 {
            IOServiceClose(connection)
        }
        connection = Self.openConnection()
    }

    private func readValueUnlocked(for key: String) -> SMCEncodedValue? {
        guard connection != 0, key.utf8.count == 4 else { return nil }
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = Self.fourCharacterCode(key)
        input.data8 = SMCCommand.readKeyInfo.rawValue

        guard call(input: &input, output: &output) == kIOReturnSuccess,
              output.keyInfo.dataSize > 0,
              output.keyInfo.dataSize <= 32
        else { return nil }

        let dataType = output.keyInfo.dataType
        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = SMCCommand.readBytes.rawValue
        output = SMCKeyData()
        guard call(input: &input, output: &output) == kIOReturnSuccess,
              output.result == 0
        else { return nil }

        var rawBytes = output.bytes
        let bytes = withUnsafeBytes(of: &rawBytes) { buffer in
            Array(buffer.prefix(Int(input.keyInfo.dataSize)))
        }
        return SMCEncodedValue(dataType: Self.string(from: dataType), bytes: bytes)
    }

    private func call(input: inout SMCKeyData, output: inout SMCKeyData) -> kern_return_t {
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride
        return IOConnectCallStructMethod(
            connection,
            UInt32(SMCCommand.kernelIndex.rawValue),
            &input,
            inputSize,
            &output,
            &outputSize
        )
    }

    private static func openConnection() -> io_connect_t {
        for serviceName in ["AppleSMC", "AppleSMCKeysEndpoint"] {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(serviceName))
            guard service != 0 else { continue }
            var connection: io_connect_t = 0
            let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
            IOObjectRelease(service)
            if result == kIOReturnSuccess {
                return connection
            }
        }
        return 0
    }

    private static func fourCharacterCode(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func string(from code: UInt32) -> String {
        String(bytes: [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ], encoding: .ascii) ?? ""
    }
}

private enum SMCCommand: UInt8 {
    case kernelIndex = 2
    case readBytes = 5
    case readIndex = 8
    case readKeyInfo = 9
}

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memoryPLimit: UInt32 = 0
}

private struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var version = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}
