import SwiftUI
import UniformTypeIdentifiers
import MeasureMeCore

/// Screen 9: brand size-chart management.
struct SizeChartListView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var creatingNew = false
    @State private var importing = false
    @State private var message: String?
    @State private var exportFile: ExportFile?

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            List {
                Section {
                    Text("Charts are stored as data on this iPhone. Add charts by copying them from a brand’s official size guide, and record the link and the date you checked it.")
                        .font(.subheadline)
                    Toggle("Show demo charts", isOn: $settings.showDemoCharts)
                }
                let brands = model.chartLibrary.brands
                if brands.isEmpty {
                    ContentUnavailableView("No charts", systemImage: "tablecells",
                                           description: Text("Tap + to add a chart from an official size guide."))
                }
                ForEach(brands, id: \.self) { brand in
                    Section(brand) {
                        ForEach(model.chartLibrary.charts(matching: .init(brand: brand))) { chart in
                            NavigationLink {
                                SizeChartDetailView(chartID: chart.id)
                            } label: {
                                ChartRow(chart: chart)
                            }
                            .swipeActions {
                                if model.isUserChart(chart.id) {
                                    Button("Delete", role: .destructive) { delete(chart) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Size charts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { creatingNew = true } label: { Label("Add chart manually", systemImage: "square.and.pencil") }
                        Button { importing = true } label: { Label("Import chart file (JSON)", systemImage: "square.and.arrow.down") }
                        if !model.userCharts.isEmpty {
                            Button { export() } label: { Label("Export my charts", systemImage: "square.and.arrow.up") }
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $creatingNew) {
                SizeChartEditorView(existing: nil)
            }
            .sheet(item: $exportFile) { file in
                ShareSheet(items: [file.url])
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .alert("Size charts", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func delete(_ chart: SizeChart) {
        do { try model.deleteChart(id: chart.id) } catch { message = error.localizedDescription }
    }

    private func export() {
        do { exportFile = ExportFile(url: try model.exportUserCharts()) } catch { message = error.localizedDescription }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let count = try model.importCharts(from: Data(contentsOf: url))
                message = "Imported \(count) \(count == 1 ? "chart" : "charts")."
            } catch {
                message = "Import failed: \(error.localizedDescription)"
            }
        case .failure(let error):
            message = error.localizedDescription
        }
    }
}

struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct ChartRow: View {
    let chart: SizeChart

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(chart.productLine.map { "\(chart.category.displayName) · \($0)" } ?? chart.category.displayName)
                    .font(.headline)
                if chart.source.isDemoData { DemoDataBadge() }
            }
            Text(chart.subtitle).font(.subheadline).foregroundStyle(.secondary)
            Text("\(chart.measurementType.displayName) · \(chart.sizes.count) sizes").font(.caption).foregroundStyle(.secondary)
            if !chart.source.isDemoData {
                Text(chart.trustLabel).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SizeChartDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    let chartID: UUID
    @State private var editing: SizeChart?
    @State private var message: String?

    var body: some View {
        if let chart = model.chartLibrary.chart(id: chartID) {
            let isUser = model.isUserChart(chart.id)
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chart.displayTitle).font(.headline)
                        Text(chart.subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    ChartTrustView(chart: chart)
                    if let notes = chart.source.notes, !notes.isEmpty {
                        Text(notes).font(.footnote)
                    }
                }
                Section("Sizes") {
                    SizeChartTable(chart: chart, unit: settings.defaultUnit)
                }
                let warnings = SizeChartValidator.warnings(for: chart)
                if !warnings.isEmpty {
                    Section("Consistency hints") {
                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, w in
                            Text(describe(w)).font(.footnote)
                        }
                    }
                }
                Section {
                    if isUser {
                        Button("Edit or update chart") { editing = chart }
                        Button("Mark as re-verified today") {
                            var c = chart
                            c.source.lastVerified = Date()
                            do { try model.saveChart(c) } catch { message = error.localizedDescription }
                        }
                        .disabled(chart.source.url == nil)
                        Button("Delete chart", role: .destructive) {
                            do { try model.deleteChart(id: chart.id); dismiss() } catch { message = error.localizedDescription }
                        }
                    } else {
                        Text("Demo charts are read-only. To add a real chart, copy the values from the brand’s official size guide into a new chart.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Use as a template for a new chart") {
                            var copy = chart
                            copy.id = UUID()
                            copy.brand = ""
                            copy.productLine = nil
                            copy.source = ChartSource(url: nil, lastVerified: nil, isDemoData: false)
                            editing = copy
                        }
                    }
                }
            }
            .navigationTitle("Size chart")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { c in
                SizeChartEditorView(existing: c)
            }
            .alert("Size chart", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        } else {
            ContentUnavailableView("Chart not available", systemImage: "tablecells.badge.ellipsis")
        }
    }

    private func describe(_ w: SizeChartWarning) -> String {
        switch w {
        case .sizesNotIncreasing(let k): return "\(k.displayName) values don’t increase from size to size. Check the order of sizes."
        case .overlappingRanges(let k, let a, let b): return "\(k.displayName) ranges for \(a) and \(b) overlap. This happens in some brand charts; double-check against the source."
        case .gapBetweenSizes(let k, let a, let b): return "There is a gap in \(k.displayName.lowercased()) between \(a) and \(b)."
        }
    }
}
