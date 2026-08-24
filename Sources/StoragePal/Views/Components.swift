import SwiftUI

extension Color {
    static let palInk = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.94, green: 0.96, blue: 0.97, alpha: 1.0)
            : NSColor(red: 0.10, green: 0.13, blue: 0.16, alpha: 1.0)
    }))

    static let palMuted = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.65, green: 0.70, blue: 0.74, alpha: 1.0)
            : NSColor(red: 0.38, green: 0.42, blue: 0.44, alpha: 1.0)
    }))

    static let palMint = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.28, green: 0.76, blue: 0.58, alpha: 1.0)
            : NSColor(red: 0.23, green: 0.64, blue: 0.50, alpha: 1.0)
    }))

    static let palMist = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.12, green: 0.15, blue: 0.18, alpha: 1.0)
            : NSColor(red: 0.93, green: 0.96, blue: 0.94, alpha: 1.0)
    }))

    static let palCream = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.08, green: 0.10, blue: 0.12, alpha: 1.0)
            : NSColor(red: 0.975, green: 0.97, blue: 0.945, alpha: 1.0)
    }))

    static let palCardBackground = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.16, alpha: 0.85)
            : NSColor(white: 1.0, alpha: 0.82)
    }))

    static let palCardBorder = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.12)
            : NSColor(white: 1.0, alpha: 0.9)
    }))

    static let palRowBackground = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.18, alpha: 0.80)
            : NSColor(white: 1.0, alpha: 0.75)
    }))

    static let palSidebarBackground = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.11, alpha: 0.75)
            : NSColor(white: 1.0, alpha: 0.58)
    }))

    static let palSidebarSelection = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.22, alpha: 0.85)
            : NSColor(white: 1.0, alpha: 0.80)
    }))

    static let palLine = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.10)
            : NSColor(white: 0.0, alpha: 0.08)
    }))
}

struct PalCard<Content: View>: View {
    private let content: Content
    private let padding: CGFloat

    init(padding: CGFloat = 22, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(Color.palCardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.palCardBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.045), radius: 18, y: 8)
    }
}

struct StorageBar: View {
    let usedFraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.075))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(10, proxy.size.width * min(max(usedFraction, 0), 1)))
            }
        }
        .frame(height: 9)
        .accessibilityLabel("Storage used")
        .accessibilityValue("\(Int(usedFraction * 100)) percent")
    }
}

struct PalButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? .white : Color.palInk)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                prominent ? Color.palInk.opacity(configuration.isPressed ? 0.82 : 1) : Color.black.opacity(configuration.isPressed ? 0.10 : 0.055),
                in: Capsule()
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SectionHeading: View {
    let eyebrow: String
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow.uppercased())
                .font(.caption.bold())
                .tracking(1.3)
                .foregroundStyle(Color.palMint)
            Text(title)
                .font(.title.bold())
                .foregroundStyle(Color.palInk)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(.body)
                    .foregroundStyle(Color.palMuted)
            }
        }
    }
}

struct EmptyIllustration: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.palMist)
                .frame(width: 148, height: 148)
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.white)
                .frame(width: 105, height: 74)
                .shadow(color: .black.opacity(0.09), radius: 12, y: 6)
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.palMint.opacity(0.18))
                .frame(width: 72, height: 8)
                .offset(y: 18)
            Image(systemName: "externaldrive.fill.badge.checkmark")
                .font(.system(size: 35, weight: .medium))
                .foregroundStyle(Color.palMint)
                .offset(y: -7)
        }
    }
}
