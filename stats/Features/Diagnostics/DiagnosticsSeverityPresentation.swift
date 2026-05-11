import SwiftUI

extension DiagnosticsIssueSeverity {
    var color: Color {
        switch self {
        case .warning:
            return .yellow
        case .critical:
            return .red
        }
    }
}
