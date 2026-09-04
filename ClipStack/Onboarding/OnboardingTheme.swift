import AppKit
import SwiftUI

enum OnboardingStrings {
    static let table = "Onboarding"

    static func string(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: table)
    }

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), arguments: arguments)
    }
}

extension Text {
    /// Every onboarding string lives in `Onboarding.strings`, never in the default table.
    init(onboarding key: String) {
        self.init(LocalizedStringKey(key), tableName: OnboardingStrings.table)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension NSColor {
    static func onboardingDynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

/// Chrome of the onboarding window itself: semantic system colors only.
enum OnboardingChrome {
    static let label = Color(nsColor: .labelColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let tertiary = Color(nsColor: .tertiaryLabelColor)
    static let separator = Color(nsColor: .separatorColor)
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    /// `NSColor.quaternarySystemFill` is macOS 14+; these are the same quaternary fills, drawn
    /// from the label color so they still follow the system appearance on macOS 13.
    static let hoverFill = Color(nsColor: .onboardingDynamic(light: NSColor(white: 0, alpha: 0.045),
                                                             dark: NSColor(white: 1, alpha: 0.06)))
    static let cardFill = Color(nsColor: .onboardingDynamic(light: NSColor(white: 0, alpha: 0.09),
                                                            dark: NSColor(white: 1, alpha: 0.12)))

    /// SPEC §4: `.controlBackgroundColor` in light, #454547 in dark — the system control background
    /// is near-black in dark aqua and would read as a hole instead of a key cap.
    static let keyCapFill = Color(nsColor: .onboardingDynamic(light: .controlBackgroundColor,
                                                              dark: NSColor(srgbRed: 0x45 / 255, green: 0x45 / 255, blue: 0x47 / 255, alpha: 1)))
    static let keyCapHairline = Color(nsColor: .onboardingDynamic(light: NSColor(white: 0, alpha: 0.08),
                                                                  dark: NSColor(white: 1, alpha: 0.12)))
    static let keyCapShadow = Color(nsColor: .onboardingDynamic(light: NSColor(white: 0, alpha: 0.18),
                                                                dark: NSColor(white: 0, alpha: 0.60)))

    /// The app-icon gradient, reused for the Welcome icon and the ClipStack row in the settings scene.
    static let iconGradient = LinearGradient(colors: [Color(hex: 0x3D9CFF), Color(hex: 0x0A6FE6)],
                                             startPoint: .top, endPoint: .bottom)
}

/// Tokens for the simulated desktop *inside* the laptop screen. These stand in for another app's
/// chrome, so they carry the artboard's literal values rather than this app's semantic colors.
enum SceneTheme {
    static let windowBackground = Color(nsColor: .onboardingDynamic(light: NSColor(srgbRed: 0xEC / 255, green: 0xEC / 255, blue: 0xEC / 255, alpha: 1),
                                                                    dark: NSColor(srgbRed: 0x2A / 255, green: 0x2A / 255, blue: 0x2C / 255, alpha: 1)))
    static let label = Color(nsColor: .onboardingDynamic(light: NSColor(white: 0, alpha: 0.85),
                                                         dark: NSColor(white: 1, alpha: 0.85)))
    static let secondaryLabel = Color(nsColor: .onboardingDynamic(light: NSColor(white: 0, alpha: 0.50),
                                                                  dark: NSColor(white: 1, alpha: 0.55)))
    static let quaternaryFill = Color(nsColor: .onboardingDynamic(light: NSColor(white: 0, alpha: 0.045),
                                                                  dark: NSColor(white: 1, alpha: 0.06)))
    static let tertiaryFill = Color(nsColor: .onboardingDynamic(light: NSColor(white: 0, alpha: 0.09),
                                                                dark: NSColor(white: 1, alpha: 0.12)))
    static let separator = Color(nsColor: .onboardingDynamic(light: NSColor(white: 0, alpha: 0.10),
                                                             dark: NSColor(white: 1, alpha: 0.12)))
    static let control = Color(nsColor: .onboardingDynamic(light: .white,
                                                           dark: NSColor(srgbRed: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255, alpha: 1)))
    static let glass = Color(nsColor: .onboardingDynamic(light: NSColor(srgbRed: 244 / 255, green: 244 / 255, blue: 246 / 255, alpha: 0.90),
                                                         dark: NSColor(srgbRed: 46 / 255, green: 46 / 255, blue: 48 / 255, alpha: 0.90)))
    static let hairline = Color(nsColor: .onboardingDynamic(light: NSColor(white: 0, alpha: 0.08),
                                                            dark: NSColor(white: 1, alpha: 0.12)))
    static let desk = Color(nsColor: .onboardingDynamic(light: NSColor(srgbRed: 0xC7 / 255, green: 0xD3 / 255, blue: 0xDF / 255, alpha: 1),
                                                        dark: NSColor(srgbRed: 0x2B / 255, green: 0x34 / 255, blue: 0x41 / 255, alpha: 1)))
    static let sidebarBackground = Color(nsColor: .onboardingDynamic(light: NSColor(white: 1, alpha: 0.55),
                                                                     dark: NSColor(white: 0, alpha: 0.18)))
    static let menuBarForeground = Color(nsColor: .onboardingDynamic(light: NSColor(white: 0, alpha: 0.85), dark: .white))
    static let menuBarHighlight = Color(nsColor: .onboardingDynamic(light: NSColor(white: 0, alpha: 0.12),
                                                                    dark: NSColor(white: 1, alpha: 0.22)))

    /// Accent at 16% in light, 24% in dark (SPEC §3, selected Quick Paste row).
    static func accentWash(_ scheme: ColorScheme) -> Color {
        Color.accentColor.opacity(scheme == .dark ? 0.24 : 0.16)
    }
}

/// `UnevenRoundedRectangle` is macOS 14+; ClipStack ships to macOS 13.
struct UnevenRoundedRect: Shape, InsettableShape {
    var topLeading: CGFloat = 0
    var topTrailing: CGFloat = 0
    var bottomLeading: CGFloat = 0
    var bottomTrailing: CGFloat = 0
    var insetAmount: CGFloat = 0

    init(topLeading: CGFloat = 0, topTrailing: CGFloat = 0, bottomLeading: CGFloat = 0, bottomTrailing: CGFloat = 0) {
        self.topLeading = topLeading
        self.topTrailing = topTrailing
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
    }

    func inset(by amount: CGFloat) -> UnevenRoundedRect {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let limit = min(r.width, r.height) / 2
        let tl = min(topLeading, limit), tr = min(topTrailing, limit)
        let bl = min(bottomLeading, limit), br = min(bottomTrailing, limit)

        var path = Path()
        path.move(to: CGPoint(x: r.minX + tl, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
        path.addArc(center: CGPoint(x: r.maxX - tr, y: r.minY + tr), radius: tr,
                    startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        path.addArc(center: CGPoint(x: r.maxX - br, y: r.maxY - br), radius: br,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
        path.addArc(center: CGPoint(x: r.minX + bl, y: r.maxY - bl), radius: bl,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + tl))
        path.addArc(center: CGPoint(x: r.minX + tl, y: r.minY + tl), radius: tl,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

extension View {
    /// `onChange(of:initial:_:)` is macOS 14+; the single-argument form is deprecated there.
    @ViewBuilder
    func onValueChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { _, newValue in action(newValue) }
        } else {
            self.onChange(of: value, perform: action)
        }
    }
}

/// Backdrop for the Quick Paste panel and the popover: the artboard's blurred, 90 % tinted glass.
/// macOS 26 draws real Liquid Glass and only needs a light tint to stay legible at demo scale.
struct GlassPanelBackground<S: Shape>: View {
    let shape: S

    var body: some View {
        ZStack {
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: shape)
                shape.fill(SceneTheme.glass.opacity(0.35))
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(SceneTheme.glass)
            }
        }
    }
}
