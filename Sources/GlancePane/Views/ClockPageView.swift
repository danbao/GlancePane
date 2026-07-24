import SwiftUI

struct ClockPageView: View {
    let date: Date
    let theme: ScreenTheme
    let scale: CGFloat

    private var timeParts: [String] {
        Array(DateFormatter.cached(format: "HHmm").string(from: date)).map(String.init)
    }

    var body: some View {
        GeometryReader { proxy in
            let digitWidth = min(288 * scale, proxy.size.width * 0.225)
            let digitHeight = min(proxy.size.height * 0.64, digitWidth * 1.48)
            let seamRatio = 0.54

            ZStack {
                Color.black

                VStack(spacing: 18 * scale) {
                    Spacer(minLength: 0)

                    HStack(alignment: .center, spacing: 48 * scale) {
                        HeroTimeGroup(
                            digits: [timeParts[safe: 0] ?? "0", timeParts[safe: 1] ?? "0"],
                            digitWidth: digitWidth,
                            digitHeight: digitHeight,
                            seamRatio: seamRatio,
                            scale: scale
                        )

                        HeroTimeGroup(
                            digits: [timeParts[safe: 2] ?? "0", timeParts[safe: 3] ?? "0"],
                            digitWidth: digitWidth,
                            digitHeight: digitHeight,
                            seamRatio: seamRatio,
                            scale: scale
                        )
                    }

                    Text(DateFormatter.cached(format: "EEEE, MMMM d").string(from: date).uppercased())
                        .font(.system(size: 24 * scale, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .tracking(2.5 * scale)

                    Spacer(minLength: 0)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

private struct HeroTimeGroup: View {
    let digits: [String]
    let digitWidth: CGFloat
    let digitHeight: CGFloat
    let seamRatio: CGFloat
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 2 * scale) {
            HeroFlipDigitView(digit: digits[safe: 0] ?? "0", width: digitWidth, height: digitHeight, seamRatio: seamRatio)
            HeroFlipDigitView(digit: digits[safe: 1] ?? "0", width: digitWidth, height: digitHeight, seamRatio: seamRatio)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.72))
                .frame(height: max(1.2, 1.4 * scale))
                .offset(y: digitHeight * seamRatio)
        }
        .frame(width: digitWidth * 2 + 2 * scale, height: digitHeight)
    }
}

private struct HeroFlipDigitView: View {
    let digit: String
    let width: CGFloat
    let height: CGFloat
    let seamRatio: CGFloat

    @State private var displayedDigit: String
    @State private var previousDigit: String
    @State private var flipProgress = 1.0

    init(digit: String, width: CGFloat, height: CGFloat, seamRatio: CGFloat) {
        self.digit = digit
        self.width = width
        self.height = height
        self.seamRatio = seamRatio
        _displayedDigit = State(initialValue: digit)
        _previousDigit = State(initialValue: digit)
    }

    var body: some View {
        ZStack {
            FlipDigitFace(digit: flipProgress < 0.5 ? previousDigit : displayedDigit, width: width, height: height, seamRatio: seamRatio)

            if flipProgress < 0.5 {
                FlipDigitHalf(digit: previousDigit, width: width, height: height, seamRatio: seamRatio, half: .top)
                    .rotation3DEffect(
                        .degrees(-180 * flipProgress),
                        axis: (x: 1, y: 0, z: 0),
                        anchor: UnitPoint(x: 0.5, y: seamRatio),
                        perspective: 0.7
                    )
                    .zIndex(2)
            }

            if flipProgress >= 0.5 && flipProgress < 1 {
                FlipDigitHalf(digit: displayedDigit, width: width, height: height, seamRatio: seamRatio, half: .bottom)
                    .rotation3DEffect(
                        .degrees(180 - 180 * flipProgress),
                        axis: (x: 1, y: 0, z: 0),
                        anchor: UnitPoint(x: 0.5, y: seamRatio),
                        perspective: 0.7
                    )
                    .zIndex(2)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .onChange(of: digit) { _, newDigit in
            startFlip(to: newDigit)
        }
    }

    private func startFlip(to newDigit: String) {
        guard newDigit != displayedDigit else { return }

        previousDigit = displayedDigit
        displayedDigit = newDigit
        flipProgress = 0

        withAnimation(.easeIn(duration: 0.18)) {
            flipProgress = 0.5
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeOut(duration: 0.26)) {
                flipProgress = 1
            }
        }
    }
}

private enum FlipDigitHalfKind {
    case top
    case bottom
}

private struct FlipDigitHalf: View {
    let digit: String
    let width: CGFloat
    let height: CGFloat
    let seamRatio: CGFloat
    let half: FlipDigitHalfKind

    var body: some View {
        let topHeight = height * seamRatio
        let bottomHeight = height - topHeight
        let halfHeight = half == .top ? topHeight : bottomHeight

        FlipDigitFace(digit: digit, width: width, height: height, seamRatio: seamRatio)
            .frame(width: width, height: halfHeight, alignment: half == .top ? .top : .bottom)
            .clipped()
            .frame(width: width, height: height, alignment: half == .top ? .top : .bottom)
    }
}

private struct FlipDigitFace: View {
    let digit: String
    let width: CGFloat
    let height: CGFloat
    let seamRatio: CGFloat

    private let digitFontName = "Oswald-Bold"

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Color.white.opacity(0.006)
                    .frame(height: height * seamRatio)
                Color.clear
            }
            Text(digit)
                .font(.custom(digitFontName, size: height * 0.96))
                .foregroundStyle(Color(red: 0.72, green: 0.72, blue: 0.72))
                .monospacedDigit()
                .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                .offset(y: -height * 0.006)
        }
        .frame(width: width, height: height)
    }
}
