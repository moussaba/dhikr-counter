import SwiftUI

// MARK: - Settings Help View

struct SettingsHelpView: View {
    @State private var expandedSections: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                // Overview
                Section {
                    Text("The TKEO (Teager-Kaiser Energy Operator) algorithm detects pinch gestures through a multi-stage pipeline: signal fusion, filtering, energy calculation, adaptive thresholding, peak detection, and template validation.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Primary Sensitivity
                HelpSection(
                    title: "Primary Sensitivity",
                    icon: "slider.horizontal.3",
                    color: .orange,
                    isExpanded: expandedSections.contains("sensitivity"),
                    toggle: { toggleSection("sensitivity") }
                ) {
                    HelpItem(
                        name: "Gate K (Gate Threshold)",
                        key: "gateK",
                        defaultValue: "3.5",
                        range: "1.0 - 6.0 σ",
                        description: "Sets the threshold for a signal peak to be considered a pinch candidate. Calculated as MAD_baseline × gateK.",
                        lowImpact: "More sensitive, detects lighter pinches, but increases false positives",
                        highImpact: "Less sensitive, requires stronger pinches, fewer false positives",
                        recommendation: "Start at 2.5-3.5. Lower if missing pinches, raise if getting false positives."
                    )

                    HelpItem(
                        name: "NCC Threshold",
                        key: "templateConfidence",
                        defaultValue: "0.6",
                        range: "0.3 - 0.9",
                        description: "Minimum correlation score when matching candidates against trained pinch templates.",
                        lowImpact: "Accepts more varied pinch patterns, may accept non-pinch movements",
                        highImpact: "Requires close match to templates, may reject valid but atypical pinches",
                        recommendation: "0.55-0.65 is typically good. Lower if valid pinches are rejected."
                    )

                    HelpItem(
                        name: "Gyro Veto Threshold",
                        key: "gyroVetoThresh",
                        defaultValue: "2.5",
                        range: "0.5 - 5.0 rad/s",
                        description: "Rejects candidates during significant wrist rotation. High gyroscope activity indicates arm movement.",
                        lowImpact: "Strict motion rejection, may miss pinches during movement",
                        highImpact: "Allows pinches during more movement, may accept false positives",
                        recommendation: "2.0-3.0. Raise if doing dhikr while walking."
                    )

                    HelpItem(
                        name: "Amplitude Surplus",
                        key: "amplitudeSurplusThresh",
                        defaultValue: "2.5",
                        range: "1.0 - 5.0 σ",
                        description: "Requires peak to exceed local baseline by this many standard deviations.",
                        lowImpact: "Accepts weaker signals, more sensitive",
                        highImpact: "Requires stronger, more distinct peaks",
                        recommendation: "2.0-3.0. Similar effect to gateK but filters on peak prominence."
                    )
                }

                // Timing Parameters
                HelpSection(
                    title: "Timing Parameters",
                    icon: "clock",
                    color: .blue,
                    isExpanded: expandedSections.contains("timing"),
                    toggle: { toggleSection("timing") }
                ) {
                    HelpItem(
                        name: "ISI Threshold",
                        key: "isiThresholdMs",
                        defaultValue: "220",
                        range: "100 - 500 ms",
                        description: "Minimum time between consecutive detections. Prevents double-counting.",
                        lowImpact: "Allows rapid consecutive pinches, may double-count",
                        highImpact: "Ensures separation, may miss rapid deliberate pinches",
                        recommendation: "200-300ms for normal pace. Lower for rapid counting."
                    )

                    HelpItem(
                        name: "Refractory Period",
                        key: "refractoryMs",
                        defaultValue: "150",
                        range: "50 - 300 ms",
                        description: "Hard lockout period after detection during which no new candidates are considered.",
                        lowImpact: "More responsive to rapid pinches",
                        highImpact: "More conservative, prevents artifacts",
                        recommendation: "100-200ms. Similar to ISI but acts earlier."
                    )

                    HelpItem(
                        name: "Gyro Veto Hold",
                        key: "gyroVetoHoldMs",
                        defaultValue: "100",
                        range: "0 - 300 ms",
                        description: "After high gyro activity, requires this duration of quiet before enabling detection.",
                        lowImpact: "Quick recovery after movement",
                        highImpact: "Ensures arm has settled before detecting",
                        recommendation: "80-150ms."
                    )

                    HelpItem(
                        name: "Min/Max Width",
                        key: "minWidthMs / maxWidthMs",
                        defaultValue: "70 / 350",
                        range: "ms",
                        description: "Acceptable duration range for a pinch event. Events outside this range are rejected.",
                        lowImpact: "minWidth filters brief noise spikes",
                        highImpact: "maxWidth filters slow movements",
                        recommendation: "Typical pinch: 80-250ms."
                    )
                }

                // Signal Processing
                HelpSection(
                    title: "Signal Processing",
                    icon: "waveform.path.ecg",
                    color: .purple,
                    isExpanded: expandedSections.contains("signal"),
                    toggle: { toggleSection("signal") }
                ) {
                    HelpItem(
                        name: "Sample Rate",
                        key: "sampleRate",
                        defaultValue: "50",
                        range: "Hz",
                        description: "Rate at which sensor data is collected. Should match actual sensor update rate.",
                        lowImpact: "N/A",
                        highImpact: "N/A",
                        recommendation: "Keep at 50Hz unless you know what you're doing."
                    )

                    HelpItem(
                        name: "Bandpass Filter",
                        key: "bandpassLow / bandpassHigh",
                        defaultValue: "3.0 / 20.0",
                        range: "Hz",
                        description: "Frequency band of interest. Removes slow drift (low) and high-frequency noise (high).",
                        lowImpact: "Low cutoff removes gravity effects",
                        highImpact: "High cutoff removes sensor noise",
                        recommendation: "Pinches typically 5-15 Hz. Default 3-20 Hz works well."
                    )

                    HelpItem(
                        name: "Accel/Gyro Weights",
                        key: "accelWeight / gyroWeight",
                        defaultValue: "1.0 / 1.5",
                        range: "Multiplier",
                        description: "Relative weights for combining accelerometer and gyroscope signals.",
                        lowImpact: "Higher gyro emphasizes rotational pinch signature",
                        highImpact: "Higher accel emphasizes linear motion",
                        recommendation: "Keep gyro slightly higher (1.2-1.5)."
                    )

                    HelpItem(
                        name: "MAD Window",
                        key: "madWinSec",
                        defaultValue: "3.0",
                        range: "1 - 5 seconds",
                        description: "Duration of sliding window for computing baseline (Median Absolute Deviation).",
                        lowImpact: "Shorter: adapts quickly but may be unstable",
                        highImpact: "Longer: stable baseline but slow to adapt",
                        recommendation: "2.5-3.5 seconds."
                    )
                }

                // Tuning Recommendations
                Section("Quick Tuning Guide") {
                    TuningRecommendation(
                        title: "More Sensitive",
                        description: "For detecting lighter pinches",
                        settings: ["gateK → 2.0-2.5", "NCC → 0.5", "Amplitude → 1.5-2.0", "Gyro Veto → 3.0"]
                    )

                    TuningRecommendation(
                        title: "Fewer False Positives",
                        description: "For strict detection",
                        settings: ["gateK → 4.0-5.0", "NCC → 0.7", "Amplitude → 3.0", "Gyro Veto → 1.5-2.0"]
                    )

                    TuningRecommendation(
                        title: "Active Movement",
                        description: "For dhikr while walking",
                        settings: ["Gyro Veto → 3.5-4.0", "Gyro Hold → 150-200", "gateK → slightly higher"]
                    )

                    TuningRecommendation(
                        title: "Rapid Counting",
                        description: "For fast-paced dhikr",
                        settings: ["ISI → 150-180", "Refractory → 100"]
                    )
                }

                // Debugging Tips
                Section("Debugging Tips") {
                    VStack(alignment: .leading, spacing: 8) {
                        DebugTip(rejection: "Template", solution: "Lower NCC threshold or check template match")
                        DebugTip(rejection: "Gyro Veto", solution: "Raise gyroVetoThresh if moving during dhikr")
                        DebugTip(rejection: "Amplitude", solution: "Lower amplitudeSurplus for lighter pinches")
                        DebugTip(rejection: "ISI", solution: "Raise ISI if double-counting, lower if missing rapid")
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Settings Help")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func toggleSection(_ section: String) {
        if expandedSections.contains(section) {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
        }
    }
}

// MARK: - Help Section Container

struct HelpSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    let isExpanded: Bool
    let toggle: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Section {
            Button(action: toggle) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .frame(width: 24)
                    Text(title)
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
            }
        }
    }
}

