import SwiftUI
import MeasureMeCore

/// A text field bound to a centimetre value, displayed and edited in the chosen unit.
struct LengthField: View {
    let title: String
    @Binding var valueCM: Double?
    let unit: LengthUnit

    @State private var text = ""
    @State private var isInvalid = false

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 70)
                .foregroundStyle(isInvalid ? .red : .primary)
            Text(unit.symbol)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), in \(unit == .centimetres ? "centimetres" : "inches")")
        .onAppear { text = formatted(valueCM) }
        .onChange(of: unit) { _, _ in text = formatted(valueCM) }
        .onChange(of: valueCM) { _, newValue in
            // Keep the text in sync when the value changes elsewhere (e.g. "revert").
            let parsed = unit.parseToCentimetres(text)
            if parsed.map({ abs($0 - (newValue ?? -1)) > 0.01 }) ?? (newValue != nil) {
                text = formatted(newValue)
            }
        }
        .onChange(of: text) { _, newText in
            // Text set from the stored value (not typed by the user) must not count as an edit.
            if newText == formatted(valueCM) {
                isInvalid = false
                return
            }
            let trimmed = newText.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                isInvalid = false
                if valueCM != nil { valueCM = nil }
            } else if let cm = unit.parseToCentimetres(trimmed) {
                isInvalid = false
                if valueCM.map({ abs($0 - cm) > 0.001 }) ?? true { valueCM = cm }
            } else {
                isInvalid = true
            }
        }
    }

    private func formatted(_ cm: Double?) -> String {
        guard let cm else { return "" }
        let v = unit.fromCentimetres(cm)
        return unit == .centimetres ? String(format: "%.1f", v) : String(format: "%.2f", v)
    }
}

/// Height input: centimetres, or feet + inches for imperial users.
struct HeightField: View {
    @Binding var heightCM: Double?
    let unit: LengthUnit

    @State private var feet = ""
    @State private var inches = ""

    var body: some View {
        switch unit {
        case .centimetres:
            LengthField(title: "Height", valueCM: $heightCM, unit: .centimetres)
        case .inches:
            HStack {
                TextField("ft", text: $feet)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Height, feet")
                Text("ft").foregroundStyle(.secondary)
                TextField("in", text: $inches)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Height, inches")
                Text("in").foregroundStyle(.secondary)
            }
            .onAppear {
                if let h = heightCM {
                    let fi = FeetInches(centimetres: h)
                    feet = "\(fi.feet)"
                    inches = String(format: "%.0f", fi.inches)
                }
            }
            .onChange(of: feet) { _, _ in update() }
            .onChange(of: inches) { _, _ in update() }
        }
    }

    private func update() {
        guard let f = Int(feet.trimmingCharacters(in: .whitespaces)) else { heightCM = nil; return }
        let i = Double(inches.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) ?? 0
        heightCM = FeetInches(feet: f, inches: i).centimetres
    }
}
