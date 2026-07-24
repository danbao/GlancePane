import AppKit

struct MouseClickShieldState {
    private(set) var leftStartedInside = false
    private(set) var rightStartedInside = false

    mutating func reset() {
        leftStartedInside = false
        rightStartedInside = false
    }

    mutating func shouldSwallow(eventType: NSEvent.EventType, isInside: Bool) -> Bool {
        switch eventType {
        case .leftMouseDown:
            leftStartedInside = isInside
            return isInside
        case .leftMouseDragged:
            return leftStartedInside
        case .leftMouseUp:
            let ownsSequence = leftStartedInside
            leftStartedInside = false
            return ownsSequence
        case .rightMouseDown:
            rightStartedInside = isInside
            return isInside
        case .rightMouseDragged:
            return rightStartedInside
        case .rightMouseUp:
            let ownsSequence = rightStartedInside
            rightStartedInside = false
            return ownsSequence
        default:
            return false
        }
    }
}
final class MouseClickShield {
    struct ScreenMapping {
        let quartzBounds: CGRect
        let appKitFrame: CGRect
    }

    private let lock = NSLock()
    private let handler: @MainActor (NSEvent.EventType, CGPoint) -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var windowFrame = CGRect.zero
    private var screenMappings: [ScreenMapping] = []
    private var isEnabled = true
    private var gestureState = MouseClickShieldState()

    init(handler: @escaping @MainActor (NSEvent.EventType, CGPoint) -> Void) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() -> Bool {
        stop()

        let mask = Self.eventMask([
            .leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp,
            .rightMouseDown,
            .rightMouseDragged,
            .rightMouseUp
        ])

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        runLoopSource = nil
        eventTap = nil

        lock.lock()
        gestureState.reset()
        lock.unlock()
    }

    func update(windowFrame: CGRect, screenMappings: [ScreenMapping], enabled: Bool) {
        lock.lock()
        self.windowFrame = windowFrame
        self.screenMappings = screenMappings
        isEnabled = enabled
        if !enabled {
            gestureState.reset()
        }
        lock.unlock()
    }

    private static func eventMask(_ types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << CGEventMask(type.rawValue))
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }

        let shield = Unmanaged<MouseClickShield>.fromOpaque(refcon).takeUnretainedValue()
        return shield.handle(type: type, event: event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let eventType = Self.nsEventType(for: type) else {
            return Unmanaged.passUnretained(event)
        }

        let location = appKitLocation(fromQuartzLocation: event.location)
        let shouldSwallow = shouldSwallow(eventType: eventType, location: location)

        if shouldSwallow {
            let handler = handler
            Task { @MainActor in
                handler(eventType, location)
            }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private static func nsEventType(for type: CGEventType) -> NSEvent.EventType? {
        switch type {
        case .leftMouseDown:
            return .leftMouseDown
        case .leftMouseDragged:
            return .leftMouseDragged
        case .leftMouseUp:
            return .leftMouseUp
        case .rightMouseDown:
            return .rightMouseDown
        case .rightMouseDragged:
            return .rightMouseDragged
        case .rightMouseUp:
            return .rightMouseUp
        default:
            return nil
        }
    }

    private func appKitLocation(fromQuartzLocation location: CGPoint) -> CGPoint {
        lock.lock()
        let mappings = screenMappings
        lock.unlock()

        guard let mapping = mappings.first(where: { $0.quartzBounds.contains(location) }) else {
            let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
            return CGPoint(x: location.x, y: mainHeight - location.y)
        }

        let relativeY = location.y - mapping.quartzBounds.minY
        return CGPoint(
            x: location.x,
            y: mapping.appKitFrame.maxY - relativeY
        )
    }

    private func shouldSwallow(eventType: NSEvent.EventType, location: CGPoint) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard isEnabled else {
            gestureState.reset()
            return false
        }

        let isInside = windowFrame.contains(location)
        return gestureState.shouldSwallow(eventType: eventType, isInside: isInside)
    }
}
