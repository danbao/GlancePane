import AppKit
import Foundation

struct DisplayDescriptor: Equatable {
    let persistentID: String
    let displayID: CGDirectDisplayID
    let name: String
    let frame: CGRect
    let scaleFactor: CGFloat
    let isMain: Bool

    var id: String {
        persistentID
    }

    var logicalWidth: Int {
        Int(frame.width.rounded())
    }

    var logicalHeight: Int {
        Int(frame.height.rounded())
    }

    var logicalArea: CGFloat {
        frame.width * frame.height
    }

    var pixelWidth: Int {
        Int(frame.width * scaleFactor)
    }

    var pixelHeight: Int {
        Int(frame.height * scaleFactor)
    }

    var summary: String {
        "\(name) \(logicalWidth)x\(logicalHeight)\(isMain ? " main" : "")"
    }

    var settingsLabel: String {
        "\(name) · \(logicalWidth)×\(logicalHeight)\(isMain ? " · Main" : "")"
    }
}

extension NSScreen {
    var glancePaneDisplayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }

    var glancePanePersistentDisplayID: String {
        let displayID = glancePaneDisplayID
        guard displayID != 0,
              let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return "display-\(displayID)"
        }

        let uuid = unmanagedUUID.takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String
    }
}
