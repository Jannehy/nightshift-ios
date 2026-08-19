import SwiftUI

/// One selectable app icon. `alternateName` is what iOS switches on; nil is the
/// primary icon from the asset catalog.
struct AppIconOption: Identifiable, Hashable {
    let label: String
    let alternateName: String?
    let hex: String

    var id: String { alternateName ?? "primary" }
    var color: Color { Color(hex: hex) ?? .orange }
}

/// Switches the home-screen icon.
///
/// Deliberately separate from the accent colour: iOS shows a system alert on
/// every icon change, which would be unbearable while tapping through the
/// accent swatches. Icons cannot be produced at runtime either – every variant
/// is a PNG shipped in the bundle and declared in `Info.plist`.
@MainActor
final class AppIconManager: ObservableObject {
    static let shared = AppIconManager()

    @Published private(set) var current: AppIconOption
    @Published var errorMessage: String?

    static let options: [AppIconOption] = [
        AppIconOption(label: "Nightshift", alternateName: nil, hex: "FFB03A"),
        AppIconOption(label: "Indigo", alternateName: "Indigo", hex: "5856D6"),
        AppIconOption(label: "Blue", alternateName: "Blue", hex: "0A84FF"),
        AppIconOption(label: "Teal", alternateName: "Teal", hex: "30B0C7"),
        AppIconOption(label: "Green", alternateName: "Green", hex: "34C759"),
        AppIconOption(label: "Red", alternateName: "Red", hex: "FF3B30"),
        AppIconOption(label: "Pink", alternateName: "Pink", hex: "FF375F"),
        AppIconOption(label: "Purple", alternateName: "Purple", hex: "AF52DE"),
    ]

    var isSupported: Bool { UIApplication.shared.supportsAlternateIcons }

    private init() {
        let name = UIApplication.shared.alternateIconName
        current = Self.options.first { $0.alternateName == name } ?? Self.options[0]
    }

    func select(_ option: AppIconOption) {
        guard option.id != current.id else { return }
        guard isSupported else {
            errorMessage = NSLocalizedString("This device cannot change the app icon.",
                                             comment: "")
            return
        }
        UIApplication.shared.setAlternateIconName(option.alternateName) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                } else {
                    self.current = option
                }
            }
        }
    }
}
