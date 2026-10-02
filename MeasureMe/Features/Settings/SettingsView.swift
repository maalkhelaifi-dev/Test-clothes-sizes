import SwiftUI
import MeasureMeCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var confirmDeleteAll = false
    @State private var confirmDeletePhotos = false
    @State private var message: String?
    @State private var capabilities = CameraCapabilities.detect()

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    InfoRow(symbol: "iphone", title: "On-device only",
                            text: "Images, depth data and measurements are processed and stored on this iPhone. This app contains no upload, sync or analytics code.")
                    InfoRow(symbol: "externaldrive.badge.xmark", title: "Excluded from backups",
                            text: "Measurement files are encrypted while the iPhone is locked and excluded from iCloud and computer backups.")
                    InfoRow(symbol: "eye.slash", title: "No sensitive inferences",
                            text: "The app measures lengths only. It does not infer age, health, ethnicity, identity or other attributes.")
                } header: {
                    Text("Privacy")
                }

                Section {
                    Toggle("Camera consent", isOn: $settings.cameraConsentGiven)
                    Toggle("Save capture photos", isOn: $settings.saveCapturePhotos)
                } header: {
                    Text("Camera")
                } footer: {
                    Text("Without camera consent, you can still enter measurements by hand. Photo saving is off by default: frames are analysed in memory and discarded. When on, one photo per view is kept on this iPhone with the session, and can be deleted at any time.")
                }

                Section("Capture") {
                    Toggle("Spoken guidance", isOn: $settings.voiceGuidance)
                    if capabilities.hasLiDARDepthCamera {
                        Toggle("Use LiDAR depth as a cross-check", isOn: $settings.useDepthWhenAvailable)
                    }
                    Picker("Default units", selection: $settings.defaultUnit) {
                        ForEach(LengthUnit.allCases) { Text($0.displayName).tag($0) }
                    }
                    NavigationLink("This iPhone’s camera features") {
                        List(capabilities.rows) { row in
                            HStack(alignment: .top) {
                                Image(systemName: row.available ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(row.available ? .green : .secondary)
                                    .accessibilityLabel(row.available ? "Available" : "Not available")
                                VStack(alignment: .leading) {
                                    Text(row.name)
                                    Text(row.usage).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .navigationTitle("Camera features")
                    }
                }

                Section("Size charts") {
                    Toggle("Show demo charts", isOn: $settings.showDemoCharts)
                }

                Section("About the estimates") {
                    NavigationLink("Accuracy and limitations") { LimitationsView() }
                }

                Section {
                    Button("Delete all saved capture photos (\(model.savedPhotoCount))", role: .destructive) {
                        confirmDeletePhotos = true
                    }
                    .disabled(model.savedPhotoCount == 0)
                    Button("Delete all data", role: .destructive) { confirmDeleteAll = true }
                } header: {
                    Text("Delete data")
                } footer: {
                    Text("“Delete all data” removes every profile, measurement, saved photo and chart you added, and resets settings. Individual profiles and sessions can be deleted from the Profiles tab.")
                }
            }
            .navigationTitle("Privacy & settings")
            .confirmationDialog("Delete all saved photos?", isPresented: $confirmDeletePhotos, titleVisibility: .visible) {
                Button("Delete photos", role: .destructive) {
                    do { try model.deleteAllCapturePhotos() } catch { message = error.localizedDescription }
                }
            } message: {
                Text("Measurements are kept. Photos cannot be recovered.")
            }
            .confirmationDialog("Delete all data?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    do { try model.deleteAllData() } catch { message = error.localizedDescription }
                }
            } message: {
                Text("This permanently deletes all profiles, measurements, photos and your size charts from this iPhone.")
            }
            .alert("Something went wrong", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }
}

struct LimitationsView: View {
    var body: some View {
        List {
            Section("How estimates are made") {
                Text("Your height sets the scale. Vision finds body landmarks and separates your outline from the background. Lengths come from landmarks; girths such as chest, waist and hips are estimated as ellipses from your front width and side depth.")
                Text("If your iPhone has LiDAR, depth is used only to cross-check the scale and the 3D pose height — it never replaces the height you entered.")
            }
            Section("What affects accuracy") {
                Text("• Loose or thick clothing, hair covering the neck or shoulders\n• Height entered incorrectly or measured with shoes\n• Phone tilted, too close, or not at waist height\n• Arms touching the body, or feet together\n• Poor lighting or a busy background")
            }
            Section("Not estimated by the camera") {
                ForEach(MeasurementKind.allCases.filter { $0.cameraSupport == .manualOnly }, id: \.self) { k in
                    Text(k.displayName)
                }
                Text("These can’t be seen reliably through clothing at full-body distance. Enter them with a tape measure.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Rough estimates only") {
                ForEach(MeasurementKind.allCases.filter { $0.cameraSupport == .lowConfidenceSilhouette }, id: \.self) { k in
                    Text(k.displayName)
                }
                Text("Always marked low confidence. Check with a tape measure if they matter for your purchase.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Calibration") {
                Text("The geometric model has not yet been calibrated against a large group of tape-measured volunteers. Treat every estimate as approximate, and compare it with a tape measure before relying on it for an expensive or non-returnable purchase.")
            }
        }
        .navigationTitle("Accuracy & limitations")
    }
}
