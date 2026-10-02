import SwiftUI

/// Screen 1: welcome, adult-use notice, privacy explanation and explicit consent.
struct WelcomeView: View {
    @Environment(AppSettings.self) private var settings
    @State private var step = 0
    @State private var isAdult = false
    @State private var understandsEstimates = false
    @State private var cameraConsent = false

    private let stepCount = 4

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(stepCount))
                    .padding(.horizontal)
                    .accessibilityLabel("Step \(step + 1) of \(stepCount)")
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch step {
                        case 0: welcome
                        case 1: adultNotice
                        case 2: privacy
                        default: consent
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                footer
            }
            .navigationTitle("Measure Me")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "figure.stand")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Find your size with your iPhone camera")
                .font(.largeTitle.bold())
            Text("Measure Me guides you through a few photos, estimates your body measurements, and compares them with brand size charts.")
                .font(.body)
            InfoRow(symbol: "ruler", title: "Estimates, not tailoring",
                    text: "Camera estimates are approximate. Every value shows a confidence level and can be corrected with a tape measure.")
            InfoRow(symbol: "pencil", title: "You stay in control",
                    text: "You can edit any measurement, or skip the camera and type your measurements in.")
            InfoRow(symbol: "tablecells", title: "Charts from the source",
                    text: "Size charts are stored as data with a link to the brand’s official page. Sample charts are clearly marked as demo data.")
        }
    }

    private var adultNotice: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "person.badge.shield.checkmark")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("For adults only")
                .font(.title.bold())
            Text("This version of Measure Me is designed for adults aged 18 and over. Please don’t create profiles or take measurements for children.")
            Toggle(isOn: $isAdult) {
                Text("I am 18 or older, and I will only measure adults who have agreed to it.")
            }
            .toggleStyle(.switch)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Your privacy")
                .font(.title.bold())
            InfoRow(symbol: "iphone", title: "Processed on this iPhone",
                    text: "Photos are analysed on-device with Apple’s Vision framework. This app has no upload feature and sends nothing over the internet.")
            InfoRow(symbol: "photo.badge.exclamationmark", title: "Photos are not kept",
                    text: "Capture frames are held in memory only while measuring, then discarded. You can choose to save them in Settings.")
            InfoRow(symbol: "eye.slash", title: "No sensitive guesses",
                    text: "The app never tries to infer age, health, ethnicity, identity or any other personal attribute. It only measures lengths.")
            InfoRow(symbol: "trash", title: "Delete any time",
                    text: "Delete a single measurement, a profile, saved photos, or everything, from within the app.")
            InfoRow(symbol: "externaldrive.badge.xmark", title: "Not in backups",
                    text: "Measurement data is excluded from iCloud and computer backups and is encrypted while your iPhone is locked.")
        }
    }

    private var consent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Your consent")
                .font(.title.bold())
            Toggle(isOn: $understandsEstimates) {
                Text("I understand camera measurements are estimates with uncertainty, and size recommendations are guidance only.")
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            Toggle(isOn: $cameraConsent) {
                Text("I agree that Measure Me may use the camera to analyse my body shape on this iPhone to estimate measurements. (Optional — you can enter measurements by hand instead.)")
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            Text("You can withdraw camera consent at any time in Privacy & settings. iOS will also ask for camera permission the first time you start a capture.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var canContinue: Bool {
        switch step {
        case 1: return isAdult
        case 3: return understandsEstimates
        default: return true
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button("Back") { withAnimation { step -= 1 } }
                    .frame(minWidth: 88, minHeight: 54)
            }
            Button(step == stepCount - 1 ? "Get started" : "Continue") {
                if step < stepCount - 1 {
                    withAnimation { step += 1 }
                } else {
                    settings.cameraConsentGiven = cameraConsent
                    settings.hasCompletedOnboarding = true
                }
            }
            .buttonStyle(.primary)
            .disabled(!canContinue)
        }
        .padding()
        .background(.bar)
    }
}

struct InfoRow: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 36)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
