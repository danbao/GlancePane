import AppKit
import SwiftUI

func dashboardCompositionTestCases() -> [TestCase] {
    [
        TestCase("production dashboard composition renders every page") {
            try await testProductionDashboardCompositionPages()
        },
        TestCase("production dashboard composition applies dim and rest overlays") {
            try await testProductionDashboardCompositionOverlays()
        },
        TestCase("production dashboard composition scales and applies pixel shifts") {
            try await testProductionDashboardCompositionScaleAndOffset()
        }
    ]
}

@MainActor
private func testProductionDashboardCompositionPages() async throws {
    _ = NSApplication.shared
    for page in DashboardPage.defaultOrder {
        let representation = try renderDashboardComposition(
            DashboardPresentationState(config: .default, page: page)
        )
        try compositionExpect(representation.pixelsWide == 1280, "\(page) width must be 1280")
        try compositionExpect(representation.pixelsHigh == 720, "\(page) height must be 720")
        try compositionExpect(maxSampledLuminance(representation) > 0.03, "\(page) composition appears blank")
    }
}

@MainActor
private func testProductionDashboardCompositionOverlays() async throws {
    var state = DashboardPresentationState(config: .default, page: .weather)
    let base = try renderDashboardComposition(state)

    state.dimOpacity = 0.6
    let dimmed = try renderDashboardComposition(state)
    try compositionExpect(
        averageSampledLuminance(dimmed) < averageSampledLuminance(base) * 0.65,
        "dim overlay must darken the production composition"
    )

    state.isResting = true
    let resting = try renderDashboardComposition(state)
    try compositionExpect(maxSampledLuminance(resting) < 0.01, "rest overlay must cover the entire composition")
}

@MainActor
private func testProductionDashboardCompositionScaleAndOffset() async throws {
    var state = DashboardPresentationState(config: .default, page: .weather)
    let compact = try renderDashboardComposition(state, size: NSSize(width: 640, height: 360))
    try compositionExpect(compact.pixelsWide == 640, "scaled composition width must match its container")
    try compositionExpect(compact.pixelsHigh == 360, "scaled composition height must match its container")
    try compositionExpect(maxSampledLuminance(compact) > 0.03, "scaled composition appears blank")

    let centered = try renderDashboardComposition(state)
    state.contentOffset = CGSize(width: 24, height: -24)
    let shifted = try renderDashboardComposition(state)
    try compositionExpect(
        sampledLuminanceDifference(centered, shifted) > 0.01,
        "pixel-shift offset must move the production page content"
    )
}

@MainActor
private func renderDashboardComposition(
    _ state: DashboardPresentationState,
    size: NSSize = NSSize(width: 1280, height: 720)
) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(
        content: DashboardPresentationView(state: state)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)
    )
    renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
    renderer.scale = 1
    guard let image = renderer.nsImage,
          let data = image.tiffRepresentation,
          let representation = NSBitmapImageRep(data: data) else {
        throw TestFailure(message: "could not render dashboard composition", file: #fileID, line: #line)
    }
    return representation
}

private func averageSampledLuminance(_ image: NSBitmapImageRep) -> Double {
    let samples = sampledLuminances(image)
    return samples.reduce(0, +) / Double(max(1, samples.count))
}

private func maxSampledLuminance(_ image: NSBitmapImageRep) -> Double {
    sampledLuminances(image).max() ?? 0
}

private func sampledLuminanceDifference(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep) -> Double {
    let left = sampledLuminances(lhs)
    let right = sampledLuminances(rhs)
    return zip(left, right).reduce(0) { $0 + abs($1.0 - $1.1) } / Double(max(1, min(left.count, right.count)))
}

private func sampledLuminances(_ image: NSBitmapImageRep) -> [Double] {
    var values: [Double] = []
    for y in stride(from: 0, to: image.pixelsHigh, by: 12) {
        for x in stride(from: 0, to: image.pixelsWide, by: 12) {
            guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            values.append(0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent)
        }
    }
    return values
}

private func compositionExpect(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: String = #fileID,
    line: Int = #line
) throws {
    if !condition() {
        throw TestFailure(message: message, file: file, line: line)
    }
}
