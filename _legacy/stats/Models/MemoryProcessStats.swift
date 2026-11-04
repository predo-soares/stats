import Foundation

struct MemoryProcessStats: Identifiable, Equatable {
    var id: Int32 { pid }
    var pid: Int32
    var name: String
    var memoryBytes: UInt64
}
