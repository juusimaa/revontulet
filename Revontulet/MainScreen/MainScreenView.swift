import AuroraCore
import SwiftUI

/// "Should I go outside and look?" at a glance (contracts/main-screen-states.md).
struct MainScreenView: View {
    let model: MainScreenModel
    let alerts: AlertSettingsModel

    @State private var isChoosingPlace = false
    @State private var isShowingAlerts = false

    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { SkyBackground(level: level).environment(\.colorScheme, systemColorScheme) }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Change place", systemImage: "mappin.and.ellipse") { isChoosingPlace = true }
                            .accessibilityIdentifier("changePlaceButton")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        AlertsButton(isOn: alerts.isOn) { isShowingAlerts = true }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await model.userRefresh() }
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
        // Cached result first, then refreshes every 5 minutes; cancelled when the app leaves the foreground.
        .task(id: scenePhase) {
            if scenePhase == .active { await model.runWhileActive() }
        }
        .sensoryFeedback(.warning, trigger: model.isOffline) { _, offline in offline }
        .sensoryFeedback(.selection, trigger: model.selection)
        // Opening an aurora alert shows this screen with a fresh result (no deep link).
        .onReceive(NotificationCenter.default.publisher(for: .auroraAlertOpened)) { _ in
            Task { await model.refresh() }
        }
        .sheet(isPresented: $isShowingAlerts) {
            AlertSettingsView(model: alerts) {
                isShowingAlerts = false
                isChoosingPlace = true
            }
        }
        .sheet(isPresented: $isChoosingPlace) {
            PlacePickerView(
                resolver: model.placeResolver, selection: model.selection,
                preferSwedish: MainScreenModel.prefersSwedish
            ) { selection in
                Task { await model.choose(selection) }
            }
        }
    }

    private var chooseMunicipalityButton: some View {
        Button("Choose municipality") { isChoosingPlace = true }
            .accessibilityIdentifier("chooseMunicipalityButton")
    }

    /// The outlook does not need R, so it stays when the headline has no data.
    @ViewBuilder
    private var outlookWithoutHeadline: some View {
        if let outlook = model.outlook {
            OutlookSectionView(snapshot: outlook, now: model.now())
                .padding(.top, 24)
                .multilineTextAlignment(.leading)
        }
    }

    private var level: ChanceLevel? {
        if case .result(let result, _) = model.state { result.chance.level } else { nil }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .result(let result, let placeName):
            ResultView(model: model, result: result, placeName: placeName)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        case .determiningLocation:
            StatusView(symbol: "location.circle", title: "Finding your location",
                       message: "Your location stays on this device.", showsProgress: true) {
                chooseMunicipalityButton
                    .buttonStyle(.glass)
            }
        case .loading:
            StatusView(symbol: "sparkles", title: "Fetching aurora data",
                       message: "Magnetometer and cloud observations from FMI.", showsProgress: true)
        case .noData where model.isOffline:
            StatusView(symbol: "wifi.slash", title: "You're offline",
                       message: "Aurora data from FMI is needed to show a chance. Connect to the internet and try again.") {
                Button("Retry") { Task { await model.userRefresh() } }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("retryButton")
                outlookWithoutHeadline
            }
            .accessibilityIdentifier("offlineNoData")
        case .noData:
            StatusView(symbol: "antenna.radiowaves.left.and.right.slash", title: "No aurora data right now",
                       message: "FMI's measurements could not be loaded. Try again in a moment.") {
                Button("Retry") { Task { await model.userRefresh() } }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("retryButton")
                outlookWithoutHeadline
            }
        case .locationDenied:
            StatusView(symbol: "location.slash", title: "Location access is off",
                       message: "Choose a municipality, or allow location access in Settings to see the chance where you are.") {
                VStack(spacing: 12) {
                    chooseMunicipalityButton
                        .buttonStyle(.glassProminent)
                    OpenSettingsButton()
                }
            }
            .accessibilityIdentifier("locationDenied")
        case .outsideCoverage:
            StatusView(symbol: "globe.europe.africa", title: "Outside coverage area",
                       message: "Revontulet covers Finland only. Choose a Finnish municipality to see its chance.") {
                chooseMunicipalityButton
                    .buttonStyle(.glassProminent)
            }
            .accessibilityIdentifier("outsideCoverage")
        }
    }
}

/// Opens the alert settings. The bell is filled while alerts are on, and the label says so in
/// words, never by the symbol alone.
private struct AlertsButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Aurora alerts", systemImage: isOn ? "bell.fill" : "bell")
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(Text(isOn ? "Aurora alerts, on" : "Aurora alerts, off"))
        .accessibilityIdentifier("alertsButton")
    }
}

// MARK: - Result

private struct ResultView: View {
    let model: MainScreenModel
    let result: AuroraResult
    let placeName: String

    private var outlookShown: Bool { model.outlook?.outlook != nil }

