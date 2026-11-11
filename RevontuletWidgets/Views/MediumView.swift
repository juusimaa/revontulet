import AuroraCore
import SwiftUI

/// The medium Home Screen widget (specs/004-ios-widgets, FR-004): the headline on the left, the R value
/// with its station and the Soon and Tonight outlook on the right. The sky is drawn by the caller in
/// `containerBackground`.
struct MediumView: View {
    let entry: AuroraEntry

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                content(snapshot)
            } else {
                fallback
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Layout

    private func content(_ snapshot: WidgetSnapshot) -> some View {
        HStack(spacing: 14) {
            MediumHeadline(entry: entry, snapshot: snapshot)
                .frame(maxWidth: .infinity, alignment: .leading)
            // At accessibility sizes the headline needs the whole width.
            if !dynamicTypeSize.isAccessibilitySize {
                Rectangle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 1)
                    .padding(.vertical, 2)
                MediumFacts(snapshot: snapshot, now: entry.date)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// No snapshot yet: glyph and place only. The real no-data designs come with US3.
    private var fallback: some View {
        VStack(alignment: .leading, spacing: 6) {
            AuroraGlyph().frame(width: 18, height: 18)
                .foregroundStyle(MediumPalette.color(for: nil))
            Text(entry.placeName)
                .font(.headline)
                .lineLimit(2)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: VoiceOver

    /// "<Level>, <reason>, <place>, <age>" followed by the R, Soon and Tonight facts as sentences.
    private var accessibilityText: Text {
        let base = WidgetFormat.accessibilityLabel(for: entry)
        guard let snapshot = entry.snapshot else { return Text(verbatim: base) }
        var parts: [Text] = [Text(verbatim: base)]
        if let r = MediumFacts.rText(snapshot) { parts.append(r) }
        if let soon = MediumFacts.soonValue(snapshot) { parts.append(Text("Soon: \(soon)")) }
        if let tonight = MediumFacts.tonightValue(snapshot) { parts.append(Text("Tonight: \(tonight)")) }
        if !snapshot.cloudsIncluded { parts.append(Text("Cloud cover not included")) }
        return parts.dropFirst().reduce(parts[0]) { Text("\($0). \($1)") }
    }
}

// MARK: Headline

/// Glyph, level word, reason and "place · age". The level word comes first and largest and never
/// truncates; the place truncates before the reason.
private struct MediumHeadline: View {
    let entry: AuroraEntry
    let snapshot: WidgetSnapshot

    var body: some View {
        let tint = MediumPalette.color(for: snapshot.level)
        VStack(alignment: .leading, spacing: 0) {
            AuroraGlyph(level: snapshot.level)
                .frame(width: 16, height: 16)
                .foregroundStyle(tint)
            Spacer(minLength: 2)
            Text(snapshot.level.title)
                .font(.title.weight(.heavy))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(snapshot.reason.title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)
                .padding(.top, 1)
            HStack(spacing: 0) {
                Text(entry.placeName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(" · ").fixedSize()
                Text(WidgetFormat.age(of: snapshot.measuredAt, at: entry.date))
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.7))
            .padding(.top, 5)
        }
    }
}

// MARK: Facts

/// R value with its station, then Soon and Tonight. Rows with nothing to say are left out.
private struct MediumFacts: View {
    let snapshot: WidgetSnapshot
    let now: Date

    static func rText(_ snapshot: WidgetSnapshot) -> Text? {
        guard let r = snapshot.rValue else { return nil }
        return Text("R \(Int(r.rounded())) at \(snapshot.stationName)")
    }

    /// The same wording as the app's Soon line; nothing for Quiet and Unknown or when the app hides it.
    static func soonValue(_ snapshot: WidgetSnapshot) -> Text? {
        guard let soon = snapshot.soon, soon.showsOnMainScreen else { return nil }
        return soon.line(headlineActivity: snapshot.activity)
    }

    /// Tonight's level and reason, as in the app's outlook row.
    static func tonightValue(_ snapshot: WidgetSnapshot) -> Text? {
        guard let night = snapshot.tonight, night.availability == .available,
              let chance = night.chance, let reason = night.reason else { return nil }
        return Text("\(Text(chance.level.title)), \(Text(reason.title))")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let r = Self.rText(snapshot) {
                r.font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(2)
                    .foregroundStyle(.white)
            }
            if let soon = Self.soonValue(snapshot) {
                MediumRow(label: Text("Soon"), value: soon, lines: 3)
            }
            if let tonight = Self.tonightValue(snapshot) {
                MediumRow(label: Text("Tonight"), value: tonight)
            }
            if !snapshot.cloudsIncluded {
                Text("Cloud cover not included")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
            }
        }
    }
}

private struct MediumRow: View {
    let label: Text
    let value: Text
    /// The Soon sentence is the longest and must not be cut mid-word in Finnish.
    var lines = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            label
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.62))
            value
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(lines)
                .minimumScaleFactor(0.85)
        }
    }
}

// MARK: Colours

/// The four level colours from the widget UI draft (the app has no shared level tint). The level is
/// always also written as a word.
private enum MediumPalette {
    static func color(for level: ChanceLevel?) -> Color {
        switch level {
        case .high: Color(red: 1.0, green: 0.435, blue: 0.847)      // #ff6fd8
        case .moderate: Color(red: 0.365, green: 1.0, blue: 0.69)   // #5dffb0
        case .low: Color(red: 1.0, green: 0.827, blue: 0.42)        // #ffd36b
        case ChanceLevel.none?, nil: Color(red: 0.725, green: 0.776, blue: 0.8) // #b9c6cc
        }
    }
}

// MARK: Previews

#if DEBUG
private func mediumSample(_ level: ChanceLevel, reason: ChanceReason, r: Double? = 142, clouds: Bool = true,
                          outlook: Bool = true) -> AuroraEntry {
    let now = Date()
    let tonight = NightOutlook(
        which: .tonight, night: .tooLight, availability: .available, activity: .possible,
        chance: Chance(level: .moderate, limitingFactor: nil, cloudsIncluded: true), reason: .chance(.goodConditions))
    let snapshot = WidgetSnapshot(
        level: level, reason: reason, cloudsIncluded: clouds, municipalityCode: "000", stationName: "Sampletown",
        rValue: r, measuredAt: now.addingTimeInterval(-12 * 60), isStale: false,
        soon: outlook ? SoonSignal(state: .likely, arrivalMinutes: 30, showsOnMainScreen: true) : nil,
        tonight: outlook ? tonight : nil)
    return AuroraEntry(date: now, snapshot: snapshot, placeName: "Faketown")
}

private struct MediumPreviewFrame: View {
    let entry: AuroraEntry
    var body: some View {
        MediumView(entry: entry)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(width: 338, height: 158)
            .background { WidgetSky(level: entry.snapshot?.level) }
            .clipShape(.rect(cornerRadius: 26))
    }
}

#Preview("High") { MediumPreviewFrame(entry: mediumSample(.high, reason: .goodConditions)) }
#Preview("Moderate") { MediumPreviewFrame(entry: mediumSample(.moderate, reason: .goodConditions)) }
#Preview("Low, no clouds") { MediumPreviewFrame(entry: mediumSample(.low, reason: .lowActivity, clouds: false)) }
#Preview("None, no outlook") { MediumPreviewFrame(entry: mediumSample(.none, reason: .tooLight, r: nil, outlook: false)) }
#endif
