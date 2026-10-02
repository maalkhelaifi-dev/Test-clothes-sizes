import SwiftUI
import MeasureMeCore

/// Screen 7: brand and product size recommendation.
struct RecommendationView: View {
    @Environment(AppModel.self) private var model

    let profileID: UUID
    var initialCategory: ClothingCategory?
    var initialFit: FitPreference?

    @State private var brand = ""
    @State private var category: ClothingCategory = .tops
    @State private var region: SizeRegion?
    @State private var audience: SizeAudience?
    @State private var sizeSystem: String?
    @State private var productLine: String?
    @State private var fit: FitPreference = .regular
    @State private var initialised = false
    @State private var manualEntryProfile: PersonProfile?

    var body: some View {
        if let profile = model.profile(id: profileID) {
            content(profile)
        } else {
            ContentUnavailableView("Profile not found", systemImage: "person.crop.circle.badge.questionmark")
        }
    }

    private var library: SizeChartLibrary { model.chartLibrary }

    private func content(_ profile: PersonProfile) -> some View {
        let measurements = profile.latestMeasurements
        let chart = brand.isEmpty ? nil : library.bestChart(brand: brand, category: category, region: region,
                                                             audience: audience, sizeSystem: sizeSystem, productLine: productLine)
        return Form {
            selectionSection

            if library.charts.isEmpty {
                Section {
                    Text("No size charts are available. Add a chart from a brand’s official size guide in the Size charts tab, or turn on demo charts in Settings.")
                }
            } else if let chart {
                Section("Chart used") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chart.displayTitle).font(.headline)
                        Text(chart.subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let p = productLine, !p.isEmpty, chart.productLine != p {
                        Label("No chart specific to “\(p)” — using the brand-wide chart.", systemImage: "info.circle")
                            .font(.footnote)
                    }
                    ChartTrustView(chart: chart)
                }
                outcomeSections(SizeRecommender.recommend(chart: chart, measurements: measurements, fit: fit), chart: chart, unit: profile.preferredUnit, profile: profile)
                Section {
                    DisclosureGroup("Full size chart") {
                        SizeChartTable(chart: chart, unit: profile.preferredUnit)
                    }
                }
            } else {
                Section {
                    Text("No chart matches this combination. Try a different region, chart line or size system.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("Recommendations are guidance based on your measurements and the chart you selected. Fit also depends on fabric, cut and personal preference — check the brand’s fit notes and return policy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Find my size")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { initialise(profile) }
        .onChange(of: brand) { _, _ in resetBelowBrand(profile) }
        .onChange(of: category) { _, _ in resetBelowCategory(profile) }
        .onChange(of: region) { _, _ in pickAudience(profile) }
        .fullScreenCover(item: $manualEntryProfile) { p in
            MeasureFlowView(profile: p, mode: .manual)
        }
    }

    // MARK: Selection

    private var selectionSection: some View {
        Section("What are you buying?") {
            Picker("Brand", selection: $brand) {
                ForEach(library.brands, id: \.self) { Text($0).tag($0) }
            }
            Picker("Category", selection: $category) {
                ForEach(availableCategories, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Country / region", selection: $region) {
                Text("Any").tag(SizeRegion?.none)
                ForEach(library.regions(brand: brand, category: category), id: \.self) { Text($0.displayName).tag(SizeRegion?.some($0)) }
            }
            Picker("Chart line", selection: $audience) {
                Text("Any").tag(SizeAudience?.none)
                ForEach(library.audiences(brand: brand, category: category, region: region), id: \.self) {
                    Text($0.displayName).tag(SizeAudience?.some($0))
                }
            }
            let systems = library.sizeSystems(brand: brand, category: category, region: region, audience: audience)
            if systems.count > 1 {
                Picker("Size system", selection: $sizeSystem) {
                    Text("Any").tag(String?.none)
                    ForEach(systems, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }
            let lines = library.productLines(brand: brand, category: category, region: region, audience: audience, sizeSystem: sizeSystem)
            if !lines.isEmpty {
                Picker("Product / collection", selection: $productLine) {
                    Text("General brand chart").tag(String?.none)
                    ForEach(lines, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }
            Picker("Fit", selection: $fit) {
                ForEach(FitPreference.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var availableCategories: [ClothingCategory] {
        let cats = library.categories(brand: brand)
        return cats.isEmpty ? [category] : cats
    }

    private func initialise(_ profile: PersonProfile) {
        guard !initialised else { return }
        initialised = true
        fit = initialFit ?? profile.defaultFit
        let wanted = initialCategory
        if let wanted, let b = library.brands.first(where: { library.categories(brand: $0).contains(wanted) }) {
            brand = b
            category = wanted
        } else if let b = library.brands.first {
            brand = b
            category = library.categories(brand: b).first ?? .tops
        }
        pickAudience(profile)
    }

    private func resetBelowBrand(_ profile: PersonProfile) {
        let cats = library.categories(brand: brand)
        if !cats.contains(category), let first = cats.first { category = first }
        resetBelowCategory(profile)
    }

    private func resetBelowCategory(_ profile: PersonProfile) {
        region = nil
        sizeSystem = nil
        productLine = nil
        pickAudience(profile)
    }

    private func pickAudience(_ profile: PersonProfile) {
        let available = library.audiences(brand: brand, category: category, region: region)
        audience = profile.preferredAudiences.first(where: { available.contains($0) })
    }

    // MARK: Outcome

    @ViewBuilder
    private func outcomeSections(_ outcome: RecommendationOutcome, chart: SizeChart, unit: LengthUnit, profile: PersonProfile) -> some View {
        switch outcome {
        case .recommended(let r):
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Size \(r.size)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                        if let alt = r.alternativeSize {
                            Text("or \(alt)")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Recommended size \(r.size)\(r.alternativeSize.map { ", or \($0)" } ?? "")")
                    HStack {
                        ConfidenceBadge(confidence: r.confidence)
                        if r.isDemoChart { DemoDataBadge() }
                    }
                    if let reason = r.alternativeReason {
                        Label(reason, systemImage: "arrow.left.arrow.right")
                            .font(.subheadline)
                    }
                }
            } header: {
                Text("Recommendation")
            }

            Section {
                ForEach(r.comparisons) { c in
                    ComparisonRow(comparison: c, sizeLabel: r.size, unit: unit, chartType: chart.measurementType,
                                  isDriving: r.drivingMeasurements.contains(c.kind))
                }
            } header: {
                Text("Your measurements vs size \(r.size)")
            } footer: {
                Text("Bold measurements drove the recommendation. Ranges are \(chart.measurementType == .body ? "body measurements from the chart" : "the body sizes each garment suits, after adding wearing ease").")
            }

            if let alt = r.alternativeSize, !r.alternativeComparisons.isEmpty {
                Section {
                    DisclosureGroup("Compare with size \(alt)") {
                        ForEach(r.alternativeComparisons) { c in
                            ComparisonRow(comparison: c, sizeLabel: alt, unit: unit, chartType: chart.measurementType, isDriving: false)
                        }
                    }
                }
            }

            Section("Why") {
                ForEach(r.explanation, id: \.self) { Text($0).font(.subheadline) }
            }

        case .insufficientData(let reasons, let missing):
            Section("Not enough information") {
                ForEach(reasons, id: \.self) { Label($0, systemImage: "exclamationmark.circle") }
                if !missing.isEmpty {
                    Button("Enter \(missing.map { $0.displayName.lowercased() }.joined(separator: ", "))") {
                        manualEntryProfile = profile
                    }
                }
            }

        case .outsideChartRange(let nearest, let comparisons, let lines):
            Section("Outside this chart") {
                ForEach(lines, id: \.self) { Text($0) }
                ForEach(comparisons) { c in
                    ComparisonRow(comparison: c, sizeLabel: nearest, unit: unit, chartType: chart.measurementType, isDriving: false)
                }
            }
        }
    }
}

struct ComparisonRow: View {
    let comparison: MeasurementComparison
    let sizeLabel: String
    let unit: LengthUnit
    let chartType: ChartMeasurementType
    let isDriving: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(comparison.kind.displayName)
                    .font(isDriving ? .headline : .body)
                Spacer()
                statusIcon
            }
            HStack {
                VStack(alignment: .leading) {
                    Text("You").font(.caption).foregroundStyle(.secondary)
                    Text("\(unit.format(centimetres: comparison.userValueCM)) \(unit.formatUncertainty(centimetres: comparison.userUncertaintyCM))")
                        .font(.subheadline.monospacedDigit())
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Size \(sizeLabel)").font(.caption).foregroundStyle(.secondary)
                    Text(comparison.bodyRange.formatted(in: unit)).font(.subheadline.monospacedDigit())
                    if chartType == .garment {
                        Text("garment \(comparison.chartRange.formatted(in: unit))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if comparison.userConfidence == .low {
                Label("Low-confidence measurement", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusIcon: some View {
        let (symbol, color, text): (String, Color, String) = {
            switch comparison.status {
            case .within: return ("checkmark.circle.fill", .green, "Within range")
            case .below: return ("arrow.down.circle.fill", .orange, "\(unit.format(centimetres: -comparison.differenceCM)) below range")
            case .above: return ("arrow.up.circle.fill", .orange, "\(unit.format(centimetres: comparison.differenceCM)) above range")
            }
        }()
        return Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
    }
}

struct SizeChartTable: View {
    let chart: SizeChart
    let unit: LengthUnit

    var body: some View {
        let kinds = MeasurementKind.allCases.filter { chart.coveredMeasurements.contains($0) }
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Size").font(.caption.weight(.bold))
                    ForEach(kinds, id: \.self) { Text($0.displayName).font(.caption.weight(.bold)) }
                }
                Divider()
                ForEach(chart.sizes) { size in
                    GridRow {
                        Text(size.label).font(.subheadline.weight(.semibold))
                        ForEach(kinds, id: \.self) { k in
                            Text(size.measurements[k]?.formatted(in: unit) ?? "—")
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        Text(chart.measurementType == .garment
             ? "Garment measurements\(chart.garmentConvention == .flatHalfWidth ? " (girths measured flat — half the circumference)" : "")."
             : "Body measurements.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
