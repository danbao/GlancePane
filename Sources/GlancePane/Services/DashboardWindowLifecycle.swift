import Foundation

enum DashboardWindowLifecycleEvent {
    case repositionRequested
    case targetUnavailable
    case sessionResigned
    case sessionBecameActive
    case screensSlept
    case screensWoke
    case screenLockChanged(Bool)
}

enum DashboardWindowLifecycleAction: Equatable {
    case hide
    case reposition
    case repositionAndShow
}

struct DashboardWindowLifecycleState {
    private(set) var isSessionActive: Bool
    private(set) var areScreensAwake: Bool
    private(set) var hasPendingReposition: Bool
    private(set) var isWindowPresented: Bool
    private(set) var isScreenLocked: Bool

    init(
        isSessionActive: Bool = true,
        areScreensAwake: Bool = true,
        hasPendingReposition: Bool = true,
        isWindowPresented: Bool = false,
        isScreenLocked: Bool = false
    ) {
        self.isSessionActive = isSessionActive
        self.areScreensAwake = areScreensAwake
        self.hasPendingReposition = hasPendingReposition
        self.isWindowPresented = isWindowPresented
        self.isScreenLocked = isScreenLocked
    }

    var canPresentWindow: Bool {
        isSessionActive && areScreensAwake && !isScreenLocked
    }

    mutating func handle(_ event: DashboardWindowLifecycleEvent) -> [DashboardWindowLifecycleAction] {
        switch event {
        case .repositionRequested:
            hasPendingReposition = true
            return presentIfAllowed()

        case .targetUnavailable:
            hasPendingReposition = true
            guard isWindowPresented else { return [] }
            isWindowPresented = false
            return [.hide]

        case .sessionResigned:
            isSessionActive = false
            return suspendPresentation()

        case .sessionBecameActive:
            isSessionActive = true
            return presentIfAllowed()

        case .screensSlept:
            areScreensAwake = false
            return suspendPresentation()

        case .screensWoke:
            areScreensAwake = true
            return presentIfAllowed()

        case .screenLockChanged(let isLocked):
            guard isScreenLocked != isLocked else { return [] }
            isScreenLocked = isLocked
            return isLocked ? suspendPresentation() : presentIfAllowed()
        }
    }

    private mutating func suspendPresentation() -> [DashboardWindowLifecycleAction] {
        hasPendingReposition = true
        guard isWindowPresented else { return [] }
        isWindowPresented = false
        return [.hide]
    }

    private mutating func presentIfAllowed() -> [DashboardWindowLifecycleAction] {
        guard canPresentWindow, hasPendingReposition else { return [] }
        hasPendingReposition = false
        let action: DashboardWindowLifecycleAction = isWindowPresented ? .reposition : .repositionAndShow
        isWindowPresented = true
        return [action]
    }
}
