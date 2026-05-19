import Foundation

@MainActor
final class DiskCategoryBreakdownCache {
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("stats", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("disk_category_breakdown.json")
    }

    func load() -> DiskStorageCategoryBreakdown? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(DiskStorageCategoryBreakdown.self, from: data)
    }

    func save(_ breakdown: DiskStorageCategoryBreakdown) {
        guard let data = try? JSONEncoder().encode(breakdown) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
