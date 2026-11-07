import AuroraCore
import SwiftUI

// Forecasts on the main screen (specs/003-aurora-outlook/contracts/main-screen-additions.md).
//
// A forecast never looks like a measurement (FR-009): forecast elements are labelled as forecasts
// in words, in the paler forecast accent, use smaller type than the headline, and the outlook sits
// in a container with a dashed outline.

/// The "soon" line, under the headline and its data age: Possible or Likely, when not hidden by the
/// light rule. A single line, no container: it is secondary to the headline. The view only reads
/// the snapshot; `OutlookService` computed everything.
struct SoonLine: View {
    let soon: SoonSignal
    let headline: AuroraResult

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if soon.showsOnMainScreen, let line = soon.line(headlineActivity: headline.reading.activity) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                // Decorative; at accessibility sizes the text needs the width.
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: soon.state == .likely ? "wind" : "wind.circle")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(ForecastStyle.accent)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    ForecastTag(text: "Soon")
                    line
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                    if isOvercastNow {
                        Text("Overcast now")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isOvercastNow ? Text("Forecast: \(line). Overcast now") : Text("Forecast: \(line)"))
            .accessibilityIdentifier("soonLine")
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// The headline is None because of overcast: the line still shows, with a note.
    private var isOvercastNow: Bool {
        headline.chance.level == .none && headline.clouds.condition == .overcast
            && headline.chance.limitingFactor == .clouds
    }
}

/// Tonight and tomorrow night under a "Forecast" heading. Tapping a night opens the details at it.
struct OutlookSectionView: View {
    let snapshot: OutlookSnapshot
    let now: Date
    /// The headline's measured activity, compared with tonight's forecast once the night is under way.
    var measuredActivity: ActivityLevel?

    @State private var isShowingDetails = false
    @State private var detailsNight: NightKind = .tonight
    /// When it is next dark enough at this place, for the summer row. Recomputed when the place or
    /// the minute changes, not on every render.
    @State private var darkAgain: Date?

