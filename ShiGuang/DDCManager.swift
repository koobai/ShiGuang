import CoreFoundation
import CoreGraphics
import Darwin
import Foundation
import IOKit

nonisolated final class DDCManager: @unchecked Sendable {
    private enum Constant {
        static let ddcChipAddress: UInt32 = 0x37
        static let controlAddress: UInt32 = 0x51
        static let brightnessVCPCode: UInt8 = 0x10
    }

    private let ioav = IOAVServiceRuntime()
    private var service: IOAVServiceRef?
    private var maxBrightnessValue: UInt16?

    func readBrightnessPercent() throws -> Int {
        do {
            return try readBrightnessPercentOnce()
        } catch {
            resetConnection()
            usleep(120_000)
            return try readBrightnessPercentOnce()
        }
    }

    func setBrightnessPercent(_ percent: Int) throws {
        do {
            try setBrightnessPercentOnce(percent)
        } catch {
            resetConnection()
            usleep(120_000)
            try setBrightnessPercentOnce(percent)
        }
    }

    func resetConnection() {
        service = nil
        maxBrightnessValue = nil
    }

    private func readBrightnessPercentOnce() throws -> Int {
        let value = try readVCPFeature(Constant.brightnessVCPCode)
        let maximum = max(1, value.maximum)
        maxBrightnessValue = maximum
        let percent = Int((Double(value.current) / Double(maximum) * 100).rounded())
        return min(100, max(0, percent))
    }

    private func setBrightnessPercentOnce(_ percent: Int) throws {
        let service = try currentService()
        let clampedPercent = min(100, max(0, percent))
        let maximum = try brightnessMaximumValue()
        let rawValue = UInt16((Double(maximum) * Double(clampedPercent) / 100).rounded())
        let payload: [UInt8] = [
            Constant.brightnessVCPCode,
            UInt8((rawValue >> 8) & 0xFF),
            UInt8(rawValue & 0xFF)
        ]
        try write(command: 0x03, payload: payload, service: service)
    }

    private func brightnessMaximumValue() throws -> UInt16 {
        if let maxBrightnessValue {
            return maxBrightnessValue
        }

        let value = try readVCPFeature(Constant.brightnessVCPCode)
        let maximum = max(1, value.maximum)
        maxBrightnessValue = maximum
        return maximum
    }

    private func readVCPFeature(_ code: UInt8) throws -> VCPValue {
        let service = try currentService()
        try write(command: 0x01, payload: [code], service: service, includeDataAddressInChecksum: false)
        usleep(40_000)

        var reply = [UInt8](repeating: 0, count: 11)
        let replyCount = UInt32(reply.count)
        let result = reply.withUnsafeMutableBytes { buffer in
            ioav.readI2C(service, Constant.ddcChipAddress, 0, buffer.baseAddress!, replyCount)
        }

        guard result == kIOReturnSuccess else {
            throw DDCError.i2cReadFailed(result)
        }

        guard checksumIsValid(reply, start: 0x50) else {
            throw DDCError.invalidChecksum
        }

        guard reply.count >= 10, reply[2] == 0x02, reply[4] == code else {
            throw DDCError.invalidReply
        }

        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        return VCPValue(current: current, maximum: max(1, maximum))
    }

    private func write(
        command: UInt8,
        payload: [UInt8],
        service: IOAVServiceRef,
        includeDataAddressInChecksum: Bool = true
    ) throws {
        var packet = [UInt8]()
        packet.reserveCapacity(payload.count + 4)
        packet.append(0x80 | UInt8(payload.count + 1))
        packet.append(command)
        packet.append(contentsOf: payload)

        var checksum = UInt8(Constant.ddcChipAddress << 1)
        if includeDataAddressInChecksum {
            checksum ^= UInt8(Constant.controlAddress)
        }
        for byte in packet {
            checksum ^= byte
        }
        packet.append(checksum)

        let packetCount = UInt32(packet.count)
        let result = packet.withUnsafeMutableBytes { buffer in
            ioav.writeI2C(service, Constant.ddcChipAddress, Constant.controlAddress, buffer.baseAddress!, packetCount)
        }

        guard result == kIOReturnSuccess else {
            throw DDCError.i2cWriteFailed(result)
        }

        usleep(10_000)
    }

    private func currentService() throws -> IOAVServiceRef {
        if let service {
            return service
        }

        guard ioav.isAvailable else {
            throw DDCError.privateAPINotAvailable
        }

        guard firstExternalDisplayID() != nil else {
            throw DDCError.externalDisplayNotFound
        }

        guard let createdService = createExternalService() ?? ioav.createDefaultService() else {
            throw DDCError.serviceNotFound
        }

        service = createdService
        return createdService
    }

    private func firstExternalDisplayID() -> CGDirectDisplayID? {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return nil
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success else {
            return nil
        }

        return displays.prefix(Int(displayCount)).first { displayID in
            CGDisplayIsBuiltin(displayID) <= 0
        }
    }

    private func createExternalService() -> IOAVServiceRef? {
        guard ioav.canCreateWithRegistryService else {
            return nil
        }

        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("DCPAVServiceProxy")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else { break }
            defer { IOObjectRelease(entry) }

            if registryString(entry, key: "Location") == "External",
               let service = ioav.createService(from: entry) {
                return service
            }
        }

        return nil
    }

    private func registryString(_ entry: io_registry_entry_t, key: String) -> String? {
        guard let property = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }

        return property.takeRetainedValue() as? String
    }

    private func checksumIsValid(_ bytes: [UInt8], start: UInt8) -> Bool {
        guard let expected = bytes.last else {
            return false
        }

        let checksum = bytes.dropLast().reduce(start) { $0 ^ $1 }
        return checksum == expected
    }
}

