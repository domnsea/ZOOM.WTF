import SwiftUI

/// Palette and reusable pieces for the 1132.WTF look.
enum Theme {
    static let bg = Color(hex: 0x0B0E14)
    static let bgTop = Color(hex: 0x141A26)
    static let bgBottom = Color(hex: 0x06080D)
    static let ink = Color(hex: 0xF5F7FA)
    static let muted = Color(hex: 0x8A94A6)
    static let accent = Color(hex: 0x00E5FF)
    static let accent2 = Color(hex: 0xFF2E88)
    static let ok = Color(hex: 0x22C55E)
    static let warn = Color(hex: 0xFFB020)
    static let err = Color(hex: 0xFF4D4D)

    static let cardStroke = Color(hex: 0x22304A)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Rounded panel that every section of the screen sits inside.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.bgTop)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
    }
}

/// Numbered badge and label that mark a card as level 1, 2, or 3.
struct LevelHeader: View {
    let number: String
    let label: String
    let colour: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Theme.bgBottom)
                .frame(width: 26, height: 26)
                .background(Circle().fill(colour))
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold))
                .kerning(1.4)
                .foregroundColor(colour)
        }
    }
}

struct Eyebrow: View {
    let text: String
    var colour: Color = Theme.muted

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .kerning(1.4)
            .foregroundColor(colour)
    }
}

struct CardTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(Theme.ink)
    }
}

struct CardBody: View {
    let text: String
    var colour: Color = Theme.muted

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundColor(colour)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(3)
    }
}

/// Monospaced readout used for status output.
struct MonoBlock: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.bgBottom)
            )
    }
}

struct ActionButton: View {
    let title: String
    var colour: Color = Theme.accent
    var filled: Bool = true
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundColor(filled ? Theme.bgBottom : colour)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(filled ? colour : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(colour, lineWidth: filled ? 0 : 2)
                )
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}