    var body: some View {
        if let outlook = snapshot.outlook {
            if Self.bothNights(of: outlook, are: .unavailable) {
                // The details would add nothing, so the card is not a button.
                card(showsChevron: false) {
                    UnavailableRow(fetchedAt: outlook.tonight.kpFetchedAt, now: now)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("outlookSection")
            } else {
                Group {
                    if Self.bothNights(of: outlook, are: .tooLight) {
                        Button {
                            showDetails(at: .tonight)
                        } label: {
                            card(showsChevron: true) { TooLightRow(darkAgain: darkAgain) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Shows what the forecast is based on"))
                    } else {
                        // Each night is its own button, so the details open at the night tapped.
                        card(showsChevron: true) {
                            NightRow(night: outlook.tonight, now: now, measuredActivity: measuredActivity) {
                                showDetails(at: .tonight)
                            }
                            Divider().overlay(.white.opacity(0.08))
                            NightRow(night: outlook.tomorrow, now: now) { showDetails(at: .tomorrow) }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("outlookSection")
                .onChange(of: darkAgainKey(outlook), initial: true) {
                    let coordinate = snapshot.place.coordinate
                    darkAgain = Self.bothNights(of: outlook, are: .tooLight)
                        ? SolarPosition.nextDarkNight(
                            latitude: coordinate.latitude, longitude: coordinate.longitude, after: now)
                        : nil
                }
                .sensoryFeedback(.selection, trigger: isShowingDetails) { _, showing in showing }
                .sheet(isPresented: $isShowingDetails) {
                    OutlookDetailsSheet(outlook: outlook, now: now, initialNight: detailsNight)
                }
            }
        }
    }

    private func showDetails(at night: NightKind) {
        detailsNight = night
        isShowingDetails = true
    }

    private func card<Rows: View>(showsChevron: Bool, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                // Every row already says "Forecast for …" to VoiceOver.
                ForecastTag(text: "Forecast")
                    .accessibilityHidden(true)
                Spacer()
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            rows()
        }
        .padding(18)
        .contentShape(.rect)
        .forecastFrame(cornerRadius: 24)
    }

    private static func bothNights(of outlook: Outlook, are availability: OutlookAvailability) -> Bool {
        outlook.tonight.availability == availability && outlook.tomorrow.availability == availability
    }

    private struct DarkAgainKey: Equatable {
        let latitude: Double, longitude: Double, minute: Int, needed: Bool
    }

    private func darkAgainKey(_ outlook: Outlook) -> DarkAgainKey {
        DarkAgainKey(
            latitude: snapshot.place.coordinate.latitude, longitude: snapshot.place.coordinate.longitude,
            minute: Int(now.timeIntervalSince1970 / 60), needed: Self.bothNights(of: outlook, are: .tooLight))
    }
}

/// Both nights too light (summer in Finland): one row, with when dark nights return.
private struct TooLightRow: View {
    let darkAgain: Date?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tonight and tomorrow night")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(ChanceLevel.none.title)
                    .font(.title3.weight(.semibold))
                Text(OutlookReason.chance(.tooLight).title)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                if let darkAgain {
                    Text("Dark nights return around \(darkAgain.formatted(.dateTime.day().month(.wide)))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ForecastStyle.accent)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            ForecastMeter(level: .none)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityIdentifier("outlookTooLight")
    }

    private var label: Text {
        var value = Text("\(Text(ChanceLevel.none.title)), \(Text(OutlookReason.chance(.tooLight).title))")
        if let darkAgain {
            value = Text("\(value). \(Text("Dark nights return around \(darkAgain.formatted(.dateTime.day().month(.wide)))"))")
        }
        return Text("Forecast for tonight and tomorrow night: \(value)")
    }
}

/// "Tonight" with the level and reason; the level as words and a small meter, never colour alone.
private struct NightRow: View {
    let night: NightOutlook
    let now: Date
    var measuredActivity: ActivityLevel?
    let showDetails: () -> Void

    var body: some View {
        Button(action: showDetails) { content }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityHint(Text("Shows what the forecast is based on"))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(night.which == .tonight ? "outlookTonight" : "outlookTomorrow")
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(night.title(at: now))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if night.availability == .unavailable {
                    Text("Outlook unavailable")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                } else if let chance = night.chance {
                    Text(chance.level.title)
                        .font(.title3.weight(.semibold))
                    if let reason = night.reason {
                        Text(reason.title)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    if !chance.cloudsIncluded {
                        Text("Cloud cover not included")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if exceeded {
                        Text("Activity now is higher than forecast")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ForecastStyle.accent)
                            .padding(.top, 2)
                    }
                }
            }
            Spacer(minLength: 8)
            if let level = night.chance?.level {
                ForecastMeter(level: level)
            }
        }
        .contentShape(.rect)
    }

    private var exceeded: Bool { night.isExceeded(by: measuredActivity, at: now) }

    private var label: Text {
        var value: Text = if night.availability == .unavailable {
            Text("Outlook unavailable")
        } else if let chance = night.chance, let reason = night.reason {
            Text("\(Text(chance.level.title)), \(Text(reason.title))")
        } else {
            Text("Outlook unavailable")
        }
        if exceeded {
            value = Text("\(value). \(Text("Activity now is higher than forecast"))")
        }
        return switch night.which {
        case .tonight where night.isUnderway(at: now): Text("Forecast for the rest of tonight: \(value)")
        case .tonight: Text("Forecast for tonight: \(value)")
        case .tomorrow: Text("Forecast for tomorrow night: \(value)")
        }
    }
}

private struct UnavailableRow: View {
    let fetchedAt: Date?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Outlook unavailable")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            if let fetchedAt {
                Text("Last forecast \(Formatting.age(of: fetchedAt, now: now))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("outlookUnavailable")
    }
}

// MARK: - Details

/// What each night's outlook is based on (FR-016).
private struct OutlookDetailsSheet: View {
    let outlook: Outlook
    let now: Date
    /// The night tapped on the main screen. Tonight starts at the top, under the
    /// "This is a forecast" note.
    let initialNight: NightKind

    @Environment(\.dismiss) private var dismiss
    @State private var scrolledNight: NightKind?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Label("This is a forecast, not a measurement", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ForecastStyle.accent)
                    ForEach([outlook.tonight, outlook.tomorrow], id: \.which) { night in
                        NightDetails(night: night, now: now)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Based on NOAA's Kp forecast and storm watches, FMI's cloud forecast for your area, and the sun and moon where you are.")
                        Text("Space weather: NOAA Space Weather Prediction Center")
                        Text("Source: Finnish Meteorological Institute (FMI), CC BY 4.0")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(24)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $scrolledNight, anchor: .top)
            // Set once the sheet is laid out: an initial value is not scrolled to.
            .task {
                if initialNight != .tonight { scrolledNight = initialNight }
            }
            .navigationTitle(Text("Outlook details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        // The system glass sheet, dark like the sky behind it; without this it turns light at the
        // large detent in light mode and the text disappears.
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }
}

private struct NightDetails: View {
    let night: NightOutlook
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(night.title(at: now))
                    .font(.title3.weight(.semibold))
                Spacer()
                if let chance = night.chance, night.availability != .unavailable {
                    Text(chance.level.title)
                        .font(.headline)
                        .foregroundStyle(chance.level == .none ? AnyShapeStyle(.secondary) : AnyShapeStyle(ForecastStyle.accent))
                }
            }
            if night.availability == .unavailable {
                Text("Outlook unavailable")
                    .foregroundStyle(.secondary)
            }
            if night.availability == .available {
                DetailLine(symbol: "waveform.path.ecg", title: "Expected activity", effect: .of(night.activity)) {
                    Text(night.activity?.title ?? "Unknown")
                    if let kp = night.maxKp {
                        Text("Highest Kp \(Formatting.kp(kp))").foregroundStyle(.secondary)
                    }
                }
            }
            if night.availability != .tooLight {
                DetailLine(symbol: "bolt.horizontal", title: "Storm watch", effect: .of(stormWatch: night.watchLevel)) {
                    if let level = night.watchLevel { Text(StormLevel.title(level)) } else { Text("None in effect") }
                }
            }
            DetailLine(symbol: "moon.stars", title: "Darkness", effect: .of(night.darkness)) { Text(night.darkness.title) }
            if night.availability != .tooLight {
                DetailLine(symbol: night.moon ? "moon.fill" : "moon", title: "Moon", effect: .of(moonBright: night.moon)) {
                    Text(night.moon ? "Bright moon for most of the night" : "No bright moon")
                }
                DetailLine(symbol: "cloud", title: "Cloud cover", effect: night.meanCloudPercent == nil ? nil : .of(night.clouds)) {
                    if let mean = night.meanCloudPercent {
                        Text("\(Text(night.clouds.title)), \(Text("\(Int(mean.rounded())) % on average"))")
                    } else {
                        Text("Cloud cover not included")
                    }
                }
            }
            if night.availability != .tooLight {
                updateTimes
            }
        }
        .padding(18)
        .forecastFrame(cornerRadius: 22)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(night.which == .tonight ? "outlookDetailsTonight" : "outlookDetailsTomorrow")
    }

    private var updateTimes: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let kp = night.kpFetchedAt {
                Text("Kp forecast updated \(Formatting.age(of: kp, now: now))")
            }
            if let clouds = night.cloudsFetchedAt {
                Text("Cloud forecast updated \(Formatting.age(of: clouds, now: now))")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

private struct DetailLine<Value: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let effect: FactorEffect?
    @ViewBuilder let value: Value

    @ScaledMetric(relativeTo: .body) private var iconWidth = 24.0

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(ForecastStyle.accent.opacity(0.85))
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                FactorTitle(title: title, effect: effect)
                value
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Forecast style

enum ForecastStyle {
    /// A paler, cooler sibling of the headline's aurora green: related, but not the measurement.
    static let accent = Color(red: 0.62, green: 0.90, blue: 0.86)
}

/// "SOON", "FORECAST": small caps in the forecast accent.
struct ForecastTag: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1.1)
            .foregroundStyle(ForecastStyle.accent)
    }
}

/// Three small outlined steps; filled up to the level. Decorative: the level is text.
private struct ForecastMeter: View {
    let level: ChanceLevel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...3, id: \.self) { step in
                Capsule()
                    .strokeBorder(ForecastStyle.accent.opacity(0.55), lineWidth: 1)
                    .background(Capsule().fill(step <= level.rawValue ? ForecastStyle.accent.opacity(0.8) : .clear))
                    .frame(width: 16, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// The forecast container: a faint fill with a dashed outline.
    func forecastFrame(cornerRadius: CGFloat) -> some View {
        modifier(ForecastFrame(cornerRadius: cornerRadius))
    }
}

private struct ForecastFrame: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(reduceTransparency ? AnyShapeStyle(Color(white: 0.12)) : AnyShapeStyle(.white.opacity(0.05)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ForecastStyle.accent.opacity(reduceTransparency ? 0.6 : 0.35),
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
    }
}
