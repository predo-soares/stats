import Foundation

enum DiskStorageCategoryKind: String, CaseIterable, Equatable, Codable {
    case applications
    case trash
    case documents
    case photos
    case developer
    case systemData

    var title: String {
        switch self {
        case .applications:
            return "Applications"
        case .trash:
            return "Trash"
        case .documents:
            return "Documents"
        case .photos:
            return "Photos"
        case .developer:
            return "Developer"
        case .systemData:
            return "System Data"
        }
    }
}

struct DiskStorageCategoryUsage: Identifiable, Equatable, Codable {
    var id: DiskStorageCategoryKind { kind }
    var kind: DiskStorageCategoryKind
    var bytes: UInt64
}

struct DiskStorageCategoryBreakdown: Equatable, Codable {
    var categories: [DiskStorageCategoryUsage]
    var usedBytes: UInt64
    var totalBytes: UInt64
    var scannedAt: Date

    var availableBytes: UInt64 {
        totalBytes > usedBytes ? totalBytes - usedBytes : 0
    }
}

enum DiskStorageNodeKind: String, Equatable {
    case folder
    case files
    case other
}

struct DiskStorageNode: Identifiable, Equatable {
    var id: String { "\(kind.rawValue):\(path)" }
    var title: String
    var path: String
    var bytes: UInt64
    var systemImage: String
    var kind: DiskStorageNodeKind
    var children: [DiskStorageNode] = []

    var isDrillDownEnabled: Bool {
        kind == .folder && !children.isEmpty
    }
}

struct DiskStorageScanResult: Equatable {
    var root: DiskStorageNode
    var scannedAt: Date
    var scannedBytes: UInt64
    var inaccessibleItemCount: Int
}
