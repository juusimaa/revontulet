import AuroraCore
import SwiftUI

/// The second page: aurora activity at every magnetometer station, on a map of Finland (issue #2).
/// Levels come from R alone, against each station's own thresholds; clouds, darkness and the moon
/// are left out, so the page answers "are there auroras anywhere in Finland right now?".
struct StationMapPage: View {
    let readings: [StationReading]?
    let status: MainScreenModel.StationMapStatus
    /// The warning shows when the readings are not being refreshed.
    private var isNotUpdating: Bool { status == .offline || status == .noData }
    /// When the newest valid reading was taken; derived once per input change.
    private var latestMeasurement: Date? { readings?.lazy.filter { $0.r != nil }.map(\.measuredAt).max() }

    @State private var selectedID: Station.ID?

    /// Below this the stations crowd together and their labels overlap.
    private static let minimumMapHeight: CGFloat = 380

    var body: some View {
        Group {
            if let readings {
                // One screen when it fits; with large text the page scrolls instead, so the map
                // keeps a usable size.
                ViewThatFits(in: .vertical) {
                    page(readings, mapHeight: nil)
                    ScrollView {
                        page(readings, mapHeight: 460)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.top, 20)
                    Spacer()
                    emptyState
                        .frame(maxWidth: .infinity)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 44)
            }
        }
        .animation(.smooth(duration: 0.2), value: selectedID)
        .sensoryFeedback(.selection, trigger: selectedID)
    }

