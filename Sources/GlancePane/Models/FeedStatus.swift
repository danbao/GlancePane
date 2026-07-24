import Foundation

enum FeedStatus: Equatable {
    case loading
    case refreshing
    case live
    case partial
    case cached
    case offline
    case setup
    case hidden
    case disabled

    var title: String {
        switch self {
        case .loading: return "Loading"
        case .refreshing: return "Refreshing"
        case .live: return "Live"
        case .partial: return "Partial"
        case .cached: return "Cached"
        case .offline: return "Offline"
        case .setup: return "Setup"
        case .hidden: return "Hidden"
        case .disabled: return "Disabled"
        }
    }
}