private struct VCPValue {
    let current: UInt16
    let maximum: UInt16
}

private typealias IOAVServiceRef = CFTypeRef

nonisolated private final class IOAVServiceRuntime {
    typealias CreateFunction = @convention(c) (CFAllocator?) -> Unmanaged<IOAVServiceRef>?
    typealias CreateWithServiceFunction = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<IOAVServiceRef>?
    typealias ReadI2CFunction = @convention(c) (IOAVServiceRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    typealias WriteI2CFunction = @convention(c) (IOAVServiceRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private let frameworkHandle: UnsafeMutableRawPointer?
    private let create: CreateFunction?
    private let createWithService: CreateWithServiceFunction?
    let readI2C: ReadI2CFunction
    let writeI2C: WriteI2CFunction

    var isAvailable: Bool {
        frameworkHandle != nil
    }

    var canCreateWithRegistryService: Bool {
        createWithService != nil
    }

    init() {
        frameworkHandle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        create = Self.loadSymbol("IOAVServiceCreate", from: frameworkHandle)
        createWithService = Self.loadSymbol("IOAVServiceCreateWithService", from: frameworkHandle)
        readI2C = Self.loadSymbol("IOAVServiceReadI2C", from: frameworkHandle) ?? { _, _, _, _, _ in kIOReturnUnsupported }
        writeI2C = Self.loadSymbol("IOAVServiceWriteI2C", from: frameworkHandle) ?? { _, _, _, _, _ in kIOReturnUnsupported }
    }

    func createDefaultService() -> IOAVServiceRef? {
        create?(kCFAllocatorDefault)?.takeRetainedValue()
    }

    func createService(from registryService: io_service_t) -> IOAVServiceRef? {
        createWithService?(kCFAllocatorDefault, registryService)?.takeRetainedValue()
    }

    private static func loadSymbol<T>(_ name: String, from handle: UnsafeMutableRawPointer?) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else {
            return nil
        }

        return unsafeBitCast(symbol, to: T.self)
    }
}

enum DDCError: LocalizedError {
    case privateAPINotAvailable
    case externalDisplayNotFound
    case serviceNotFound
    case i2cReadFailed(IOReturn)
    case i2cWriteFailed(IOReturn)
    case invalidChecksum
    case invalidReply

    var errorDescription: String? {
        switch self {
        case .privateAPINotAvailable:
            "IOAVService 私有接口不可用"
        case .externalDisplayNotFound:
            "未检测到外接显示器"
        case .serviceNotFound:
            "未找到外接显示器的 IOAVService"
        case .i2cReadFailed(let code):
            "DDC 读取失败：\(code)"
        case .i2cWriteFailed(let code):
            "DDC 写入失败：\(code)"
        case .invalidChecksum:
            "显示器返回的 DDC 校验失败"
        case .invalidReply:
            "显示器返回了无法识别的 DDC 数据"
        }
    }
}
