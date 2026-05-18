import CoreLocation
import Darwin
import Foundation
import Observation

@MainActor
@Observable
final class SystemStatsStore {
    var snapshot = SystemStatsSnapshot.empty
    var cpuHistory: [Double] = []
    var cpuStatsHistory: [CPUStats] = []
    var networkRateHistory: [NetworkRateSample] = []
    var thermalHistory: [ProcessInfo.ThermalState] = []
    var menuBarIndex = 0
    var machineModelName: String = ""
    var machineChipName: String = ""
    var machineGPUSpec: String = ""
    var networkName: String = ""
    var cpuTemperature: Double? = nil
    var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    var activeIssues: [DiagnosticsIssueEvent] = []
    var recentIssues: [DiagnosticsIssueEvent] = []

    var machineMemoryString: String {
        "\(Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)) GB"
    }

    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var memoryRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var cpuRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var cpuProcessRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var instrumentation = SystemStatsInstrumentation()
    @ObservationIgnored private let sampler = SystemMetricsSampler()
    @ObservationIgnored private lazy var locationPermissionCoordinator = LocationPermissionCoordinator { [weak self] in
        Task { [weak self] in
            await self?.refreshHardwareInfo()
        }
    }
    @ObservationIgnored private let diagnosticsMapper = DiagnosticsInputMapper()
    @ObservationIgnored private let diagnosticsEngine = DiagnosticsEngine()
    @ObservationIgnored private let diagnosticsPersistence = DiagnosticsPersistence()
    @ObservationIgnored private var diagnosticsTracker = DiagnosticsEventTracker()
    @ObservationIgnored private var memorySignalHistory: [DiagnosticsMemorySignal] = []
    @ObservationIgnored private var latestCPUStats: CPUStats?
    @ObservationIgnored private var latestTopProcesses: [RunningProcessStats] = []
    @ObservationIgnored private var latestMemoryStats: MemoryStats?
    @ObservationIgnored private var latestTopMemoryProcesses: [MemoryProcessStats] = []
    @ObservationIgnored private var latestDiskUsed: UInt64 = 0
    @ObservationIgnored private var latestDiskTotal: UInt64 = 0
    @ObservationIgnored private var latestNetworkDownloadRate: UInt64?
    @ObservationIgnored private var latestNetworkUploadRate: UInt64?
    @ObservationIgnored private var latestBattery: BatteryStats?
    @ObservationIgnored private var latestGPUStats: GPUStats?
    @ObservationIgnored private var isSlowLaneRunning = false
    @ObservationIgnored private var isMemoryLaneRunning = false
    @ObservationIgnored private var isCPUActivityLaneRunning = false
    @ObservationIgnored private var isCPUProcessesLaneRunning = false

    var instrumentationSnapshot: SystemStatsInstrumentationSnapshot {
        instrumentation.snapshot
    }

    var instrumentationReport: String {
        instrumentation.formattedReport()
    }

    var menuBarSummary: String {
        let items = menuBarItems
        guard !items.isEmpty else { return "Stats" }
        return items[menuBarIndex % items.count]
    }

    private var menuBarItems: [String] {
        var items = [String]()

        if let cpuUsage = snapshot.cpuUsage {
            items.append("CPU \(StatsFormatting.percentString(cpuUsage))")
        } else {
            items.append("CPU --")
        }

        items.append("Mem \(StatsFormatting.percentString(snapshot.memoryUsage))")

        if let downloadRate = snapshot.networkDownloadRate,
           let uploadRate = snapshot.networkUploadRate {
            items.append("Net ↓ \(StatsFormatting.byteRateString(downloadRate)) ↑ \(StatsFormatting.byteRateString(uploadRate))")
        } else {
            items.append("Net measuring")
        }

        if snapshot.diskTotal > 0 {
            items.append("Disk \(StatsFormatting.percentString(snapshot.diskUsage))")
        }

        if let battery = snapshot.battery {
            items.append("Bat \(StatsFormatting.percentString(battery.level))")
        }

        return items
    }

    init() {
        Task { [weak self] in
            await self?.loadPersistedIssues()
            await self?.refreshHardwareInfo()
            self?.locationPermissionCoordinator.requestIfNeeded()
            self?.startSampling()
            self?.refreshNow()
        }
    }

    deinit {
        refreshTask?.cancel()
        memoryRefreshTask?.cancel()
        cpuRefreshTask?.cancel()
        cpuProcessRefreshTask?.cancel()
    }

    func refreshNow() {
        let token = instrumentation.beginCycle(.manualRefresh, expectedInterval: nil)

        Task { [weak self] in
            guard let self else { return }
            await self.runMemoryLane()
            await self.runSlowLane()
            await self.runCPUActivityLane()
            await self.runCPUProcessesLane()
            self.instrumentation.endCycle(token)
            self.instrumentation.logSummary(reason: "manual_refresh")
        }
    }

