import Foundation
import IOKit

final class SMCConnection {
    nonisolated(unsafe) private var connection: io_connect_t = 0

    nonisolated
    init() {
        let service = IOServiceGetMatchingService(0, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(service) }
        IOServiceOpen(service, mach_task_self_, 0, &connection)
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    nonisolated
    func cpuTemperature() -> Double? {
        // Apple Silicon keys first, then Intel
        let keys = ["Tp09", "Tp0T", "Tp01", "Ts0P", "TC0P", "TC0E", "TCXC"]
        for key in keys {
            if let temp = readTemperature(key: key), temp > 0 && temp < 120 {
                return temp
            }
        }
        return nil
    }

    nonisolated
    private func readTemperature(key: String) -> Double? {
        guard connection != 0 else { return nil }

        var input = SMCParamStruct()
        var output = SMCParamStruct()
        input.key = fourCC(key)
        input.data8 = 9 // kSMCGetKeyInfo

        guard callSMC(input: &input, output: &output) == KERN_SUCCESS,
              output.result == 0 else { return nil }

        let dataSize = output.keyInfoDataSize

        input = SMCParamStruct()
        output = SMCParamStruct()
        input.key = fourCC(key)
        input.keyInfoDataSize = dataSize
        input.data8 = 5 // kSMCReadKey

        guard callSMC(input: &input, output: &output) == KERN_SUCCESS,
              output.result == 0 else { return nil }

        // sp78: big-endian signed fixed-point (7 int bits + 8 frac bits)
        let raw = (UInt16(output.bytes.0) << 8) | UInt16(output.bytes.1)
        return Double(raw) / 256.0
    }

    nonisolated
    private func callSMC(input: inout SMCParamStruct, output: inout SMCParamStruct) -> kern_return_t {
        var outputSize = MemoryLayout<SMCParamStruct>.size
        return IOConnectCallStructMethod(
            connection,
            2, // kSMCHandleYPCEvent
            &input,
            MemoryLayout<SMCParamStruct>.size,
            &output,
            &outputSize
        )
    }

    nonisolated
    private func fourCC(_ string: String) -> UInt32 {
        string.unicodeScalars.prefix(4).reduce(0) { ($0 << 8) | UInt32($1.value) }
    }
}

// Flat layout matching the C SMCParamStruct (80 bytes total).
// Explicit padding fields reproduce C sub-struct alignment.
private struct SMCParamStruct {
    var key: UInt32 = 0
    // SMCVersion (6 bytes)
    var versMajor: UInt8 = 0
    var versMinor: UInt8 = 0
    var versBuild: UInt8 = 0
    var versReserved: UInt8 = 0
    var versRelease: UInt16 = 0
    var _pad0: UInt16 = 0           // align SMCPLimitData to 4-byte boundary
    // SMCPLimitData (16 bytes)
    var pLimitVersion: UInt16 = 0
    var pLimitLength: UInt16 = 0
    var pLimitCPU: UInt32 = 0
    var pLimitGPU: UInt32 = 0
    var pLimitMem: UInt32 = 0
    // SMCKeyInfoData (12 bytes: 4+4+1+3pad)
    var keyInfoDataSize: UInt32 = 0
    var keyInfoDataType: UInt32 = 0
    var keyInfoDataAttributes: UInt8 = 0
    var _pad1: UInt8 = 0            // trailing padding for SMCKeyInfoData
    var _pad2: UInt8 = 0
    var _pad3: UInt8 = 0
    // result/status/data fields
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var _pad4: UInt8 = 0            // align data32 to 4-byte boundary
    var data32: UInt32 = 0
    // 32-byte value buffer
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )

    nonisolated init() {}
}
