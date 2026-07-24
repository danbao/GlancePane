import AppKit

enum DisplaySelectionReason: String, Equatable {
    case automaticSmallest
    case configuredID
    case legacyName
}

enum DisplayWaitReason: Equatable {
    case secondaryUnavailable
    case selectedUnavailable
    case ambiguousLegacyName

    var statusText: String {
        switch self {
        case .secondaryUnavailable:
            return "Waiting for secondary display"
        case .selectedUnavailable:
            return "Waiting for selected display"
        case .ambiguousLegacyName:
            return "Select display again (duplicate name)"
        }
    }
}

enum DisplaySelectionResult: Equatable {
    case selected(DisplayDescriptor, DisplaySelectionReason)
    case waiting(DisplayWaitReason)
}

enum DisplaySelector {
    static func select(config: DisplayConfig, from displays: [DisplayDescriptor]) -> DisplaySelectionResult {
        if let targetID = config.targetID, !targetID.isEmpty {
            guard let selected = displays.first(where: { $0.persistentID == targetID }) else {
                return .waiting(.selectedUnavailable)
            }
            return .selected(selected, .configuredID)
        }

        let targetName = config.targetName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !targetName.isEmpty {
            let matches = displays.filter {
                $0.name.compare(targetName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
            guard matches.count == 1, let selected = matches.first else {
                return .waiting(matches.isEmpty ? .selectedUnavailable : .ambiguousLegacyName)
            }
            return .selected(selected, .legacyName)
        }

        guard let selected = displays
            .filter({ !$0.isMain })
            .sorted(by: automaticDisplayOrder)
            .first else {
            return .waiting(.secondaryUnavailable)
        }
        return .selected(selected, .automaticSmallest)
    }

    private static func automaticDisplayOrder(_ lhs: DisplayDescriptor, _ rhs: DisplayDescriptor) -> Bool {
        if lhs.logicalArea != rhs.logicalArea {
            return lhs.logicalArea < rhs.logicalArea
        }

        let targetAspect = 16.0 / 9.0
        let lhsAspectDelta = abs(Double(lhs.frame.width / max(lhs.frame.height, 1)) - targetAspect)
        let rhsAspectDelta = abs(Double(rhs.frame.width / max(rhs.frame.height, 1)) - targetAspect)
        if lhsAspectDelta != rhsAspectDelta {
            return lhsAspectDelta < rhsAspectDelta
        }
        if lhs.frame.width != rhs.frame.width {
            return lhs.frame.width < rhs.frame.width
        }
        return lhs.persistentID < rhs.persistentID
    }
}

enum ManagedDisplaySelection {
    case selected(screen: NSScreen, descriptor: DisplayDescriptor, reason: DisplaySelectionReason)
    case waiting(DisplayWaitReason)
}

@MainActor
final class DisplayManager {
    func displays() -> [DisplayDescriptor] {
        NSScreen.screens.map { screen in
            descriptor(for: screen)
        }
    }

    func selectDisplay(config: DisplayConfig) -> ManagedDisplaySelection {
        let screens = NSScreen.screens
        let descriptors = screens.map(descriptor(for:))
        switch DisplaySelector.select(config: config, from: descriptors) {
        case .selected(let selected, let reason):
            guard let screen = screens.first(where: { $0.glancePaneDisplayID == selected.displayID }) else {
                return .waiting(config.targetID == nil && config.targetName.isEmpty
                    ? .secondaryUnavailable
                    : .selectedUnavailable)
            }
            return .selected(screen: screen, descriptor: selected, reason: reason)
        case .waiting(let reason):
            return .waiting(reason)
        }
    }

    func descriptor(for screen: NSScreen) -> DisplayDescriptor {
        let displayID = screen.glancePaneDisplayID
        return DisplayDescriptor(
            persistentID: screen.glancePanePersistentDisplayID,
            displayID: displayID,
            name: screen.localizedName,
            frame: screen.frame,
            scaleFactor: screen.backingScaleFactor,
            isMain: displayID == CGMainDisplayID()
        )
    }
}
