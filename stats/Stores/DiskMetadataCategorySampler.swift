import Foundation

@MainActor
final class DiskMetadataCategorySampler {
    private let fileManager = FileManager.default
    private var activeDriver: DiskQueryDriver?

    func streamStorageBreakdown(used: UInt64, total: UInt64) -> AsyncStream<DiskStorageCategoryBreakdown> {
        activeDriver?.stop()

        let context = makeSearchContext()
        let driver = DiskQueryDriver(searchScopes: context.searchScopes)
        activeDriver = driver
        driver.start()

        let (stream, continuation) = AsyncStream<DiskStorageCategoryBreakdown>.makeStream()

        Task { @MainActor [weak self, weak driver] in
            guard let driver else {
                continuation.finish()
                return
            }
            for await entries in driver.entryStream {
                guard !entries.isEmpty else { continue }
                let breakdown = await Task.detached(priority: .utility) {
                    Self.buildBreakdown(from: entries, used: used, total: total, context: context)
                }.value
                continuation.yield(breakdown)
            }
            continuation.finish()
            if let self, self.activeDriver === driver {
                self.activeDriver = nil
            }
        }

        return stream
    }

    private func makeSearchContext() -> DiskMetadataSearchContext {
        let homePath = fileManager.homeDirectoryForCurrentUser.path

        let searchScopes = [
            fileManager.homeDirectoryForCurrentUser,
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Library/Developer", isDirectory: true)
        ].filter { fileManager.fileExists(atPath: $0.path) }

        return DiskMetadataSearchContext(
            searchScopes: searchScopes,
            homePath: homePath,
            trashPath: homePath + "/.Trash",
            developerPaths: [
                homePath + "/Developer",
                homePath + "/Library/Developer",
                "/Library/Developer"
            ],
            photoLibraryPath: homePath + "/Pictures/Photos Library.photoslibrary",
            picturesPath: homePath + "/Pictures",
            applicationsPaths: [
                homePath + "/Applications",
                "/Applications",
                "/System/Applications"
            ],
            iCloudDrivePath: homePath + "/Library/Mobile Documents/com~apple~CloudDocs"
        )
    }

    fileprivate static func extractEntries(from query: NSMetadataQuery) -> [DiskMetadataQueryEntry] {
        var entries: [DiskMetadataQueryEntry] = []
        entries.reserveCapacity(query.resultCount)

        for index in 0..<query.resultCount {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  let size = item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber else {
                continue
            }

            entries.append(DiskMetadataQueryEntry(path: path, size: size.uint64Value))
        }

        return entries
    }

    nonisolated private static func buildBreakdown(
        from entries: [DiskMetadataQueryEntry],
        used: UInt64,
        total: UInt64,
        context: DiskMetadataSearchContext
    ) -> DiskStorageCategoryBreakdown {
        var usageByCategory = Dictionary(
            uniqueKeysWithValues: DiskStorageCategoryKind.allCases.map { ($0, UInt64(0)) }
        )

        for entry in entries {
            guard let category = category(for: entry.path, context: context) else { continue }
            usageByCategory[category, default: 0] += entry.size
        }

        let accountedKinds: [DiskStorageCategoryKind] = [
            .applications,
            .trash,
            .documents,
            .photos,
            .developer
        ]
        let accountedBytes = accountedKinds.reduce(UInt64(0)) { partialResult, kind in
            partialResult + (usageByCategory[kind] ?? 0)
        }

        usageByCategory[.systemData] = used > accountedBytes ? used - accountedBytes : 0

        let categories: [DiskStorageCategoryUsage] = DiskStorageCategoryKind.allCases.compactMap { kind in
            let bytes = usageByCategory[kind] ?? 0
            guard bytes > 0 else { return nil }
            return DiskStorageCategoryUsage(kind: kind, bytes: bytes)
        }

        return DiskStorageCategoryBreakdown(
            categories: categories,
            usedBytes: used,
            totalBytes: total,
            scannedAt: Date()
        )
    }

    nonisolated private static func category(
        for path: String,
        context: DiskMetadataSearchContext
    ) -> DiskStorageCategoryKind? {
        if path == context.trashPath || path.hasPrefix(context.trashPath + "/") {
            return .trash
        }

        if context.developerPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) ||
            isDeveloperApplicationPath(path) {
            return .developer
        }

        if path == context.photoLibraryPath ||
            path.hasPrefix(context.photoLibraryPath + "/") ||
            path == context.picturesPath ||
            path.hasPrefix(context.picturesPath + "/") {
            return .photos
        }

        if context.applicationsPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return .applications
        }

        if path == context.iCloudDrivePath || path.hasPrefix(context.iCloudDrivePath + "/") {
            return .documents
        }

        if path == context.homePath || path.hasPrefix(context.homePath + "/") {
            let relativePath = String(path.dropFirst(context.homePath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relativePath.isEmpty else { return nil }

            let firstComponent = relativePath.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
            let excludedRootDirectories: Set<String> = [
                ".Trash",
                "Applications",
                "Developer",
                "Library",
                "Pictures"
            ]

            if !excludedRootDirectories.contains(firstComponent) {
                return .documents
            }
        }

        return nil
    }

    nonisolated private static func isDeveloperApplicationPath(_ path: String) -> Bool {
        let developerAppMarkers = [
            "/Applications/Xcode.app",
            "/Applications/Simulator.app",
            "/Applications/Instruments.app"
        ]

        return developerAppMarkers.contains(where: { path == $0 || path.hasPrefix($0 + "/") })
    }
}

private struct DiskMetadataQueryEntry: Sendable {
    let path: String
    let size: UInt64
}

private struct DiskMetadataSearchContext: Sendable {
    let searchScopes: [URL]
    let homePath: String
    let trashPath: String
    let developerPaths: [String]
    let photoLibraryPath: String
    let picturesPath: String
    let applicationsPaths: [String]
    let iCloudDrivePath: String
}

@MainActor
private final class DiskQueryDriver: NSObject {
    private(set) var entryStream: AsyncStream<[DiskMetadataQueryEntry]>
    private let continuation: AsyncStream<[DiskMetadataQueryEntry]>.Continuation
    private let query: NSMetadataQuery
    private var finished = false

    init(searchScopes: [URL]) {
        let q = NSMetadataQuery()
        q.searchScopes = searchScopes
        q.predicate = NSPredicate(format: "%K > 0", NSMetadataItemFSSizeKey)
        q.notificationBatchingInterval = 0.25
        query = q
        (entryStream, continuation) = AsyncStream.makeStream()
        super.init()
    }

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUpdate),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFinish),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        guard query.start() else {
            stop()
            return
        }
    }

    @objc private func handleUpdate() {
        guard !finished else { return }
        query.disableUpdates()
        let entries = DiskMetadataCategorySampler.extractEntries(from: query)
        query.enableUpdates()
        continuation.yield(entries)
    }

    @objc private func handleFinish() {
        guard !finished else { return }
        finished = true
        NotificationCenter.default.removeObserver(self)
        query.disableUpdates()
        let entries = DiskMetadataCategorySampler.extractEntries(from: query)
        query.stop()
        continuation.yield(entries)
        continuation.finish()
    }

    func stop() {
        guard !finished else { return }
        finished = true
        NotificationCenter.default.removeObserver(self)
        query.disableUpdates()
        query.stop()
        continuation.finish()
    }
}
