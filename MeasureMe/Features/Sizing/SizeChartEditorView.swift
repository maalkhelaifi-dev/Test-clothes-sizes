import SwiftUI
import MeasureMeCore

/// Add or update a size chart copied from an official source.
/// The source URL and verification date are required, so charts are never invented.
@MainActor
struct SizeChartEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let existing: SizeChart?

    struct DraftSize: Identifiable {
        let id = UUID()
        var label = ""
        var minCM: [MeasurementKind: Double] = [:]
        var maxCM: [MeasurementKind: Double] = [:]
    }

    @State private var chartID = UUID()
    @State private var brand = ""
    @State private var productLine = ""
    @State private var category: ClothingCategory = .tops
    @State private var audience: SizeAudience = .unisex
    @State private var region: SizeRegion = .international
    @State private var sizeSystem = ""
    @State private var measurementType: ChartMeasurementType = .body
    @State private var convention: GarmentMeasurementConvention = .fullCircumference
    @State private var unit: LengthUnit = .centimetres
    @State private var useRanges = true
    @State private var kinds: Set<MeasurementKind> = []
    @State private var sizes: [DraftSize] = [DraftSize()]
    @State private var sourceURL = ""
    @State private var verified = Date()
    @State private var notes = ""
    @State private var errorMessage: String?
    @State private var loaded = false

    private var orderedKinds: [MeasurementKind] { MeasurementKind.allCases.filter { kinds.contains($0) } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Chart") {
                    TextField("Brand", text: $brand)
                    TextField("Product line / collection / garment (optional)", text: $productLine)
                    Picker("Category", selection: $category) {
                        ForEach(ClothingCategory.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Chart line", selection: $audience) {
                        ForEach(SizeAudience.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Region", selection: $region) {
                        ForEach(SizeRegion.allCases) { Text($0.displayName).tag($0) }
                    }
                    TextField("Size system (e.g. Letter, EU numeric, UK)", text: $sizeSystem)
                }

                Section {
                    Picker("Chart lists", selection: $measurementType) {
                        ForEach(ChartMeasurementType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    if measurementType == .garment {
                        Picker("Girths are", selection: $convention) {
                            ForEach(GarmentMeasurementConvention.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                    }
                    Picker("Values are in", selection: $unit) {
                        ForEach(LengthUnit.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Chart gives ranges (min–max)", isOn: $useRanges)
                } header: {
                    Text("Measurement type")
                } footer: {
                    Text(measurementType.explanation)
                }

                Section("Measurements in this chart") {
                    ForEach(MeasurementKind.allCases.filter { $0 != .height || measurementType == .body }, id: \.self) { kind in
                        Toggle(kind.displayName, isOn: Binding(
                            get: { kinds.contains(kind) },
                            set: { on in if on { kinds.insert(kind) } else { kinds.remove(kind) } }))
                    }
                }

                ForEach(sizes) { size in
                    Section {
                        TextField("Size label (e.g. M, 40, 32R)", text: labelBinding(size.id))
                        ForEach(orderedKinds, id: \.self) { kind in
                            HStack {
                                Text(kind.displayName).font(.subheadline)
                                Spacer()
                                LengthField(title: useRanges ? "min" : "value", valueCM: rangeBinding(size.id, kind, isMax: false), unit: unit)
                                    .frame(maxWidth: 110)
                                if useRanges {
                                    Text("–")
                                    LengthField(title: "max", valueCM: rangeBinding(size.id, kind, isMax: true), unit: unit)
                                        .frame(maxWidth: 110)
                                }
                            }
                        }
                        if sizes.count > 1 {
                            Button("Remove this size", role: .destructive) {
                                let id = size.id
                                // Defer removal so fields in the row finish updating first.
                                DispatchQueue.main.async {
                                    withAnimation { sizes.removeAll { $0.id == id } }
                                }
                            }
                        }
                    } header: {
                        Text(size.label.isEmpty ? "Size" : "Size \(size.label)")
                    }
                }
                Section {
                    Button {
                        sizes.append(DraftSize())
                    } label: {
                        Label("Add size", systemImage: "plus")
                    }
                } footer: {
                    Text("Add sizes from smallest to largest.")
                }

                Section {
                    TextField("https://brand.example/size-guide", text: $sourceURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    DatePicker("Last verified", selection: $verified, in: ...Date(), displayedComponents: .date)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                    if let url = validURL {
                        Link(destination: url) { Label("Open source page to check", systemImage: "safari") }
                    }
                } header: {
                    Text("Official source (required)")
                } footer: {
                    Text("Copy values exactly from the brand’s official size guide. Recording the link and date lets you re-check the chart when the brand updates it. Opening the link uses Safari; this app itself never downloads anything.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existing.map { $0.brand.isEmpty ? "New chart" : "Edit \($0.brand)" } ?? "New chart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear(perform: load)
            .onChange(of: category) { _, newValue in
                if kinds.isEmpty { kinds = Set(newValue.primaryMeasurements) }
            }
        }
    }

    // Bindings look sizes up by id, so a removed row can never index out of range.
    private func labelBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { sizes.first { $0.id == id }?.label ?? "" },
            set: { v in if let i = sizes.firstIndex(where: { $0.id == id }) { sizes[i].label = v } })
    }

    private func rangeBinding(_ id: UUID, _ kind: MeasurementKind, isMax: Bool) -> Binding<Double?> {
        Binding(
            get: {
                guard let s = sizes.first(where: { $0.id == id }) else { return nil }
                return isMax ? s.maxCM[kind] : s.minCM[kind]
            },
            set: { v in
                guard let i = sizes.firstIndex(where: { $0.id == id }) else { return }
                if isMax { sizes[i].maxCM[kind] = v } else { sizes[i].minCM[kind] = v }
            })
    }

    private var validURL: URL? {
        guard let url = URL(string: sourceURL.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host != nil else { return nil }
        return url
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let c = existing else {
            kinds = Set(category.primaryMeasurements)
            return
        }
        chartID = c.id
        brand = c.brand
        productLine = c.productLine ?? ""
        category = c.category
        audience = c.audience
        region = c.region
        sizeSystem = c.sizeSystem
        measurementType = c.measurementType
        convention = c.garmentConvention ?? .fullCircumference
        kinds = c.coveredMeasurements
        useRanges = c.sizes.contains { s in s.measurements.values.contains { !$0.isPoint } }
        sizes = c.sizes.map { s in
            var d = DraftSize()
            d.label = s.label
            for (k, r) in s.measurements {
                d.minCM[k] = r.minCM
                d.maxCM[k] = r.maxCM
            }
            return d
        }
        if sizes.isEmpty { sizes = [DraftSize()] }
        sourceURL = c.source.url?.absoluteString ?? ""
        verified = c.source.lastVerified ?? Date()
        notes = c.source.notes ?? ""
    }

    private func save() {
        guard let url = validURL else {
            errorMessage = "Enter the full web address (https://…) of the brand’s official size guide."
            return
        }
        var entries: [SizeEntry] = []
        for draft in sizes {
            let label = draft.label.trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else {
                errorMessage = "Every size needs a label."
                return
            }
            var ranges: [MeasurementKind: MeasurementRange] = [:]
            for kind in orderedKinds {
                guard let lo = draft.minCM[kind] else { continue }
                let hi = useRanges ? (draft.maxCM[kind] ?? lo) : lo
                ranges[kind] = MeasurementRange(minCM: lo, maxCM: hi)
            }
            entries.append(SizeEntry(label: label, measurements: ranges))
        }
        let trimmedLine = productLine.trimmingCharacters(in: .whitespaces)
        let chart = SizeChart(
            id: chartID,
            brand: brand.trimmingCharacters(in: .whitespaces),
            productLine: trimmedLine.isEmpty ? nil : trimmedLine,
            category: category, audience: audience, region: region,
            sizeSystem: sizeSystem.trimmingCharacters(in: .whitespaces).isEmpty ? "Standard" : sizeSystem,
            measurementType: measurementType,
            garmentConvention: measurementType == .garment ? convention : nil,
            sizes: entries,
            source: ChartSource(url: url, lastVerified: verified, isDemoData: false, notes: notes.isEmpty ? nil : notes))
        do {
            try model.saveChart(chart)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