    func killProcess(pid: Int32) {
        Darwin.kill(pid, SIGTERM)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            await self?.runCPUProcessesLane(force: true)
            await self?.runSlowLane(force: true)
        }
    }

    func clearRecentIssueHistory() {
        diagnosticsTracker.clearResolvedHistory()
        recentIssues = []
        Task { [weak self] in
            guard let self else { return }
            await self.diagnosticsPersistence.clear()
            await self.persistDiagnosticsState()
        }
    }

    func logInstrumentationSummary(reason: String = "manual_dump") {
        instrumentation.logSummary(reason: reason)
    }

    func recordPanelPresentation(_ metric: SystemStatsInstrumentation.Metric, elapsedMS: Double) {
        instrumentation.record(metric, elapsedMS: elapsedMS)
    }

    private func startSampling() {
        refreshTask?.cancel()
        memoryRefreshTask?.cancel()
        cpuRefreshTask?.cancel()
        cpuProcessRefreshTask?.cancel()

        refreshTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                await self.runTimedSlowCycle()
            }
        }

        memoryRefreshTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self.runTimedMemoryCycle()
            }
        }

        cpuRefreshTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self.runTimedCPUActivityCycle()
            }
        }

        cpuProcessRefreshTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self.runCPUProcessesLane()
            }
        }
    }

    private func loadPersistedIssues() async {
        let persisted = await diagnosticsPersistence.load()
        diagnosticsTracker.restore(active: persisted.active, resolved: persisted.resolved)
        activeIssues = persisted.active.sorted(by: DiagnosticsEventTracker.sort)
        recentIssues = Array(diagnosticsTracker.resolvedIssueHistory.prefix(5))
    }

    private func refreshHardwareInfo() async {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let info = await sampler.fetchHardwareInfo()
        let elapsedMS = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000

        machineModelName = info.modelName
        machineChipName = info.chipName
        machineGPUSpec = info.gpuSpec
        networkName = info.networkName
        instrumentation.record(.hardwareInfo, elapsedMS: elapsedMS)
    }

    private func runTimedSlowCycle() async {
        let token = instrumentation.beginCycle(.refreshTimer, expectedInterval: 10)
        await runSlowLane()
        menuBarIndex = menuBarItems.isEmpty ? 0 : (menuBarIndex + 1) % menuBarItems.count
        instrumentation.endCycle(token)
    }

    private func runTimedMemoryCycle() async {
        let token = instrumentation.beginCycle(.memoryTimer, expectedInterval: 2)
        await runMemoryLane()
        instrumentation.endCycle(token)
    }

    private func runTimedCPUActivityCycle() async {
        let token = instrumentation.beginCycle(.cpuTimer, expectedInterval: 1)
        await runCPUActivityLane()
        instrumentation.endCycle(token)
    }

    private func runMemoryLane(force: Bool = false) async {
        guard !isMemoryLaneRunning || force else { return }
        isMemoryLaneRunning = true
        defer { isMemoryLaneRunning = false }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        let result = await sampler.sampleMemoryMetrics()

        latestMemoryStats = result.memoryStats

        let signal = diagnosticsMapper.makeMemorySignal(
            stats: result.memoryStats,
            history: memorySignalHistory,
            timestamp: Date()
        )
        memorySignalHistory.append(signal)
        trim(&memorySignalHistory, limit: 12)

        instrumentation.record(.memorySample, elapsedMS: result.memoryDurationMS)

        rebuildSnapshot()
        evaluateDiagnostics()

        let elapsedMS = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        instrumentation.record(.refreshPublish, elapsedMS: elapsedMS)
    }

    private func runSlowLane(force: Bool = false) async {
        guard !isSlowLaneRunning || force else { return }
        isSlowLaneRunning = true
        defer { isSlowLaneRunning = false }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        let result = await sampler.sampleSlowMetrics()

        latestMemoryStats = result.memoryStats
        latestTopMemoryProcesses = result.topMemoryProcesses
        latestDiskUsed = result.diskUsed
        latestDiskTotal = result.diskTotal
        latestNetworkDownloadRate = result.networkDownloadRate
        latestNetworkUploadRate = result.networkUploadRate
        latestBattery = result.battery

        if let downloadRate = result.networkDownloadRate,
           let uploadRate = result.networkUploadRate {
            networkRateHistory.append(
                NetworkRateSample(
                    downloadRate: downloadRate,
                    uploadRate: uploadRate
                )
            )
            trim(&networkRateHistory, limit: 60)
        }

        instrumentation.record(.diskSample, elapsedMS: result.diskDurationMS)
        instrumentation.record(.networkSample, elapsedMS: result.networkDurationMS)
        instrumentation.record(.batterySample, elapsedMS: result.batteryDurationMS)
        instrumentation.record(.topMemoryProcesses, elapsedMS: result.processEnumerationMeasurement.durationMS)
        instrumentation.recordProcessEnumeration(
            durationMS: result.processEnumerationMeasurement.durationMS,
            processCount: result.processEnumerationMeasurement.processCount,
            pidInfoCalls: result.processEnumerationMeasurement.pidInfoCalls
        )

        rebuildSnapshot()
        evaluateDiagnostics()

        let elapsedMS = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        instrumentation.record(.refreshPublish, elapsedMS: elapsedMS)
    }

    private func runCPUActivityLane(force: Bool = false) async {
        guard !isCPUActivityLaneRunning || force else { return }
        isCPUActivityLaneRunning = true
        defer { isCPUActivityLaneRunning = false }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        let result = await sampler.sampleCPUActivity()
        instrumentation.record(.cpuTicks, elapsedMS: result.cpuStatsDurationMS)
        instrumentation.record(.cpuTemperature, elapsedMS: result.temperatureDurationMS)
        instrumentation.record(.gpuSample, elapsedMS: result.gpuDurationMS)

        latestCPUStats = result.stats
        cpuTemperature = result.temperature
        thermalState = result.thermalState
        latestGPUStats = result.gpuStats

        if let stats = result.stats {
            cpuHistory.append(stats.active)
            cpuStatsHistory.append(stats)
            trim(&cpuHistory, limit: 60)
            trim(&cpuStatsHistory, limit: 60)
        }

        thermalHistory.append(result.thermalState)
        trim(&thermalHistory, limit: 60)

        rebuildSnapshot()
        evaluateDiagnostics()

        let elapsedMS = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        instrumentation.record(.cpuPublish, elapsedMS: elapsedMS)
    }

    private func runCPUProcessesLane(force: Bool = false) async {
        guard !isCPUProcessesLaneRunning || force else { return }
        isCPUProcessesLaneRunning = true
        defer { isCPUProcessesLaneRunning = false }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        let result = await sampler.sampleTopCPUProcesses()

        if !result.processes.isEmpty {
            latestTopProcesses = result.processes
        }

        instrumentation.recordProcessEnumeration(
            durationMS: result.measurement.durationMS,
            processCount: result.measurement.processCount,
            pidInfoCalls: result.measurement.pidInfoCalls
        )

        rebuildSnapshot()
        evaluateDiagnostics()

        let elapsedMS = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        instrumentation.record(.topCPUProcesses, elapsedMS: elapsedMS)
    }

    private func rebuildSnapshot() {
        snapshot = SystemStatsSnapshot(
            cpuUsage: latestCPUStats?.active,
            cpuStats: latestCPUStats,
            memoryUsed: latestMemoryStats?.used ?? 0,
            memoryTotal: latestMemoryStats?.total ?? ProcessInfo.processInfo.physicalMemory,
            memoryStats: latestMemoryStats,
            topMemoryProcesses: latestTopMemoryProcesses,
            diskUsed: latestDiskUsed,
            diskTotal: latestDiskTotal,
            networkDownloadRate: latestNetworkDownloadRate,
            networkUploadRate: latestNetworkUploadRate,
            battery: latestBattery,
            gpuStats: latestGPUStats,
            topProcesses: latestTopProcesses,
            lastUpdated: Date()
        )
    }

    private func evaluateDiagnostics() {
        let input = diagnosticsMapper.map(
            snapshot: snapshot,
            cpuHistory: cpuHistory,
            thermalState: thermalState,
            thermalHistory: thermalHistory,
            memorySignalHistory: memorySignalHistory
        )

        let drafts = diagnosticsEngine.evaluate(input: input)
        let trackedState = diagnosticsTracker.apply(drafts: drafts, at: input.timestamp)
        activeIssues = trackedState.activeIssues
        recentIssues = trackedState.recentResolvedIssues

        if trackedState.didChange {
            Task { [weak self] in
                await self?.persistDiagnosticsState()
            }
        }
    }

    private func persistDiagnosticsState() async {
        let resolvedHistory = diagnosticsTracker.resolvedIssueHistory
        let active = Array(diagnosticsTracker.activeIssuesByType.values)
        await diagnosticsPersistence.save(active: active, resolved: resolvedHistory)
    }

    private func trim<T>(_ array: inout [T], limit: Int) {
        if array.count > limit {
            array.removeFirst(array.count - limit)
        }
    }

}

@MainActor
private final class LocationPermissionCoordinator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let onAuthorizationGranted: () -> Void

    init(onAuthorizationGranted: @escaping () -> Void) {
        self.onAuthorizationGranted = onAuthorizationGranted
        super.init()
        manager.delegate = self
    }

    func requestIfNeeded() {
        guard CLLocationManager.locationServicesEnabled() else { return }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            onAuthorizationGranted()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            onAuthorizationGranted()
        default:
            break
        }
    }
}

struct NetworkRateSample {
    let downloadRate: UInt64
    let uploadRate: UInt64
}
