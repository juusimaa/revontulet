import AuroraCore
import SwiftUI

/// "Should I go outside and look?" at a glance (contracts/main-screen-states.md).
struct MainScreenView: View {
    @State var model: MainScreenModel

    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { SkyBackground(level: level).environment(\.colorScheme, systemColorScheme) }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await model.refresh() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: model.isRefreshing)
                        }
                        .disabled(model.isRefreshing)
                        .accessibilityIdentifier("refreshButton")
                    }
                }
        }
        // Text sits on a night sky in both appearances.
        .environment(\.colorScheme, .dark)
        .task { await model.refresh() }
    }

    private var level: ChanceLevel? {
        if case .result(let result, _) = model.state { result.chance.level } else { nil }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .result(let result, let placeName):
            ResultView(result: result, placeName: placeName)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        case .determiningLocation:
            StatusView(symbol: "location.circle", title: "Finding your location",
                       message: "Your location stays on this device.", showsProgress: true)
        case .loading:
            StatusView(symbol: "sparkles", title: "Fetching aurora data",
                       message: "Magnetometer and cloud observations from FMI.", showsProgress: true)
        case .noData:
            StatusView(symbol: "antenna.radiowaves.left.and.right.slash", title: "No aurora data right now",
                       message: "FMI's measurements could not be loaded. Try again in a moment.") {
                Button("Retry") { Task { await model.refresh() } }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("retryButton")
            }
        case .locationDenied:
            StatusView(symbol: "location.slash", title: "Location access is off",
                       message: "Allow location access in Settings to see the chance where you are.") {
                OpenSettingsButton()
            }
        case .outsideCoverage:
            StatusView(symbol: "globe.europe.africa", title: "Outside coverage area",
                       message: "Revontulet covers Finland only.")
                .accessibilityIdentifier("outsideCoverage")
        }
    }
}

// MARK: - Result

private struct ResultView: View {
    let result: AuroraResult
    let placeName: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PlaceHeader(name: placeName, source: result.place.source)
                Hero(result: result)
                    .padding(.top, 72)
                MeasurementLine(result: result)
                    .padding(.top, 28)
                ChanceDetailsView(result: result)
                    .padding(.top, 40)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sensoryFeedback(.success, trigger: result.computedAt)
    }
}

private struct PlaceHeader: View {
    let name: String
    let source: PlaceSource

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.largeTitle.weight(.semibold))
            Label {
                Text(source == .currentLocation ? "Current location" : "Chosen manually")
            } icon: {
                Image(systemName: source == .currentLocation ? "location.fill" : "mappin")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("placeName")
    }
}

private struct Hero: View {
    let result: AuroraResult

    /// The level is the largest text on screen at every Dynamic Type size.
    @ScaledMetric(relativeTo: .largeTitle) private var levelSize = 76.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chance to see the aurora")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text(result.chance.level.title)
                .font(.system(size: levelSize, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text(result.reason.title)
                .font(.title2.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
            LevelMeter(level: result.chance.level)
                .padding(.top, 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Chance to see the aurora"))
        .accessibilityValue(Text("\(Text(result.chance.level.title)), \(Text(result.reason.title))"))
        .accessibilityIdentifier("chanceHeadline")
        .animation(.bouncy, value: result.chance.level)
    }
}

/// Three bars for Low, Moderate and High; None leaves all empty. Decorative: the level is text.
private struct LevelMeter: View {
    let level: ChanceLevel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...3, id: \.self) { step in
                Capsule()
                    .fill(step <= level.rawValue ? AnyShapeStyle(Self.glow) : AnyShapeStyle(.white.opacity(0.16)))
                    .frame(width: 36, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private static let glow = LinearGradient(
        colors: [Color(red: 0.24, green: 0.96, blue: 0.62), Color(red: 0.16, green: 0.80, blue: 0.78)],
        startPoint: .leading, endPoint: .trailing)
}

private struct MeasurementLine: View {
    let result: AuroraResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Label {
                    Text("Measured \(Formatting.age(of: result.reading.measuredAt, now: context.date))")
                } icon: {
                    Image(systemName: "clock")
                }
            }
            .accessibilityIdentifier("dataAge")
            Label {
                Text("\(result.reading.station.name) station, \(Formatting.distance(result.distanceToStationKm))")
            } icon: {
                Image(systemName: "antenna.radiowaves.left.and.right")
            }
            .accessibilityIdentifier("station")
            if result.usedMoreDistantStation {
                Label("The nearest station has no recent data, so a more distant one is used.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.yellow.opacity(0.9))
            }
        }
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.8))
        .labelStyle(DataLabelStyle())
    }
}

struct DataLabelStyle: LabelStyle {
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth = 20.0

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .frame(width: iconWidth)
                .foregroundStyle(.secondary)
            configuration.title
        }
    }
}

// MARK: - States without a result

private struct StatusView<Actions: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var showsProgress = false
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
                .symbolEffect(.pulse, options: .repeat(.continuous), isActive: showsProgress)
            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            actions
                .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: 420)
        .accessibilityElement(children: .contain)
    }
}

extension StatusView where Actions == EmptyView {
    init(symbol: String, title: LocalizedStringKey, message: LocalizedStringKey, showsProgress: Bool = false) {
        self.init(symbol: symbol, title: title, message: message, showsProgress: showsProgress) { EmptyView() }
    }
}

private struct OpenSettingsButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("Open Settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
        .buttonStyle(.glass)
    }
}
