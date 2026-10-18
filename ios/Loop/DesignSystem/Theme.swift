import SwiftUI

/// Design tokens from .plans/ios-app-ux-spec.md §2: monochrome, Apple-native, light mode only.
/// The photos carry the color; the only other colors are system ones for status.
enum Theme {
    // Color
    static let accent = Color.black

    /// Loop Lime #C7E75A, the brand accent. This is the only place the value is written down.
    /// Use it sparingly (Scan button, welcome mark, publish and completion moments, "You" markers),
    /// and always put near-black (`onLime`) on top of it.
    static let lime = Color(red: 199.0 / 255.0, green: 231.0 / 255.0, blue: 90.0 / 255.0)
    /// Near-black #191919: the logo's background, editorial text on the welcome screen, and text on lime.
    static let ink = Color(red: 25.0 / 255.0, green: 25.0 / 255.0, blue: 25.0 / 255.0)
    /// Secondary and placeholder text on the welcome screen: ink at 72% is about 7:1 on the warm background.
    static let inkSecondary = ink.opacity(0.72)
    /// Placeholder text in a field: ink at 62% is about 4.5:1 on `surface`.
    static let inkPlaceholder = ink.opacity(0.62)
    /// Text and icons on lime.
    static let onLime = ink
    static let background = Color(red: 0.980, green: 0.973, blue: 0.957)   // warm off-white #FAF8F4
    static let surface = Color(red: 0.941, green: 0.929, blue: 0.906)      // warm gray #F0EDE7
    static let textPrimary = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let hairline = Color(uiColor: .separator)
    static let success = Color(uiColor: .systemGreen)
    static let destructive = Color(uiColor: .systemRed)
    static let warning = Color(uiColor: .systemOrange)

    // Spacing scale
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    /// Screen side margins and grid gutter.
    static let margin: CGFloat = 16
    static let gutter: CGFloat = 12

    // Corner radius
    enum Radius {
        static let card: CGFloat = 12
        static let field: CGFloat = 10
        static let sheet: CGFloat = 20
    }

    /// Feed photos are a uniform 4:5.
    static let photoAspect: CGFloat = 4.0 / 5.0
}

extension Font {
    /// SF Pro Rounded for big numbers (impact, counts, leaderboard ranks).
    static func roundedNumber(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

extension View {
    /// The warm off-white page background, behind scroll views, lists, and forms.
    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }

    func cardBackground() -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}
