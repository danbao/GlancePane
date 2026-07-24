import AppKit
import Foundation

struct DisplayDescriptor: Equatable {
    let id: String
    let name: String
    let frame: CGRect
    let scaleFactor: CGFloat
    let isMain: Bool

    var pixelWidth: Int {
        Int(frame.width * scaleFactor)
    }

    var pixelHeight: Int {
        Int(frame.height * scaleFactor)
    }

    var summary: String {
        "\(name) \(pixelWidth)x\(pixelHeight)\(isMain ? " main" : "")"
    }
}

extension NSScreen {
    var smartScreenDisplayID: String {
        let value = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        return "\(value)"
    }
}
