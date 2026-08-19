import Foundation

enum CaptureStatus: Equatable, Sendable {
    case active
    case disabled
    case unavailable(String)

    var message: String {
        switch self {
        case .active:
            "Watching committed edits locally"
        case .disabled:
            "Learning is paused"
        case .unavailable(let message):
            message
        }
    }

    var isActive: Bool {
        self == .active
    }
}