    var body: some View {
        ScrollView {
            // Re-evaluated every 30 s so the data age and the outdated badge stay current.
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                let now = model.now()
                let freshness = model.freshness(of: result, at: now)
                VStack(alignment: .leading, spacing: 0) {
                    PlaceHeader(name: placeName, source: result.place.source)
                    if freshness == .offline {
                        OfflineNotice { Task { await model.userRefresh() } }
                            .padding(.top, 24)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Hero(result: result, freshness: freshness)
                        .padding(.top, freshness == .offline ? 40 : 72)
                    // The data age and station belong to the headline; the forecast comes after them.
                    MeasurementLine(result: result, freshness: freshness, now: now)
                        .padding(.top, 28)
                    if let soon = model.outlook?.soon {
                        SoonLine(soon: soon, headline: result)
                            .padding(.top, 28)
                    }
                    if let outlook = model.outlook {
                        OutlookSectionView(snapshot: outlook, now: now, measuredActivity: result.reading.activity)
                            .padding(.top, 32)
                    }
                    ChanceDetailsView(result: result, soon: model.outlook?.soon, now: now)
                        .padding(.top, outlookShown ? 16 : 40)
                }
                .animation(.bouncy, value: freshness)
                .animation(.bouncy, value: model.outlook)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.always)
        // The soft default is invisible on the night sky; without it the header collides with the toolbar.
        .scrollEdgeEffectStyle(.hard, for: .top)
        .refreshable { await model.userRefresh() }
        // Only refreshes the user asked for; the 5-minute background refresh stays silent.
        .sensoryFeedback(.success, trigger: model.userRefreshesCompleted)
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
    let freshness: MainScreenModel.Freshness

    /// The level is the largest text on screen at every Dynamic Type size.
    @ScaledMetric(relativeTo: .largeTitle) private var levelSize = 76.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chance to see the aurora")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            Text(result.chance.level.title)
                .font(.system(size: levelSize, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .contentTransition(.numericText())
                .opacity(levelOpacity)
            // Capped so the level stays larger: it cannot wrap and shrinks to fit the width instead.
            Text(result.reason.title)
                .font(.title2.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            LevelMeter(level: result.chance.level)
                .padding(.top, 8)
                .opacity(levelOpacity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Chance to see the aurora"))
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("chanceHeadline")
        .animation(.bouncy, value: result.chance.level)
    }

    /// An old measurement dims the level. Offline it stays bright: the notice above already says so.
    private var levelOpacity: Double { freshness == .outdated ? 0.6 : 1 }

    private var accessibilityValue: Text {
        let level = Text(result.chance.level.title), reason = Text(result.reason.title)
        return switch freshness {
        case .current: Text("\(level), \(reason)")
        case .outdated: Text("\(level), \(reason), outdated")
        case .offline: Text("\(level), \(reason), not updating")
        }
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
    let freshness: MainScreenModel.Freshness
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label {
                    Text("Measured \(Formatting.age(of: result.reading.measuredAt, now: now))")
                } icon: {
                    Image(systemName: "clock")
                }
                .accessibilityIdentifier("dataAge")
                if freshness != .current {
                    OutdatedBadge(isOffline: freshness == .offline)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            Label {
                Text("\(result.reading.station.name) station, \(Formatting.distance(result.distanceToStationKm))")
            } icon: {
                Image(systemName: "antenna.radiowaves.left.and.right")
            }
            .accessibilityIdentifier("station")
            if result.darkness == .tooLight, let dark = nextDarkness {
                Label {
                    Text("Dark enough from \(dark.formatted(date: .omitted, time: .shortened))")
                } icon: {
                    Image(systemName: "moon.stars")
                }
                .accessibilityIdentifier("darkAfter")
            }
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

    /// When the sky next stops being too light at this place; nil when it stays light all day.
    private var nextDarkness: Date? {
        SolarPosition.nextDarkness(
            latitude: result.place.coordinate.latitude, longitude: result.place.coordinate.longitude, after: now)
    }
}

/// Marks a result that is not current: older than 30 minutes, or not refreshable right now.
private struct OutdatedBadge: View {
    let isOffline: Bool

    var body: some View {
        Label(isOffline ? "Not updating" : "Outdated",
              systemImage: isOffline ? "wifi.slash" : "clock.badge.exclamationmark")
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Self.amber)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Self.amber.opacity(0.16), in: .capsule)
            .overlay(Capsule().strokeBorder(Self.amber.opacity(0.35), lineWidth: 0.5))
            .accessibilityIdentifier("outdatedBadge")
    }

    static let amber = Color(red: 1.0, green: 0.78, blue: 0.36)
}

/// Shown above a cached result when new data cannot be fetched.
private struct OfflineNotice: View {
    let retry: () -> Void

    var body: some View {
        // Retry sits under the message so long translations never squeeze the text.
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.title3.weight(.medium))
                .foregroundStyle(OutdatedBadge.amber)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Can't fetch new data")
                        .font(.subheadline.weight(.semibold))
                    Text("Showing the last known result. Check your connection.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("offlineMessage")
                Button("Retry", action: retry)
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .accessibilityIdentifier("retryButton")
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
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
        // Scrolls rather than truncating when large Dynamic Type makes it taller than the screen.
        ScrollView {
            stack
                .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Centred when it fits; taller content starts from the top.
        .defaultScrollAnchor(.center, for: .alignment)
    }

    private var stack: some View {
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
