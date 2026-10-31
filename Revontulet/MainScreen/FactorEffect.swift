import AuroraCore
import SwiftUI

/// Which way a factor pushes the chance, following the chance rule
/// (specs/003-aurora-outlook/contracts/chance-rules.md). No effect (nil) shows no badge.
enum FactorEffect {
    /// Raises the chance: probable activity, a storm watch, a dark sky, no bright moon, clear sky.
    case helps
    /// Lowers it by a step: unlikely activity, twilight, a bright moon, partly cloudy.
    case limits
    /// Makes it None on its own: too light, overcast.
    case prevents

    var title: LocalizedStringResource {
        switch self {
        case .helps: "effect.helps"
        case .limits: "effect.limits"
        case .prevents: "effect.prevents"
        }
    }

    var symbol: String {
        switch self {
        case .helps: "checkmark.circle.fill"
        case .limits: "minus.circle.fill"
        case .prevents: "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .helps: Color(red: 0.24, green: 0.96, blue: 0.62)
        case .limits: Color(red: 1.00, green: 0.78, blue: 0.35)
        case .prevents: Color(red: 1.00, green: 0.45, blue: 0.45)
        }
    }

    static func of(_ activity: ActivityLevel?) -> FactorEffect? {
        switch activity {
        case .unlikely: .limits
        case .probable: .helps
        case .possible, nil: nil
        }
    }

    static func of(_ darkness: Darkness) -> FactorEffect {
        switch darkness {
        case .dark: .helps
        case .twilight: .limits
        case .tooLight: .prevents
        }
    }

    static func of(moonBright: Bool) -> FactorEffect {
        moonBright ? .limits : .helps
    }

    static func of(_ clouds: CloudCondition) -> FactorEffect? {
        switch clouds {
        case .clear: .helps
        case .partly: .limits
        case .overcast: .prevents
        case .unknown: nil
        }
    }

    static func of(stormWatch level: Int?) -> FactorEffect? {
        level == nil ? nil : .helps
    }

    static func of(_ soon: SoonState) -> FactorEffect? {
        switch soon {
        case .possible, .likely: .helps
        case .quiet, .unknown: nil
        }
    }
}

/// "✓ Helps" on a factor's title line: a symbol and a word, never colour alone.
struct FactorEffectBadge: View {
    let effect: FactorEffect

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: effect.symbol)
                .accessibilityHidden(true)
            Text(effect.title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(effect.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(effect.color.opacity(0.14)))
        .fixedSize()
    }
}

/// A factor's title with its effect badge, if any; the badge wraps under the title at
/// accessibility sizes.
struct FactorTitle: View {
    let title: LocalizedStringKey
    let effect: FactorEffect?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        layout {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let effect {
                FactorEffectBadge(effect: effect)
            }
        }
    }
}
