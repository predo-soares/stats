import Darwin
import Foundation
import IOKit.ps

nonisolated(unsafe) private let samplerNanosecondsPerSecond: TimeInterval = 1_000_000_000
nonisolated(unsafe) private let samplerNanosecondsPerMillisecond: Double = 1_000_000
nonisolated(unsafe) private let samplerMicrosecondsPerSecond: TimeInterval = 1_000_000
nonisolated(unsafe) private let samplerPercentScale = 100.0
nonisolated(unsafe) private let samplerTopCPUProcessLimit = 10
nonisolated(unsafe) private let samplerTopMemoryProcessLimit = 8

struct HardwareInfoSample {
    var modelName: String
    var chipName: String
    var gpuSpec: String
}

struct CPUActivitySample {
    var stats: CPUStats?
    var temperature: Double?
    var thermalState: ProcessInfo.ThermalState
    var gpuStats: GPUStats?
    var cpuStatsDurationMS: Double
    var temperatureDurationMS: Double
    var gpuDurationMS: Double
}

struct ProcessEnumerationMeasurement {
    var durationMS: Double
    var processCount: Int
    var pidInfoCalls: Int
}

struct TopCPUProcessesSample {
    var processes: [RunningProcessStats]
    var measurement: ProcessEnumerationMeasurement
}

struct SlowMetricsSample {
    var memoryStats: MemoryStats
    var topMemoryProcesses: [MemoryProcessStats]
    var diskUsed: UInt64
    var diskTotal: UInt64
    var networkDownloadRate: UInt64?
    var networkUploadRate: UInt64?
    var battery: BatteryStats?
    var processEnumerationMeasurement: ProcessEnumerationMeasurement
    var memoryDurationMS: Double
    var diskDurationMS: Double
    var networkDurationMS: Double
    var batteryDurationMS: Double
}

struct MemoryMetricsSample {
    var memoryStats: MemoryStats
    var memoryDurationMS: Double
}

