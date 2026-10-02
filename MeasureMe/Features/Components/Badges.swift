import SwiftUI
import MeasureMeCore

@MainActor
struct ConfidenceBadge: View {
    let confidence: ConfidenceLevel

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(confidence.displayName)
    }

    private var title: String {
        switch confidence {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

    private var symbol: String {
        switch confidence {
        case .high: return "checkmark.seal.fill"
        case .medium: return "circle.lefthalf.filled"
        case .low: return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        }
    }
}

@MainActor
struct SourceBadge: View {
    let source: MeasurementSource

    var body: some View {
        Label(source.displayName, systemImage: source == .manual ? "ruler" : (source == .cameraEdited ? "pencil" : "camera"))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Prominent label shown wherever demo chart data appears.
@MainActor
struct DemoDataBadge: View {
    var body: some View {
        Label("DEMO DATA", systemImage: "exclamationmark.octagon.fill")
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.purple.opacity(0.15), in: Capsule())
            .foregroundStyle(.purple)
            .accessibilityLabel("Demo data. Fictional brand, not a real size chart.")
    }
}

@MainActor
struct ChartTrustView: View {
    let chart: SizeChart

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if chart.source.isDemoData {
                DemoDataBadge()
                Text("This is a fictional sample chart for trying the app. Do not use it to buy clothes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Label(chart.trustLabel, systemImage: "checkmark.shield")
                    .font(.footnote)
                if let url = chart.source.url {
                    Link(destination: url) {
                        Label("Open official size guide", systemImage: "safari")
                    }
                    .font(.footnote)
                }
            }
            Text("\(chart.measurementType.displayName). \(chart.measurementType.explanation)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Big, accessible primary button style used across the main journey.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(isEnabled ? Color.accentColor : Color.gray.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