    /// - Parameter mapHeight: a fixed map height for the scrolling layout; nil lets the map take
    ///   the space left over.
    private func page(_ readings: [StationReading], mapHeight: CGFloat?) -> some View {
        let current = selected(in: readings)
        return VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, 20)
            MapLegend()
                .padding(.top, 14)
            StationMap(readings: readings, selectedID: current?.station.id) { selectedID = $0 }
                .frame(minHeight: mapHeight ?? Self.minimumMapHeight, maxHeight: mapHeight ?? .infinity)
                .padding(.vertical, 12)
            if let reading = current {
                StationCard(reading: reading)
                    .id(reading.station.id)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 24)
        // Room for the page dots.
        .padding(.bottom, 44)
    }

    /// Nothing to draw yet: a spinner while loading, otherwise a calm explanation.
    @ViewBuilder private var emptyState: some View {
        switch status {
        case .loading, .current:
            ProgressView()
        case .offline:
            Text("Can't reach FMI right now. The map updates when the connection is back.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        case .noData:
            Text("No station readings right now.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Auroras in Finland now")
                .font(.title.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                if isNotUpdating {
                    Label("Not updating", systemImage: "wifi.slash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.36))
                }
            }
        }
    }

    private var subtitle: LocalizedStringResource {
        guard let measuredAt = latestMeasurement else {
            return "Geomagnetic activity only"
        }
        // Readings from an earlier day carry their date, so old data does not pass for current.
        let when = Calendar.current.isDateInToday(measuredAt)
            ? measuredAt.formatted(date: .omitted, time: .shortened)
            : measuredAt.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        return "Measured \(when) · geomagnetic activity only"
    }

    /// The tapped station, else the most active one (the northernmost among equals).
    private func selected(in readings: [StationReading]) -> StationReading? {
        if let selectedID, let tapped = readings.first(where: { $0.station.id == selectedID }) { return tapped }
        return readings.filter { $0.r != nil }.max { a, b in
            (a.rank, a.station.latitude) < (b.rank, b.station.latitude)
        }
    }
}

private extension StationReading {
    var rank: Int {
        switch activity {
        case .probable: 3
        case .possible: 2
        case .unlikely: 1
        case nil: 0
        }
    }
}

// MARK: - Map

/// The outline of Finland with a marker per station. Markers are buttons; active stations glow.
private struct StationMap: View {
    let readings: [StationReading]
    let selectedID: Station.ID?
    let select: (Station.ID) -> Void

    var body: some View {
        GeometryReader { proxy in
            let projection = MapProjection(fitting: proxy.size)
            ZStack(alignment: .topLeading) {
                MapCanvas(readings: readings, projection: projection)
                ForEach(readings, id: \.station.id) { reading in
                    StationMarker(
                        reading: reading, isSelected: reading.station.id == selectedID,
                        labelLeading: projection.point(reading.station.coordinate).x > proxy.size.width - 110
                    ) { select(reading.station.id) }
                    .position(projection.point(reading.station.coordinate))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Map of Finland"))
    }
}

/// Equirectangular, with longitudes shrunk by cos 64° so Finland keeps its shape; fitted and
/// centred in the given size. Covers Finland and Tartu, the station in Estonia.
struct MapProjection {
    static let longitudes = 19.9...31.8
    static let latitudes = 57.9...70.15
    private static let xScale = cos(64 * Double.pi / 180)

    let rect: CGRect
    private let scale: Double

    init(fitting size: CGSize) {
        let width = (Self.longitudes.upperBound - Self.longitudes.lowerBound) * Self.xScale
        let height = Self.latitudes.upperBound - Self.latitudes.lowerBound
        scale = min(size.width / width, size.height / height)
        let fitted = CGSize(width: width * scale, height: height * scale)
        rect = CGRect(origin: CGPoint(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2), size: fitted)
    }

    func point(latitude: Double, longitude: Double) -> CGPoint {
        CGPoint(x: rect.minX + (longitude - Self.longitudes.lowerBound) * Self.xScale * scale,
                y: rect.minY + (Self.latitudes.upperBound - latitude) * scale)
    }

    func point(_ coordinate: Coordinate) -> CGPoint {
        point(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// The map's height in points, for sizes that follow the map.
    var height: Double { rect.height }
}

private struct MapCanvas: View {
    let readings: [StationReading]
    let projection: MapProjection

    var body: some View {
        Canvas { context, _ in
            let finland = FinlandOutline.path(projection)
            context.fill(finland, with: .color(.white.opacity(0.06)))
            context.stroke(finland, with: .color(.white.opacity(0.32)), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
            context.stroke(FinlandOutline.estoniaCoast(projection), with: .color(.white.opacity(0.2)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            // The glow stays inside Finland, like the aurora over it.
            var glow = context
            glow.clip(to: finland)
            glow.blendMode = .screen
            for reading in readings {
                let (radius, strength): (Double, Double) = switch reading.activity {
                case .probable: (0.16, 0.55)
                case .possible: (0.10, 0.3)
                case .unlikely, nil: (0, 0)
                }
                guard radius > 0 else { continue }
                let center = projection.point(reading.station.coordinate)
                let r = radius * projection.height
                glow.fill(
                    Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(
                        Gradient(colors: [MapStyle.glow.opacity(strength), MapStyle.glow.opacity(0)]),
                        center: center, startRadius: 0, endRadius: r))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct StationMarker: View {
    let reading: StationReading
    let isSelected: Bool
    /// The label goes left of the dot near the east edge, where it would not fit on the right.
    let labelLeading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    Circle()
                        .strokeBorder(.white, lineWidth: 2)
                        .frame(width: 28, height: 28)
                }
                MapDot(activity: reading.activity, hasData: reading.r != nil)
            }
            .frame(width: 44, height: 44)
            .contentShape(.rect)
            .overlay(alignment: labelLeading ? .trailing : .leading) {
                Text(reading.station.name)
                    .font(.caption.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(reading.activity == .unlikely || reading.r == nil ? .white.opacity(0.65) : .white)
                    .shadow(color: .black.opacity(0.9), radius: 2, y: 1)
                    .fixedSize()
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .offset(x: labelLeading ? -38 : 38)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(reading.station.name))
        .accessibilityValue(reading.accessibilityValue)
        .accessibilityHint(Text("Shows details below"))
        .accessibilitySortPriority(Double(reading.rank))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Probable, possible and unlikely differ in size and brightness as well as colour.
private struct MapDot: View {
    let activity: ActivityLevel?
    let hasData: Bool

    var body: some View {
        switch activity {
        case .probable:
            Circle().fill(MapStyle.probable)
                .frame(width: 16, height: 16)
                .shadow(color: MapStyle.probable.opacity(0.8), radius: 8)
        case .possible:
            Circle().fill(MapStyle.possible)
                .frame(width: 12, height: 12)
                .shadow(color: MapStyle.possible.opacity(0.5), radius: 4)
        case .unlikely:
            Circle().strokeBorder(.white.opacity(0.6), lineWidth: 2)
                .frame(width: 10, height: 10)
        case nil:
            Circle().strokeBorder(.white.opacity(0.65), style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                .frame(width: 10, height: 10)
        }
    }
}

private struct MapLegend: View {
    var body: some View {
        // Finnish and Swedish words are long: the legend stacks rather than widening the page.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) { items }
            VStack(alignment: .leading, spacing: 6) { items }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.caption)
        .foregroundStyle(.white.opacity(0.8))
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var items: some View {
        item(.probable)
        item(.possible)
        item(.unlikely)
        item(nil)
    }

    private func item(_ level: ActivityLevel?) -> some View {
        HStack(spacing: 6) {
            MapDot(activity: level, hasData: level != nil)
                .frame(width: 16)
            if let level {
                Text(level.shortTitle)
            } else {
                Text("No data")
            }
        }
    }
}

/// The chosen station: its level, and its R against its own thresholds.
private struct StationCard: View {
    let reading: StationReading

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(reading.station.name)
                    .font(.headline)
                Spacer()
                if let r = reading.r {
                    Text("R \(Int(r.rounded()))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            if let activity = reading.activity {
                Text(activity.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(activity.cardColor)
                ThresholdBar(reading: reading)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        possibleFrom.fixedSize()
                        Spacer(minLength: 12)
                        probableFrom.fixedSize()
                    }
                    // Stacked, the lines wrap rather than widening the page.
                    VStack(alignment: .leading, spacing: 2) {
                        possibleFrom
                        probableFrom
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            } else {
                Text("No recent data from this station")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(16)
        .background(.white.opacity(0.07), in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stationCard")
    }
}

extension StationCard {
    fileprivate var possibleFrom: Text {
        Text("Possible from R \(Int(reading.station.yellowThreshold))")
    }

    fileprivate var probableFrom: Text {
        Text("Probable from R \(Int(reading.station.redThreshold))")
    }
}

/// R on a scale that shows both thresholds, with a tick at each. Decorative: the card says it in words.
private struct ThresholdBar: View {
    let reading: StationReading

    var body: some View {
        GeometryReader { proxy in
            let r = reading.r ?? 0
            let top = max(reading.station.redThreshold * 1.4, r * 1.1)
            let x = { (value: Double) in proxy.size.width * min(1, value / top) }
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [MapStyle.possible, MapStyle.probable], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, x(r)))
                ForEach([reading.station.yellowThreshold, reading.station.redThreshold], id: \.self) { threshold in
                    Rectangle()
                        .fill(.white.opacity(0.6))
                        .frame(width: 2, height: 12)
                        .offset(x: x(threshold) - 1)
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

private enum MapStyle {
    static let probable = Color(red: 0.62, green: 1.0, blue: 0.82)
    static let possible = Color(red: 0.13, green: 0.73, blue: 0.54)
    static let glow = Color(red: 0.30, green: 1.0, blue: 0.69)
}

private extension ActivityLevel {
    var cardColor: Color {
        switch self {
        case .probable: MapStyle.probable
        case .possible: Color(red: 0.31, green: 0.86, blue: 0.67)
        case .unlikely: .white.opacity(0.8)
        }
    }

    /// One word for the legend.
    var shortTitle: LocalizedStringResource {
        switch self {
        case .probable: "Probable"
        case .possible: "Possible"
        case .unlikely: "Unlikely"
        }
    }
}

private extension StationReading {
    var accessibilityValue: Text {
        guard let r, let activity else { return Text("No recent data") }
        return Text("\(Text(activity.title)), R \(Int(r.rounded()))")
    }
}

// MARK: - Outline

/// A simplified outline of Finland (about 70 points, accurate to a few kilometres at this size) and
/// the north coast of Estonia, as longitude–latitude pairs.
enum FinlandOutline {
    static let border: [(lon: Double, lat: Double)] = [
        (20.55, 69.06), (21.27, 69.31), (21.9, 69.0), (22.4, 68.72), (23.0, 68.68), (23.9, 68.82),
        (24.9, 68.58), (25.7, 68.9), (25.8, 69.0), (26.0, 69.7), (27.0, 69.92), (27.9, 70.08),
        (28.4, 69.83), (29.3, 69.5), (28.9, 69.05), (28.4, 68.9), (28.8, 68.5), (28.4, 68.2),
        (29.6, 67.8), (30.0, 67.67), (29.1, 66.9), (29.9, 66.5), (29.6, 66.1), (30.1, 65.7),
        (29.7, 65.6), (29.9, 64.8), (30.5, 64.3), (30.0, 63.8), (31.2, 63.2), (31.55, 62.9),
        (30.9, 62.3), (30.0, 61.8), (29.3, 61.3), (28.0, 60.6), (27.8, 60.5), (27.0, 60.5),
        (26.5, 60.4), (25.5, 60.3), (24.9, 60.15), (24.0, 60.0), (23.0, 59.85), (22.5, 60.0),
        (22.0, 60.3), (21.4, 60.6), (21.5, 61.0), (21.4, 61.6), (21.2, 62.3), (21.3, 62.8),
        (21.6, 63.1), (22.3, 63.4), (23.0, 63.8), (24.0, 64.3), (24.5, 64.8), (25.3, 65.0),
        (25.2, 65.4), (24.7, 65.7), (24.2, 65.82), (23.7, 66.3), (23.9, 66.8), (23.6, 67.2),
        (23.4, 67.5), (23.6, 67.9), (22.8, 68.3), (22.4, 68.45), (21.6, 68.8), (20.8, 69.0),
    ]

    static let estonia: [(lon: Double, lat: Double)] = [
        (23.4, 59.3), (24.0, 59.4), (24.8, 59.5), (25.8, 59.6), (26.9, 59.5), (28.0, 59.45),
    ]

    static func path(_ projection: MapProjection) -> Path {
        var path = line(border, projection)
        path.closeSubpath()
        return path
    }

    static func estoniaCoast(_ projection: MapProjection) -> Path {
        line(estonia, projection)
    }

    private static func line(_ points: [(lon: Double, lat: Double)], _ projection: MapProjection) -> Path {
        Path { path in
            path.addLines(points.map { projection.point(latitude: $0.lat, longitude: $0.lon) })
        }
    }
}

private func previewReadings(measuredAt: Date = .now) -> [StationReading] {
    let stations = (try? ReferenceData.loadStations()) ?? []
    let r: [String: Double] = ["KEV": 182, "KIL": 228, "IVA": 210, "MUO": 160, "PEL": 96, "RAN": 74,
                               "OUJ": 52, "MEK": 41, "HAN": 33]
    return stations.map { station in
        StationReading(station: station, r: r[station.id], measuredAt: measuredAt,
                       activity: r[station.id].map { ActivityClassifier.level(r: $0, station: station) })
    }
}

#Preview("Current") {
    StationMapPage(readings: previewReadings(), status: .current)
        .background { SkyBackground(level: .high) }
        .environment(\.colorScheme, .dark)
}

#Preview("Offline, old readings") {
    StationMapPage(readings: previewReadings(measuredAt: .now.addingTimeInterval(-3 * 86_400)), status: .offline)
        .background { SkyBackground(level: .high) }
        .environment(\.colorScheme, .dark)
}

#Preview("Loading") {
    StationMapPage(readings: nil, status: .loading)
        .background { SkyBackground(level: .high) }
        .environment(\.colorScheme, .dark)
}

#Preview("Offline, no readings") {
    StationMapPage(readings: nil, status: .offline)
        .background { SkyBackground(level: .high) }
        .environment(\.colorScheme, .dark)
}

#Preview("No data") {
    StationMapPage(readings: nil, status: .noData)
        .background { SkyBackground(level: .high) }
        .environment(\.colorScheme, .dark)
}
