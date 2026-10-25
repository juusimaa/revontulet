import AuroraCore
import SwiftUI

/// Aurora alert settings, a sheet from the main screen (contracts/alert-settings-states.md).
/// The same night sky as the main screen; glass only on the actions.
struct AlertSettingsView: View {
    @Bindable var model: AlertSettingsModel
    /// Opens the place picker for the "No zone yet" state.
    let choosePlace: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AlertHero(isOn: model.isOn)
                    content
                        .padding(.top, 32)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .animation(.bouncy, value: model.phase)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background { SkyBackground(level: model.isOn ? .moderate : nil).environment(\.colorScheme, systemColorScheme) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("alertSettingsDone")
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.success, trigger: model.isOn) { _, isOn in isOn }
        .sensoryFeedback(.selection, trigger: model.threshold)
        .onChange(of: model.threshold) {
            Task { await model.thresholdChanged() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .noZone:
            NoZoneCard(choosePlace: choosePlace)
        case .off, .askingPermission:
            VStack(alignment: .leading, spacing: 28) {
                Text("Get a notification when the chance to see the aurora in your area reaches the level you choose.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                ThresholdPicker(threshold: $model.threshold)
                if let zoneName = model.zoneName {
                    AreaLine(zoneName: zoneName)
                }
                TurnOnButton(isAsking: model.phase == .askingPermission) {
                    Task { await model.turnOn() }
                }
            }
        case .permissionDenied:
            PermissionDeniedCard()
        case .on(let confirming):
            VStack(alignment: .leading, spacing: 28) {
                StatusCard(zoneName: model.zoneName ?? "", confirming: confirming)
                ThresholdPicker(threshold: $model.threshold)
                Button(role: .destructive) {
                    Task { await model.turnOff() }
                } label: {
                    Text("Turn off alerts")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .accessibilityIdentifier("turnOffAlerts")
            }
        }
    }
}

// MARK: - Hero

/// A bell that glows aurora green while alerts are on.
private struct AlertHero: View {
    let isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // The halo spills past the bell's frame but stays inside the screen.
            Image(systemName: isOn ? "bell.badge.fill" : "bell")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(isOn ? AnyShapeStyle(AuroraPalette.glow) : AnyShapeStyle(.white.opacity(0.85)))
                .symbolEffect(.bounce, value: isOn)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 56, height: 56)
                .background {
                    Circle()
                        .fill(RadialGradient(colors: [AuroraPalette.green.opacity(isOn ? 0.45 : 0.12), .clear],
                                             center: .center, startRadius: 4, endRadius: 44))
                        .frame(width: 88, height: 88)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Aurora alerts")
                    .font(.largeTitle.weight(.semibold))
                Text(isOn ? "On" : "Off")
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(isOn ? AuroraPalette.green : .secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("alertsStatus")
        }
        .padding(.top, 24)
    }
}

// MARK: - Threshold

/// Two choices, each with the main screen's level bars so the levels read the same everywhere.
private struct ThresholdPicker: View {
    @Binding var threshold: AlertThreshold

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notify me at")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(.secondary)
            ForEach(AlertThreshold.allCases, id: \.self) { option in
                ThresholdOption(option: option, isSelected: threshold == option) {
                    withAnimation(.bouncy) { threshold = option }
                }
            }
        }
    }
}

private struct ThresholdOption: View {
    let option: AlertThreshold
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.level.title)
                        .font(.title3.weight(.semibold))
                    Text(option.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                LevelBars(level: option.level)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(AuroraPalette.glow) : AnyShapeStyle(.white.opacity(0.35)))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(18)
            .background(.white.opacity(isSelected ? 0.10 : 0.05), in: .rect(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22)
                .strokeBorder(isSelected ? AuroraPalette.green.opacity(0.55) : .white.opacity(0.1), lineWidth: isSelected ? 1 : 0.5))
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("threshold-\(option.rawValue)")
    }
}

/// Three small bars, filled up to the level, as on the main screen. Decorative.
private struct LevelBars: View {
    let level: ChanceLevel

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...3, id: \.self) { step in
                Capsule()
                    .fill(step <= level.rawValue ? AnyShapeStyle(AuroraPalette.glow) : AnyShapeStyle(.white.opacity(0.16)))
                    .frame(width: 14, height: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - States

private struct AreaLine: View {
    let zoneName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("Area: \(zoneName)")
            } icon: {
                Image(systemName: "scope")
            }
            .accessibilityIdentifier("alertArea")
            Label("The area follows the place on the main screen.", systemImage: "location")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.8))
        .labelStyle(DataLabelStyle())
    }
}

private struct TurnOnButton: View {
    let isAsking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isAsking {
                    ProgressView()
                    Text("Waiting for permission…")
                } else {
                    Text("Turn on alerts")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(AuroraPalette.green.opacity(0.85))
        .controlSize(.large)
        .disabled(isAsking)
        .accessibilityIdentifier("turnOnAlerts")
    }
}

private struct StatusCard: View {
    let zoneName: String
    let confirming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Area")
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(zoneName)
                    .font(.title.weight(.semibold))
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("alertArea")
            Label {
                Text(confirming ? "Waiting to confirm" : "Confirmed")
            } icon: {
                Image(systemName: confirming ? "arrow.triangle.2.circlepath" : "checkmark.seal.fill")
                    .foregroundStyle(confirming ? AnyShapeStyle(.secondary) : AnyShapeStyle(AuroraPalette.green))
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: confirming)
            }
            .accessibilityIdentifier("alertConfirmation")
            Label("The area follows the place on the main screen.", systemImage: "location")
                .foregroundStyle(.secondary)
            Label("At most three alerts a night.", systemImage: "moon.zzz")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .labelStyle(DataLabelStyle())
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
    }
}

private struct NoZoneCard: View {
    let choosePlace: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Choose a place in Finland first", systemImage: "mappin.slash")
                .font(.title3.weight(.semibold))
            Text("Alerts are for an area of Finland. Allow location access or choose a municipality, and the area is set from it.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Choose municipality", action: choosePlace)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.top, 4)
                .accessibilityIdentifier("alertsChoosePlace")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alertsNoZone")
    }
}

private struct PermissionDeniedCard: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Notifications are off for Revontulet", systemImage: "bell.slash")
                .font(.title3.weight(.semibold))
            Text("Allow notifications in Settings to get aurora alerts.")
                .font(.body)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alertsPermissionDenied")
    }
}

// MARK: - Shared

enum AuroraPalette {
    static let green = Color(red: 0.24, green: 0.96, blue: 0.62)
    static let glow = LinearGradient(
        colors: [Color(red: 0.24, green: 0.96, blue: 0.62), Color(red: 0.16, green: 0.80, blue: 0.78)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension AlertThreshold {
    /// The lowest level the threshold alerts on.
    var level: ChanceLevel {
        switch self {
        case .moderate: .moderate
        case .high: .high
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .moderate: "alert.threshold.moderate.detail"
        case .high: "alert.threshold.high.detail"
        }
    }
}
