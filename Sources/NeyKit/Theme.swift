import SwiftUI

/// Tema Grafite: cores e peças básicas (structs, sem classes) compartilhadas por NeyHub e plugins.
public enum Grafite {
    public static let bg = hex("#121315")
    public static let sidebar = hex("#17181b")
    public static let border = hex("#24262a")
    public static let card = hex("#1a1b1f")
    public static let cardBorder = hex("#25272c")
    public static let text = hex("#d8d9dc")
    public static let strong = Color.white
    public static let muted = hex("#6e7179")
    public static let label = hex("#5d6068")
    public static let accent = hex("#c6ff3d")
    public static let onAccent = hex("#111111")
    public static let awakeBg = hex("#1c2410")
    public static let awakeBorder = hex("#3c5214")
    public static let ghostBorder = hex("#33363c")
    public static let ghostText = hex("#9a9ca3")
    public static let selected = hex("#22242a")
    public static let cardRadius: CGFloat = 10
    public static let windowRadius: CGFloat = 14

    /// "#rrggbb" ou "rrggbb"; qualquer outra coisa devolve nil.
    public static func color(hex string: String) -> Color? {
        let digits = string.hasPrefix("#") ? String(string.dropFirst()) : string
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else { return nil }
        return Color(red: Double(value >> 16 & 255) / 255, green: Double(value >> 8 & 255) / 255, blue: Double(value & 255) / 255)
    }

    private static func hex(_ string: String) -> Color { color(hex: string) ?? .clear }
}

public struct GCard<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Grafite.card, in: RoundedRectangle(cornerRadius: Grafite.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Grafite.cardRadius).stroke(Grafite.cardBorder, lineWidth: 1))
    }
}

public struct GPill: View {
    public enum Style { case primary, ghost }
    private let title: String
    private let style: Style
    private let action: () -> Void
    public init(title: String, style: Style = .primary, action: @escaping () -> Void = {}) {
        self.title = title; self.style = style; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(style == .primary ? Grafite.onAccent : Grafite.ghostText)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(style == .primary ? Grafite.accent : .clear, in: Capsule())
                .overlay(Capsule().stroke(style == .primary ? .clear : Grafite.ghostBorder, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Interruptor desenhado à mão: cápsula 26x15, bolinha 11.
public struct GSwitch: View {
    @Binding private var isOn: Bool
    private let label: String
    public init(isOn: Binding<Bool>, label: String) { _isOn = isOn; self.label = label }
    public var body: some View {
        Capsule()
            .fill(isOn ? Grafite.accent : Grafite.ghostBorder)
            .frame(width: 26, height: 15)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(isOn ? Grafite.onAccent : Grafite.ghostText).frame(width: 11, height: 11).padding(2)
            }
            .animation(.easeOut(duration: 0.12), value: isOn)
            .padding(6)
            .contentShape(Rectangle())
            .onTapGesture { isOn.toggle() }
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(isOn ? "Ligado" : "Desligado")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { isOn.toggle() }
    }
}

public struct GSectionLabel: View {
    private let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(1)
            .foregroundStyle(Grafite.label)
            .accessibilityAddTraits(.isHeader)
    }
}

public extension View {
    /// Fundo grafite, texto claro e cantos de janela.
    func grafiteWindow() -> some View {
        foregroundStyle(Grafite.text)
            .background(Grafite.bg)
            .clipShape(RoundedRectangle(cornerRadius: Grafite.windowRadius))
            .environment(\.colorScheme, .dark)
    }
}
