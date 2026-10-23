import AuroraCore
import SwiftUI

/// What the chance is made of, expandable on the main screen (FR-001a, FR-007).
struct ChanceDetailsView: View {
    let result: AuroraResult

    @State private var expanded = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// Grows with the text so large symbols never overlap the row titles.
    @ScaledMetric(relativeTo: .body) private var iconWidth = 24.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.bouncy) { expanded.toggle() }
            } label: {
                HStack {
                    Text("Details")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 16)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(expanded ? "Expanded" : "Collapsed"))
            .accessibilityIdentifier("detailsToggle")
            .sensoryFeedback(.selection, trigger: expanded)

            if expanded {
                VStack(alignment: .leading, spacing: 18) {
                    activity
                    row(symbol: "moon.stars", title: "Darkness") {
                        Text(result.darkness.title)
                    }
                    clouds
                    attribution
                        .padding(.top, 4)
                }
                .padding(.bottom, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 20)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(reduceTransparency ? AnyShapeStyle(Color(white: 0.12)) : AnyShapeStyle(.white.opacity(0.07)))
                .strokeBorder(.white.opacity(reduceTransparency ? 0.25 : 0.12), lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder
    private var activity: some View {
        if let level = result.reading.activity {
            row(symbol: "waveform.path.ecg", title: "Geomagnetic activity") {
                Text(level.title)
                if let r = result.reading.r {
                    Text("R \(Int(r.rounded())) at \(result.reading.station.name)")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("rValue")
                }
            }
        }
    }

    private var clouds: some View {
        row(symbol: "cloud", title: "Cloud cover") {
            if result.clouds.condition == .unknown || !result.chance.cloudsIncluded {
                Text("Cloud cover not included")
            } else {
                if let octas = result.clouds.octas {
                    Text("\(Text(result.clouds.condition.title)), \(octas)/8")
                } else {
                    Text(result.clouds.condition.title)
                }
                if let distance = result.clouds.distanceKm {
                    Text("Weather station \(Formatting.distance(distance)) away")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var attribution: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Source: Finnish Meteorological Institute (FMI), CC BY 4.0")
            Text("Municipality boundaries: Statistics Finland, CC BY 4.0")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func row<Value: View>(symbol: String, title: LocalizedStringKey, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(Color(red: 0.24, green: 0.96, blue: 0.62).opacity(0.9))
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                value()
                    .font(.body)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
