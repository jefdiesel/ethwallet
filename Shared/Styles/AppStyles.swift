import SwiftUI

// MARK: - App Colors

enum AppColors {
    static let accent = Color(red: 0.765, green: 1.0, blue: 0.0) // #c3ff00
    static let accentDark = Color(red: 0.6, green: 0.8, blue: 0.0)
}

// MARK: - Spacing Constants

enum AppSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
}

// MARK: - Primary Button Style

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs + 2)
            .frame(minWidth: 60)
            .background(isEnabled ? AppColors.accent : Color.gray.opacity(0.3))
            .foregroundColor(.black)
            .cornerRadius(5)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - Secondary Button Style

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs + 2)
            .frame(minWidth: 60)
            .background(Color.secondary.opacity(0.12))
            .foregroundColor(isEnabled ? .primary : .secondary)
            .cornerRadius(5)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - Compact Button Style

struct CompactButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(Color.secondary.opacity(0.1))
            .foregroundColor(.primary)
            .cornerRadius(4)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - Icon Button Style

struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(5)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - Button Style Extensions

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == CompactButtonStyle {
    static var compact: CompactButtonStyle { CompactButtonStyle() }
}

// MARK: - Card Style

struct CardModifier: ViewModifier {
    var padding: CGFloat = AppSpacing.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)
    }
}

extension View {
    func cardStyle(padding: CGFloat = AppSpacing.md) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

// MARK: - Compact Form Style

struct CompactFormStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: 400)
    }
}

extension View {
    func compactForm() -> some View {
        modifier(CompactFormStyle())
    }
}

// MARK: - Section Header Style

struct SectionHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

extension View {
    func sectionHeader() -> some View {
        modifier(SectionHeaderStyle())
    }
}