actor SystemMetricsSampler {
    private var previousCPUTicks: CPUTicks?
    private var previousProcessSamples: [Int32: ProcessCPUSample] = [:]
    private var previousNetworkSample: NetworkSample?
    private let smcConnection = SMCConnection()

    func fetchHardwareInfo() async -> HardwareInfoSample {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPHardwareDataType", "SPDisplaysDataType", "-json"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return HardwareInfoSample(modelName: "", chipName: "", gpuSpec: "")
        }

        let data = await Task.detached(priority: .background) {
            process.waitUntilExit()
            return pipe.fileHandleForReading.readDataToEndOfFile()
        }.value

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return HardwareInfoSample(modelName: "", chipName: "", gpuSpec: "")
        }

        var modelName = ""
        var chipName = ""
        var gpuSpec = ""

        if let hwArray = json["SPHardwareDataType"] as? [[String: Any]],
           let hw = hwArray.first {
            modelName = hw["machine_name"] as? String ?? ""
            chipName = hw["chip_type"] as? String ?? hw["cpu_type"] as? String ?? ""
        }

        if let displayArray = json["SPDisplaysDataType"] as? [[String: Any]],
           let display = displayArray.first {
            let cores = (display["sppci_cores"] as? String) ?? (display["sppci_cores"] as? Int).map(String.init)
            if let cores, !cores.isEmpty {
                gpuSpec = "\(cores)-core"
            }
        }

        return HardwareInfoSample(modelName: modelName, chipName: chipName, gpuSpec: gpuSpec)
    }

    func sampleCPUActivity() -> CPUActivitySample {
        let cpuStart = DispatchTime.now().uptimeNanoseconds
        let cpuStats = readCPUStats()
        let cpuDurationMS = elapsedMS(since: cpuStart)

        let temperatureStart = DispatchTime.now().uptimeNanoseconds
        let temperature = smcConnection.cpuTemperature()
        let temperatureDurationMS = elapsedMS(since: temperatureStart)

        let gpuStart = DispatchTime.now().uptimeNanoseconds
        let gpuStats = readGPUStats()
        let gpuDurationMS = elapsedMS(since: gpuStart)

        return CPUActivitySample(
            stats: cpuStats,
            temperature: temperature,
            thermalState: ProcessInfo.processInfo.thermalState,
            gpuStats: gpuStats,
            cpuStatsDurationMS: cpuDurationMS,
            temperatureDurationMS: temperatureDurationMS,
            gpuDurationMS: gpuDurationMS
        )
    }

    func sampleTopCPUProcesses() -> TopCPUProcessesSample {
        let processRead = readProcessInfos()
        let residentMemoryByPID = processRead.processes.reduce(into: [Int32: UInt64]()) { memoryByPID, processInfo in
            memoryByPID[processInfo.pid] = processInfo.residentMemory
        }
        let currentSamples = processRead.processes.reduce(into: [Int32: ProcessCPUSample]()) { samples, processInfo in
            samples[processInfo.pid] = ProcessCPUSample(
                name: processInfo.name,
                cpuTime: processInfo.cpuTime,
                uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
            )
        }
        defer { previousProcessSamples = currentSamples }

        guard !previousProcessSamples.isEmpty else {
            return TopCPUProcessesSample(processes: [], measurement: processRead.measurement)
        }

        let processes: [RunningProcessStats] = currentSamples.compactMap { (entry: (key: Int32, value: ProcessCPUSample)) in
            let pid = entry.key
            let currentSample = entry.value
            guard let previousSample = previousProcessSamples[pid] else { return nil }

            guard currentSample.uptimeNanoseconds >= previousSample.uptimeNanoseconds else { return nil }
            let elapsedNanoseconds = currentSample.uptimeNanoseconds - previousSample.uptimeNanoseconds
            let elapsed = TimeInterval(elapsedNanoseconds) / samplerNanosecondsPerSecond
            let cpuDelta = currentSample.cpuTime - previousSample.cpuTime
            guard elapsed > 0, cpuDelta > 0 else { return nil }

            return RunningProcessStats(
                pid: pid,
                name: currentSample.name,
                cpuPercent: (cpuDelta / elapsed) * samplerPercentScale,
                residentMemory: residentMemoryByPID[pid] ?? 0
            )
        }
        .sorted { $0.cpuPercent > $1.cpuPercent }
        .prefix(samplerTopCPUProcessLimit)
        .map { $0 }

        return TopCPUProcessesSample(processes: processes, measurement: processRead.measurement)
    }

    func sampleSlowMetrics() -> SlowMetricsSample {
        let memoryStart = DispatchTime.now().uptimeNanoseconds
        let memoryStats = readMemoryUsage()
        let memoryDurationMS = elapsedMS(since: memoryStart)

        let processRead = readProcessInfos()
        let topMemoryProcesses = processRead.processes
            .filter { $0.residentMemory > 0 }
            .map { processInfo in
                MemoryProcessStats(
                    pid: processInfo.pid,
                    name: processInfo.name,
                    memoryBytes: processInfo.residentMemory
                )
            }
            .sorted { $0.memoryBytes > $1.memoryBytes }
            .prefix(samplerTopMemoryProcessLimit)
            .map { $0 }

        let diskStart = DispatchTime.now().uptimeNanoseconds
        let disk = readDiskUsage()
        let diskDurationMS = elapsedMS(since: diskStart)

        let networkStart = DispatchTime.now().uptimeNanoseconds
        let network = readNetworkRates()
        let networkDurationMS = elapsedMS(since: networkStart)

        let batteryStart = DispatchTime.now().uptimeNanoseconds
        let battery = readBatteryStats()
        let batteryDurationMS = elapsedMS(since: batteryStart)

        return SlowMetricsSample(
            memoryStats: memoryStats,
            topMemoryProcesses: topMemoryProcesses,
            diskUsed: disk.used,
            diskTotal: disk.total,
            networkDownloadRate: network.downloadRate,
            networkUploadRate: network.uploadRate,
            battery: battery,
            processEnumerationMeasurement: processRead.measurement,
            memoryDurationMS: memoryDurationMS,
            diskDurationMS: diskDurationMS,
            networkDurationMS: networkDurationMS,
            batteryDurationMS: batteryDurationMS
        )
    }

    func sampleMemoryMetrics() -> MemoryMetricsSample {
        let memoryStart = DispatchTime.now().uptimeNanoseconds
        let memoryStats = readMemoryUsage()
        let memoryDurationMS = elapsedMS(since: memoryStart)

        return MemoryMetricsSample(
            memoryStats: memoryStats,
            memoryDurationMS: memoryDurationMS
        )
    }

    private func elapsedMS(since startedAt: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - startedAt) / samplerNanosecondsPerMillisecond
    }

    private func readProcessInfos() -> (processes: [ProcessInfoSample], measurement: ProcessEnumerationMeasurement) {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var length = 0

        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return (
                [],
                ProcessEnumerationMeasurement(durationMS: 0, processCount: 0, pidInfoCalls: 0)
            )
        }

        let processCount = length / MemoryLayout<kinfo_proc>.stride
        var processes = Array(repeating: kinfo_proc(), count: processCount)
        let result = processes.withUnsafeMutableBufferPointer { buffer in
            sysctl(&mib, u_int(mib.count), buffer.baseAddress, &length, nil, 0)
        }

        guard result == 0 else {
            return (
                [],
                ProcessEnumerationMeasurement(durationMS: 0, processCount: processCount, pidInfoCalls: 0)
            )
        }

        let processInfos: [ProcessInfoSample] = processes.compactMap { process in
            let pid = process.kp_proc.p_pid
            let name = Self.processName(from: process)

            guard pid > 0,
                  !name.isEmpty,
                  let taskInfo = readProcessTaskInfo(pid: pid) else {
                return nil
            }

            return ProcessInfoSample(
                pid: pid,
                name: name,
                cpuTime: taskInfo.cpuTime,
                residentMemory: taskInfo.residentMemory
            )
        }

        let durationMS = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / samplerNanosecondsPerMillisecond
        return (
            processInfos,
            ProcessEnumerationMeasurement(
                durationMS: durationMS,
                processCount: processCount,
                pidInfoCalls: processCount
            )
        )
    }

    private static func processName(from process: kinfo_proc) -> String {
        withUnsafeBytes(of: process.kp_proc.p_comm) { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: CChar.self).baseAddress else { return "" }
            return String(cString: baseAddress)
        }
    }

    private func readProcessTaskInfo(pid: pid_t) -> (cpuTime: TimeInterval, residentMemory: UInt64)? {
        var taskInfo = proc_taskinfo()
        let result = withUnsafeMutablePointer(to: &taskInfo) { pointer in
            proc_pidinfo(
                pid,
                PROC_PIDTASKINFO,
                0,
                pointer,
                Int32(MemoryLayout<proc_taskinfo>.stride)
            )
        }

        guard result == Int32(MemoryLayout<proc_taskinfo>.stride) else { return nil }

        // libproc reports cumulative task CPU time in microseconds.
        let microseconds = taskInfo.pti_total_user + taskInfo.pti_total_system
        var memoryBytes = UInt64(taskInfo.pti_resident_size)

        var usageInfo = rusage_info_v4()
        let usageResult = withUnsafeMutablePointer(to: &usageInfo) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { buffer in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, buffer)
            }
        }

        if usageResult == 0, usageInfo.ri_phys_footprint > 0 {
            memoryBytes = UInt64(usageInfo.ri_phys_footprint)
        }

        return (
            TimeInterval(microseconds) / samplerMicrosecondsPerSecond,
            memoryBytes
        )
    }

    private func readCPUStats() -> CPUStats? {
        guard let currentTicks = readCPUTicks() else { return nil }
        defer { previousCPUTicks = currentTicks }

        guard let previousCPUTicks else { return nil }

        let userDelta = currentTicks.user - previousCPUTicks.user
        let systemDelta = currentTicks.system - previousCPUTicks.system
        let niceDelta = currentTicks.nice - previousCPUTicks.nice
        let idleDelta = currentTicks.idle - previousCPUTicks.idle
        let totalDelta = userDelta + systemDelta + niceDelta + idleDelta

        guard totalDelta > 0 else { return nil }

        let total = Double(totalDelta)
        return CPUStats(
            user: Double(userDelta + niceDelta) / total,
            system: Double(systemDelta) / total,
            idle: Double(idleDelta) / total
        )
    }

    private func readCPUTicks() -> CPUTicks? {
        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )

        guard result == KERN_SUCCESS, let processorInfo else { return nil }
        defer {
            let size = vm_size_t(processorInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: processorInfo)), size)
        }

        var ticks = CPUTicks(user: 0, system: 0, nice: 0, idle: 0)
        let stride = Int(CPU_STATE_MAX)

        for processorIndex in 0..<Int(processorCount) {
            let offset = processorIndex * stride
            ticks.user += UInt64(processorInfo[offset + Int(CPU_STATE_USER)])
            ticks.system += UInt64(processorInfo[offset + Int(CPU_STATE_SYSTEM)])
            ticks.nice += UInt64(processorInfo[offset + Int(CPU_STATE_NICE)])
            ticks.idle += UInt64(processorInfo[offset + Int(CPU_STATE_IDLE)])
        }

        return ticks
    }

    private func readMemoryUsage() -> MemoryStats {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        let total = ProcessInfo.processInfo.physicalMemory
        let swap = readSwapUsage()
        let sampledPressure = readMemoryPressure()
        guard result == KERN_SUCCESS else {
            return MemoryStats(app: 0, wired: 0, compressed: 0, used: 0, total: total, swapUsed: swap.used, swapTotal: swap.total, sampledPressure: sampledPressure)
        }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let pageBytes = UInt64(pageSize)

        let appPages = max(Int64(statistics.internal_page_count) - Int64(statistics.purgeable_count), 0)
        let appBytes = UInt64(appPages) * pageBytes
        let wiredBytes = UInt64(statistics.wire_count) * pageBytes
        let compressedBytes = UInt64(statistics.compressor_page_count) * pageBytes
        let usedBytes = min(appBytes + wiredBytes + compressedBytes, total)

        return MemoryStats(
            app: appBytes,
            wired: wiredBytes,
            compressed: compressedBytes,
            used: usedBytes,
            total: total,
            swapUsed: swap.used,
            swapTotal: swap.total,
            sampledPressure: sampledPressure
        )
    }

    private func readMemoryPressure() -> Double? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/memory_pressure")
        process.arguments = []

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        guard let line = output.split(separator: "\n").first(where: { $0.contains("System-wide memory free percentage") }) else {
            return nil
        }

        let fields = line.split(whereSeparator: \.isWhitespace)
        guard let freeField = fields.first(where: { $0.hasSuffix("%") }),
              let freePercent = Double(freeField.dropLast()) else {
            return nil
        }

        return (100 - freePercent) / 100
    }

    private func readSwapUsage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else { return (0, 0) }
        return (UInt64(usage.xsu_used), UInt64(usage.xsu_total))
    }

    private func readDiskUsage() -> (used: UInt64, total: UInt64) {
        do {
            let values = try FileManager.default.homeDirectoryForCurrentUser.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])

            guard let total = values.volumeTotalCapacity else { return (0, 0) }
            let available = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
            let used = max(Int64(total) - available, 0)

            return (UInt64(used), UInt64(total))
        } catch {
            return (0, 0)
        }
    }

    private func readNetworkRates() -> (downloadRate: UInt64?, uploadRate: UInt64?) {
        guard let counters = readNetworkCounters() else { return (nil, nil) }
        defer { previousNetworkSample = counters }

        guard let previousNetworkSample else { return (nil, nil) }
        let elapsed = counters.date.timeIntervalSince(previousNetworkSample.date)
        guard elapsed > 0 else { return (nil, nil) }

        let receivedDelta = counters.receivedBytes >= previousNetworkSample.receivedBytes
            ? counters.receivedBytes - previousNetworkSample.receivedBytes
            : 0
        let sentDelta = counters.sentBytes >= previousNetworkSample.sentBytes
            ? counters.sentBytes - previousNetworkSample.sentBytes
            : 0

        return (
            UInt64(Double(receivedDelta) / elapsed),
            UInt64(Double(sentDelta) / elapsed)
        )
    }

    private func readNetworkCounters() -> NetworkSample? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        var receivedBytes: UInt64 = 0
        var sentBytes: UInt64 = 0

        for pointer in sequence(first: interfaces, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = Int32(interface.ifa_flags)

            guard flags & IFF_UP != 0,
                  flags & IFF_LOOPBACK == 0,
                  let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let data = interface.ifa_data else {
                continue
            }

            let networkData = data.assumingMemoryBound(to: if_data.self).pointee
            receivedBytes += UInt64(networkData.ifi_ibytes)
            sentBytes += UInt64(networkData.ifi_obytes)
        }

        return NetworkSample(date: Date(), receivedBytes: receivedBytes, sentBytes: sentBytes)
    }

    private func readBatteryStats() -> BatteryStats? {
        guard let powerSourcesInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let powerSources = IOPSCopyPowerSourcesList(powerSourcesInfo)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for powerSource in powerSources {
            guard let description = IOPSGetPowerSourceDescription(powerSourcesInfo, powerSource)?.takeUnretainedValue() as? [String: Any],
                  let currentCapacity = description[kIOPSCurrentCapacityKey as String] as? Int,
                  let maximumCapacity = description[kIOPSMaxCapacityKey as String] as? Int,
                  maximumCapacity > 0 else {
                continue
            }

            let state = description[kIOPSPowerSourceStateKey as String] as? String ?? "Unknown"
            let isCharging = (description[kIOPSIsChargingKey as String] as? Bool) ?? false
            let level = Double(currentCapacity) / Double(maximumCapacity)

            return BatteryStats(level: level, isCharging: isCharging, powerSource: state)
        }

        return nil
    }

    private func readGPUStats() -> GPUStats? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(0, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var best: Double = -1

        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var cfProps: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &cfProps, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = cfProps?.takeRetainedValue() as? [String: Any],
                  let perf = props["PerformanceStatistics"] as? [String: Any],
                  let util = perf["Device Utilization %"] as? Int else {
                continue
            }

            best = max(best, Double(util) / 100.0)
        }

        return best >= 0 ? GPUStats(utilization: best) : nil
    }
}

private struct CPUTicks {
    var user: UInt64
    var system: UInt64
    var nice: UInt64
    var idle: UInt64
}

private struct ProcessInfoSample {
    var pid: Int32
    var name: String
    var cpuTime: TimeInterval
    var residentMemory: UInt64
}

private struct ProcessCPUSample {
    var name: String
    var cpuTime: TimeInterval
    var uptimeNanoseconds: UInt64
}

private struct NetworkSample {
    var date: Date
    var receivedBytes: UInt64
    var sentBytes: UInt64
}
