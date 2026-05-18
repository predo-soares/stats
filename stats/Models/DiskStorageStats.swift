import Foundation

struct DiskStorageCategoryStats: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var bytes: UInt64
    var systemImage: String
}

struct DiskStorageScanResult: Equatable {
    var categories: [DiskStorageCategoryStats]
    var scannedAt: Date
    var scannedBytes: UInt64
    var inaccessibleItemCount: Int
}
