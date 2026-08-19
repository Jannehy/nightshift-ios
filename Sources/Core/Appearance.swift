import SwiftUI

/// The app's accent colour. Purely a client-side preference – it is stored on
/// the device, not in the server's config, so two people using the same
/// Nightshift can pick different colours.
@MainActor
final class Appearance: ObservableObject {
    static let shared = Appearance()

    @Published var accentHex: String {
        didSet { UserDefaults.standard.set(accentHex, forKey: Self.key) }
    }

    private static let key = "nightshift.accentHex"

    /// The web UI's night-shift accent (`--accent` in `static/style.css`).
    static let defaultHex = "FFB03A"

    private init() {
        accentHex = UserDefaults.standard.string(forKey: Self.key) ?? Self.defaultHex
    }

    /// A stored colour that matches a swatch is resolved through it, so the
    /// brand orange can adapt to light and dark like it does on the web.
    var accent: Color {
        if let swatch = Self.swatches.first(where: {
            $0.hex.caseInsensitiveCompare(accentHex) == .orderedSame
        }) {
            return swatch.color
        }
        return Color(hex: accentHex) ?? .orange
    }

    /// Binding for the system colour picker, which hands back arbitrary colours.
    var customColor: Binding<Color> {
        Binding(get: { self.accent },
                set: { self.accentHex = $0.hexString ?? Self.defaultHex })
    }

    func isSelected(_ swatch: AccentSwatch) -> Bool {
        swatch.hex.caseInsensitiveCompare(accentHex) == .orderedSame
    }

    static let swatches: [AccentSwatch] = [
        // Both tones straight from the web UI's day and night themes.
        AccentSwatch(name: "Nightshift", hex: "FFB03A", lightHex: "E8930C"),
        AccentSwatch(name: "Indigo", hex: "5856D6"),
        AccentSwatch(name: "Blue", hex: "0A84FF"),
        AccentSwatch(name: "Teal", hex: "30B0C7"),
        AccentSwatch(name: "Green", hex: "34C759"),
        AccentSwatch(name: "Red", hex: "FF3B30"),
        AccentSwatch(name: "Pink", hex: "FF375F"),
        AccentSwatch(name: "Purple", hex: "AF52DE"),
    ]
}

struct AccentSwatch: Identifiable, Hashable {
    let name: String
    /// Stored value, and the tone used on dark backgrounds.
    let hex: String
    /// Optional darker variant for light mode – a colour bright enough to sit
    /// on black is usually too pale on white.
    var lightHex: String?

    var id: String { hex }

    var color: Color {
        guard let lightHex,
              let light = UIColor(hex: lightHex),
              let dark = UIColor(hex: hex) else {
            return Color(hex: hex) ?? .orange
        }
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

extension Color {
    /// Accepts "RRGGBB" with or without a leading "#".
    init?(hex: String) {
        guard let color = UIColor(hex: hex) else { return nil }
        self.init(color)
    }

    /// Round-trips a colour picked with the system picker back into storage.
    var hexString: String? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let clamp = { (v: CGFloat) in Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}

extension UIColor {
    convenience init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}
