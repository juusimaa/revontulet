import AuroraCore
import SwiftUI

/// Choose a Finnish municipality by name, or go back to the current location (FR-010).
/// Searches the bundled list only; nothing is sent over the network.
struct PlacePickerView: View {
    /// nil while the bundled municipalities are still loading.
    let resolver: PlaceResolver?
    let selection: PlaceSelection
    let preferSwedish: Bool
    let onChoose: (PlaceSelection) -> Void

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        // Searched and sorted once per update, not once per use.
        let results = municipalities
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section {
                        CurrentLocationRow(isSelected: selection == .currentLocation) { choose(.currentLocation) }
                    }
                }
                Section {
                    ForEach(results) { municipality in
                        MunicipalityRow(
                            municipality: municipality, preferSwedish: preferSwedish,
                            isSelected: selection == .municipality(code: municipality.code)
                        ) {
                            choose(.municipality(code: municipality.code))
                        }
                    }
                } header: {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Municipalities")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { SkyBackground(level: nil, animated: false).environment(\.colorScheme, systemColorScheme) }
            .overlay {
                if resolver == nil {
                    ProgressView()
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            // The default placement puts search at the bottom, away from the close button.
            .searchable(text: $query, prompt: Text("Municipality in Finnish or Swedish"))
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .navigationTitle("Choose place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .accessibilityIdentifier("closePlacePicker")
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var municipalities: [Municipality] {
        guard let resolver else { return [] }
        let results = resolver.search(query, limit: 400)
        // The core lists by Finnish name; a Swedish list is alphabetical by the names it shows.
        guard preferSwedish, query.trimmingCharacters(in: .whitespaces).isEmpty else { return results }
        let swedish = Locale(identifier: "sv_FI")
        return results.sorted {
            $0.displayName(preferSwedish: true).compare($1.displayName(preferSwedish: true), locale: swedish)
                == .orderedAscending
        }
    }

    private func choose(_ newSelection: PlaceSelection) {
        onChoose(newSelection)
        dismiss()
    }
}

private struct CurrentLocationRow: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "location.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PlacePickerStyle.glow)
                    .frame(width: 36, height: 36)
                    .background(PlacePickerStyle.green.opacity(0.14), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use current location")
                        .font(.body.weight(.semibold))
                    Text("Your location stays on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                SelectedMark(isSelected: isSelected)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.white.opacity(0.07))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("useCurrentLocation")
    }
}

private struct MunicipalityRow: View {
    let municipality: Municipality
    let preferSwedish: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(municipality.displayName(preferSwedish: preferSwedish))
                        .font(.body.weight(.medium))
                    // The name in the other language, so "Helsingfors" is recognisable as Helsinki.
                    if let other = otherName {
                        Text(other)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                SelectedMark(isSelected: isSelected)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.white.opacity(0.05))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("municipality-\(municipality.code)")
    }

    private var otherName: String? {
        guard let nameSv = municipality.nameSv else { return nil }
        return preferSwedish ? municipality.nameFi : nameSv
    }
}

private struct SelectedMark: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: "checkmark")
            .font(.body.weight(.bold))
            .foregroundStyle(PlacePickerStyle.glow)
            .opacity(isSelected ? 1 : 0)
            .accessibilityHidden(true)
    }
}

enum PlacePickerStyle {
    static let green = Color(red: 0.24, green: 0.96, blue: 0.62)
    static let glow = LinearGradient(
        colors: [green, Color(red: 0.16, green: 0.80, blue: 0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)
}