// MARK: - Help Item

struct HelpItem: View {
    let name: String
    let key: String
    let defaultValue: String
    let range: String
    let description: String
    let lowImpact: String
    let highImpact: String
    let recommendation: String

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        Text("Default: \(defaultValue) | Range: \(range)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                                .foregroundColor(.green)
                                .font(.caption2)
                            Text("Lower: \(lowImpact)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "arrow.up.circle")
                                .foregroundColor(.red)
                                .font(.caption2)
                            Text("Higher: \(highImpact)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "lightbulb")
                            .foregroundColor(.yellow)
                            .font(.caption2)
                        Text(recommendation)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                }
                .padding(.leading, 8)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tuning Recommendation

struct TuningRecommendation: View {
    let title: String
    let description: String
    let settings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("- \(description)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(settings, id: \.self) { setting in
                    Text(setting)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Debug Tip

struct DebugTip: View {
    let rejection: String
    let solution: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("Rejected by \(rejection):")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.orange)
                .frame(width: 120, alignment: .leading)
            Text(solution)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Collapsible Help Card for Settings View

struct SettingsHelpCard: View {
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundColor(.blue)
                    Text("Parameter Help Guide")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()

                    // Quick summary
                    Text("Key Parameters")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    QuickHelpRow(name: "Gate K", impact: "Main sensitivity control", tip: "Lower = more sensitive")
                    QuickHelpRow(name: "NCC Thresh", impact: "Template match strictness", tip: "Lower = more lenient")
                    QuickHelpRow(name: "Gyro Veto", impact: "Motion rejection", tip: "Higher = allows more motion")
                    QuickHelpRow(name: "ISI", impact: "Min time between pinches", tip: "Lower = faster counting")

                    Divider()

                    NavigationLink(destination: SettingsHelpView()) {
                        HStack {
                            Text("View Full Documentation")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

struct QuickHelpRow: View {
    let name: String
    let impact: String
    let tip: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name)
                    .font(.caption)
                    .fontWeight(.medium)
                Text("- \(impact)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(tip)
                .font(.caption2)
                .foregroundColor(.blue)
                .padding(.leading, 8)
        }
    }
}

#Preview {
    SettingsHelpView()
}
