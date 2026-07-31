import Foundation
import IOKit

struct FanReading: Equatable {
    let index: Int
    let rpm: Double
}

/// Minimal read-only SMC client — just enough to read fan count and speeds.
/// Param layout modeled on the well-known SMCKit definition. Fails soft:
/// `nil` means the SMC wasn't reachable; an empty array means a fanless Mac.
final class SMCFansReader {
    static let shared = SMCFansReader()

    private var connection: io_connect_t = 0
    private var unavailable = false

    private init() {}

    // MARK: - SMC param structs (80 bytes total, kernel ABI)

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
        var memPLimit: UInt32 = 0
    }

    private struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
                   (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    // MARK: - Plumbing

    private func open() -> Bool {
        if connection != 0 { return true }
        if unavailable { return false }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            unavailable = true
            return false
        }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        if result != kIOReturnSuccess || connection == 0 {
            connection = 0
            unavailable = true
            return false
        }
        return true
    }

    private func fourCC(_ code: String) -> UInt32 {
        var value: UInt32 = 0
        for byte in code.utf8 {
            value = (value << 8) | UInt32(byte)
        }
        return value
    }

    private func callSMC(_ input: inout SMCParamStruct) -> SMCParamStruct? {
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection,
            2,   // kSMCHandleYPCEvent
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize
        )
        guard result == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    private func readKey(_ name: String) -> (type: UInt32, bytes: [UInt8])? {
        guard open() else { return nil }

        var info = SMCParamStruct()
        info.key = fourCC(name)
        info.data8 = 9   // get key info
        guard let infoResult = callSMC(&info) else { return nil }
        let size = Int(infoResult.keyInfo.dataSize)
        guard size > 0, size <= 32 else { return nil }

        var read = SMCParamStruct()
        read.key = fourCC(name)
        read.keyInfo.dataSize = infoResult.keyInfo.dataSize
        read.data8 = 5   // read bytes
        guard let readResult = callSMC(&read) else { return nil }

        var raw = readResult.bytes
        let bytes = withUnsafeBytes(of: &raw) { Array($0.prefix(size)) }
        return (infoResult.keyInfo.dataType, bytes)
    }

    private func decodeNumber(type: UInt32, bytes: [UInt8]) -> Double? {
        switch type {
        case fourCC("flt "):
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
            return Double(Float(bitPattern: bits))
        case fourCC("fpe2"):
            guard bytes.count >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(raw) / 4.0
        case fourCC("ui8 "):
            guard let first = bytes.first else { return nil }
            return Double(first)
        case fourCC("ui16"):
            guard bytes.count >= 2 else { return nil }
            return Double((UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
        case fourCC("ui32"):
            guard bytes.count >= 4 else { return nil }
            let value = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
            return Double(value)
        default:
            return nil
        }
    }

    // MARK: - Fans

    func readFans() -> [FanReading]? {
        guard let numData = readKey("FNum"),
              let count = decodeNumber(type: numData.type, bytes: numData.bytes) else { return nil }
        let fanCount = max(0, min(8, Int(count)))
        var fans: [FanReading] = []
        for index in 0..<fanCount {
            if let data = readKey("F\(index)Ac"),
               let rpm = decodeNumber(type: data.type, bytes: data.bytes),
               rpm >= 0, rpm < 20000 {
                fans.append(FanReading(index: index, rpm: rpm))
            }
        }
        return fans
    }
}
