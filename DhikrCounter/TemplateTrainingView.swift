import SwiftUI
import Charts

// MARK: - Template Training Data Structures

/// Represents a user-marked peak for template training
struct LabeledPeak: Identifiable, Codable {
    let id: UUID
    let timestamp: TimeInterval  // Relative to session start
    let peakIndex: Int
    var isConfirmed: Bool  // All user marks are confirmed
    let positionContext: String?

    init(timestamp: TimeInterval, peakIndex: Int, isConfirmed: Bool = true, positionContext: String? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.peakIndex = peakIndex
        self.isConfirmed = isConfirmed
        self.positionContext = positionContext
    }
}

/// Trained template set with metadata
struct TrainedTemplateSet: Codable {
    let templates: [[Float]]
    let templateLength: Int
    let confidenceThreshold: Float
    let positionContext: String?
    let sourceSessionId: String
    let createdAt: Date
    let sampleRate: Float

    var templateCount: Int { templates.count }
}

/// Template training manager
class TemplateTrainingManager: ObservableObject {
    static let shared = TemplateTrainingManager()

    @Published var labeledPeaks: [LabeledPeak] = []
    @Published var currentPositionContext: String = "sitting"
    @Published var trainedTemplateSets: [TrainedTemplateSet] = []

    private let templatesKey = "trainedTemplateSets"

    init() {
        loadSavedTemplates()
    }

    // MARK: - Peak Labeling

    func addUserMark(at index: Int, timestamp: TimeInterval) {
        let peak = LabeledPeak(
            timestamp: timestamp,
            peakIndex: index,
            isConfirmed: true,
            positionContext: currentPositionContext
        )
        labeledPeaks.append(peak)
    }

    func removeMark(id: UUID) {
        labeledPeaks.removeAll { $0.id == id }
    }

    func clearLabels() {
        labeledPeaks.removeAll()
    }

    var confirmedPeaks: [LabeledPeak] {
        labeledPeaks.filter { $0.isConfirmed }
    }

    // MARK: - Template Extraction

    func extractTemplates(from sensorData: [SensorReading], sessionId: String, userMarks: [LabeledPeak], fs: Float = 50.0) -> TrainedTemplateSet? {
        guard userMarks.count >= 3 else {
            print("Need at least 3 user marks to train templates")
            return nil
        }

        let frames = PinchDetector.convertSensorReadings(sensorData)
        guard !frames.isEmpty else { return nil }

        let fusedSignal = computeFusedSignal(frames: frames, fs: fs)
        guard fusedSignal.count == frames.count else { return nil }

        let windowPreMs: Float = 150
        let windowPostMs: Float = 150
        let preS = Int(round(windowPreMs * fs / 1000))
        let postS = Int(round(windowPostMs * fs / 1000))
        let templateLength = preS + postS + 1

        var templates: [[Float]] = []

        for mark in userMarks {
            let idx = mark.peakIndex
            guard idx >= preS && idx < fusedSignal.count - postS else { continue }

            var window = Array(fusedSignal[(idx - preS)...(idx + postS)])

            // Z-normalize
            let mean = window.reduce(0, +) / Float(window.count)
            let variance = window.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(window.count)
            let std = sqrt(variance)

            if std > 1e-6 {
                window = window.map { ($0 - mean) / std }
            }

            templates.append(window)
        }

        guard !templates.isEmpty else { return nil }

        let templateSet = TrainedTemplateSet(
            templates: templates,
            templateLength: templateLength,
            confidenceThreshold: 0.6,
            positionContext: currentPositionContext,
            sourceSessionId: sessionId,
            createdAt: Date(),
            sampleRate: fs
        )

        trainedTemplateSets.append(templateSet)
        saveTemplates()

        print("Extracted \(templates.count) templates from \(userMarks.count) user marks")
        return templateSet
    }

    private func computeFusedSignal(frames: [SensorFrame], fs: Float) -> [Float] {
        guard frames.count > 2 else { return [] }

        var ax = [Float](), ay = [Float](), az = [Float]()
        var gx = [Float](), gy = [Float](), gz = [Float]()

        for frame in frames {
            ax.append(frame.ax); ay.append(frame.ay); az.append(frame.az)
            gx.append(frame.gx); gy.append(frame.gy); gz.append(frame.gz)
        }

        func tkeo(_ x: [Float]) -> [Float] {
            guard x.count >= 3 else { return Array(repeating: 0, count: x.count) }
            var y = [Float](repeating: 0, count: x.count)
            y[0] = x[0] * x[0]
            y[y.count - 1] = x[y.count - 1] * x[y.count - 1]
            for i in 1..<(x.count - 1) {
                let v = x[i] * x[i] - x[i - 1] * x[i + 1]
                y[i] = v > 0 ? v : 0
            }
            return y
        }

        let axT = tkeo(ax), ayT = tkeo(ay), azT = tkeo(az)
        let gxT = tkeo(gx), gyT = tkeo(gy), gzT = tkeo(gz)

        var aT = [Float](repeating: 0, count: axT.count)
        var gT = [Float](repeating: 0, count: gxT.count)
        for i in 0..<axT.count {
            aT[i] = sqrt(axT[i] * axT[i] + ayT[i] * ayT[i] + azT[i] * azT[i])
            gT[i] = sqrt(gxT[i] * gxT[i] + gyT[i] * gyT[i] + gzT[i] * gzT[i])
        }

        var result = [Float](repeating: 0, count: aT.count)
        for i in 0..<aT.count {
            result[i] = 1.0 * aT[i] + 1.5 * gT[i]
        }
        return result
    }

    // MARK: - Storage

    private func saveTemplates() {
        if let data = try? JSONEncoder().encode(trainedTemplateSets) {
            UserDefaults.standard.set(data, forKey: templatesKey)
        }
    }

    private func loadSavedTemplates() {
        if let data = UserDefaults.standard.data(forKey: templatesKey),
           let sets = try? JSONDecoder().decode([TrainedTemplateSet].self, from: data) {
            trainedTemplateSets = sets
        }
    }

    func deleteTemplateSet(at index: Int) {
        guard index < trainedTemplateSets.count else { return }
        trainedTemplateSets.remove(at: index)
        saveTemplates()
    }

    // MARK: - Export for Watch

    func exportForWatch() -> Data? {
        var allTemplates: [[Double]] = []

        for set in trainedTemplateSets {
            for template in set.templates {
                allTemplates.append(template.map { Double($0) })
            }
        }

        guard !allTemplates.isEmpty else { return nil }

        let exportData: [String: Any] = [
            "templates": allTemplates,
            "template_length": trainedTemplateSets.first?.templateLength ?? 16,
            "confidence_threshold": 0.6,
            "max_lag": 3,
            "config": [
                "fs": 50,
                "bandpass_low": 3.0,
                "bandpass_high": 20.0
            ],
            "source_session": [
                "created": ISO8601DateFormatter().string(from: Date()),
                "template_count": allTemplates.count
            ]
        ]

        return try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }

    func syncToWatch() {
        guard let templateData = exportForWatch() else {
            print("No templates to sync")
            return
        }

        if let json = try? JSONSerialization.jsonObject(with: templateData) as? [String: Any] {
            Task { @MainActor in
                PhoneSessionManager.shared.sendTrainedTemplates(json)
            }
        }
    }
}

// MARK: - Template Training View (Entry Point)

struct TemplateTrainingView: View {
    let session: DhikrSession
    let sensorData: [SensorReading]

    @StateObject private var trainingManager = TemplateTrainingManager.shared
    @State private var showFullScreenLabeler = false
    @State private var userMarkedPeaks: [LabeledPeak] = []
    @State private var showingExportAlert = false
    @State private var exportMessage = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Instructions
                instructionsCard

                // Position picker
                positionPicker

                // Open full-screen labeler button
                Button {
                    showFullScreenLabeler = true
                } label: {
                    HStack {
                        Image(systemName: "hand.tap")
                        Text("Open Full-Screen Labeler")
                        Spacer()
                        Text("\(userMarkedPeaks.count) marks")
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

                // Marked peaks summary
                if !userMarkedPeaks.isEmpty {
                    markedPeaksSummary
                }

                // Action buttons
                actionButtons
            }
            .padding()
        }
        .navigationTitle("Train Templates")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showFullScreenLabeler) {
            FullScreenPeakLabeler(
                sensorData: sensorData,
                userMarkedPeaks: $userMarkedPeaks,
                positionContext: trainingManager.currentPositionContext
            )
        }
        .alert("Template Training", isPresented: $showingExportAlert) {
            Button("OK") { }
        } message: {
            Text(exportMessage)
        }
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How to Train Templates", systemImage: "info.circle")
                .font(.headline)

            Text("1. Select your position (sitting/standing/walking)")
                .font(.caption)
            Text("2. Open the full-screen labeler")
                .font(.caption)
            Text("3. Pinch and zoom to navigate the signal")
                .font(.caption)
            Text("4. TAP where YOU performed pinches (even if algorithm missed them)")
                .font(.caption)
                .fontWeight(.medium)
            Text("5. Mark at least 5-10 pinches for best results")
                .font(.caption)
            Text("6. Extract templates and sync to Watch")
                .font(.caption)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var positionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Position Context")
                .font(.subheadline)
                .fontWeight(.medium)

            Picker("Position", selection: $trainingManager.currentPositionContext) {
                Text("Sitting").tag("sitting")
                Text("Standing").tag("standing")
                Text("Walking").tag("walking")
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var markedPeaksSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Marked Pinches")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Button("Clear") {
                    userMarkedPeaks.removeAll()
                }
                .font(.caption)
                .foregroundColor(.red)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(userMarkedPeaks.sorted(by: { $0.timestamp < $1.timestamp })) { peak in
                        Text(String(format: "%.1fs", peak.timestamp))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                extractTemplates()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("Extract Templates (\(userMarkedPeaks.count) marks)")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(userMarkedPeaks.count < 3)

            Button {
                trainingManager.syncToWatch()
                exportMessage = "Templates synced to Watch!"
                showingExportAlert = true
            } label: {
                HStack {
                    Image(systemName: "applewatch")
                    Text("Sync to Watch")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(trainingManager.trainedTemplateSets.isEmpty)

            if !trainingManager.trainedTemplateSets.isEmpty {
                Text("\(trainingManager.trainedTemplateSets.count) template set(s) saved")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func extractTemplates() {
        if let templateSet = trainingManager.extractTemplates(
            from: sensorData,
            sessionId: session.id.uuidString,
            userMarks: userMarkedPeaks
        ) {
            exportMessage = "Extracted \(templateSet.templateCount) templates!"
            showingExportAlert = true
        } else {
            exportMessage = "Failed to extract templates. Need at least 3 marks with valid signal windows."
            showingExportAlert = true
        }
    }
}

// MARK: - Full Screen Peak Labeler

struct FullScreenPeakLabeler: View {
    let sensorData: [SensorReading]
    @Binding var userMarkedPeaks: [LabeledPeak]
    let positionContext: String

    @Environment(\.dismiss) private var dismiss

    @State private var fusedSignal: [Float] = []
    @State private var isProcessing = true

    // Zoom and pan state
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGFloat = 0
    @State private var lastOffset: CGFloat = 0

    // Visible range
    @State private var visibleStartIndex: Int = 0
    @State private var visibleEndIndex: Int = 0

    // Threshold for filtering noise
    @State private var thresholdPercentile: Double = 50.0  // Show only top 50% of signal by default
    @State private var computedThreshold: Float = 0.0

    // Auto-detected peaks (shown as reference)
    @State private var autoDetectedPeaks: [Int] = []

    // Signal statistics
    @State private var signalMax: Float = 1.0
    @State private var signalMean: Float = 0.0

    private let fs: Float = 50.0

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Minimal top bar
                minimalTopBar

                // Zoomable chart
                if isProcessing {
                    ProgressView("Processing signal...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    zoomableChart(in: geometry)
                }

                // Compact bottom controls
                compactBottomControls
            }
            .background(Color.black)
        }
        .statusBarHidden(true)
        .onAppear {
            processSignal()
        }
    }

    private var minimalTopBar: some View {
        HStack {
            Button("Done") {
                dismiss()
            }
            .foregroundColor(.white)

            Spacer()

            // Show counts
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                    Text("\(autoDetectedPeaks.count)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    Text("\(userMarkedPeaks.count)")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Spacer()

            Button("Undo") {
                if !userMarkedPeaks.isEmpty {
                    userMarkedPeaks.removeLast()
                }
            }
            .foregroundColor(userMarkedPeaks.isEmpty ? .gray : .white)
            .disabled(userMarkedPeaks.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black)
    }


    private func zoomableChart(in geometry: GeometryProxy) -> some View {
        let chartWidth = geometry.size.width
        let chartHeight = geometry.size.height - 100 // Minimal chrome

        return ZStack {
            // Chart with tap overlay (tap handling is in chartOverlay)
            chartContent(width: chartWidth, height: chartHeight)
                .gesture(
                    // Pinch to zoom
                    MagnificationGesture()
                        .onChanged { value in
                            let newScale = lastScale * value
                            scale = min(max(newScale, 1.0), 30.0)
                            updateVisibleRange(width: chartWidth)
                        }
                        .onEnded { _ in
                            lastScale = scale
                        }
                )
                .gesture(
                    // Two-finger drag to pan (when zoomed)
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            if scale > 1.0 {
                                let newOffset = lastOffset + value.translation.width
                                let maxOffset = chartWidth * (scale - 1) / 2
                                offset = min(max(newOffset, -maxOffset), maxOffset)
                                updateVisibleRange(width: chartWidth)
                            }
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )

            // Minimal instruction
            if scale < 3.0 && userMarkedPeaks.isEmpty {
                VStack {
                    Spacer()
                    Text("Pinch to zoom \u{2022} Tap peaks to mark")
                        .font(.caption2)
                        .padding(6)
                        .background(Color.black.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        .padding(.bottom, 4)
                }
            }
        }
        .frame(height: chartHeight)
        .clipped()
    }

    private func chartContent(width: CGFloat, height: CGFloat) -> some View {
        Chart {
            // Threshold line (horizontal)
            RuleMark(y: .value("Threshold", computedThreshold))
                .foregroundStyle(.orange.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [8, 4]))
                .annotation(position: .leading, alignment: .leading) {
                    Text("threshold")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                }

            // Signal line - only draw visible portion for performance
            let step = max(1, (visibleEndIndex - visibleStartIndex) / 500)
            let indices = stride(from: visibleStartIndex, to: min(visibleEndIndex, fusedSignal.count), by: step)

            ForEach(Array(indices), id: \.self) { index in
                if index < fusedSignal.count {
                    let value = fusedSignal[index]
                    LineMark(
                        x: .value("Sample", index),
                        y: .value("Signal", value)
                    )
                    // Color above threshold differently
                    .foregroundStyle(value >= computedThreshold ? .blue : .blue.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }

            // Auto-detected peaks (gray diamonds - tap to confirm)
            ForEach(autoDetectedPeaks.filter { idx in
                idx >= visibleStartIndex && idx <= visibleEndIndex &&
                !userMarkedPeaks.contains(where: { abs($0.peakIndex - idx) < 5 })
            }, id: \.self) { peakIdx in
                if peakIdx < fusedSignal.count {
                    PointMark(
                        x: .value("Sample", peakIdx),
                        y: .value("Signal", fusedSignal[peakIdx])
                    )
                    .foregroundStyle(.gray.opacity(0.6))
                    .symbolSize(120)
                    .symbol(.diamond)
                }
            }

            // User confirmed peaks (green circles)
            ForEach(userMarkedPeaks) { peak in
                if peak.peakIndex >= visibleStartIndex && peak.peakIndex <= visibleEndIndex {
                    let peakValue = peak.peakIndex < fusedSignal.count ? fusedSignal[peak.peakIndex] : 0

                    // Vertical line at mark
                    RuleMark(x: .value("Sample", peak.peakIndex))
                        .foregroundStyle(.green.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))

                    // Peak marker
                    PointMark(
                        x: .value("Sample", peak.peakIndex),
                        y: .value("Signal", peakValue)
                    )
                    .foregroundStyle(.green)
                    .symbolSize(250)

                    // Time label above peak
                    PointMark(
                        x: .value("Sample", peak.peakIndex),
                        y: .value("Signal", peakValue)
                    )
                    .annotation(position: .top) {
                        Text(String(format: "%.2fs", peak.timestamp))
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                            .padding(2)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(3)
                    }
                    .foregroundStyle(.clear)
                }
            }
        }
        .chartXScale(domain: visibleStartIndex...max(visibleStartIndex + 1, visibleEndIndex))
        .chartYScale(domain: 0...signalMax * 1.1)  // Fixed Y scale
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                if let intValue = value.as(Int.self) {
                    AxisValueLabel {
                        Text(String(format: "%.1fs", Float(intValue) / fs))
                    }
                }
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3))
        }
        .frame(height: height)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        handleTapWithProxy(at: location, proxy: proxy, geometry: geometry)
                    }
            }
        }
    }

    private var compactBottomControls: some View {
        VStack(spacing: 4) {
            // Single row: Threshold + Zoom
            HStack(spacing: 12) {
                // Threshold
                HStack(spacing: 4) {
                    Text("Thr")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Slider(value: $thresholdPercentile, in: 0...95, step: 5) { _ in
                        updateThreshold()
                    }
                    .frame(width: 80)
                    Text("\(Int(thresholdPercentile))%")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .frame(width: 30)
                }

                Divider().frame(height: 20)

                // Zoom
                HStack(spacing: 4) {
                    Text("Zm")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Slider(value: $scale, in: 1...30) { _ in
                        updateVisibleRange(width: UIScreen.main.bounds.width)
                    }
                    .frame(width: 80)
                    Text("\(Int(scale))x")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .frame(width: 30)
                }

                Divider().frame(height: 20)

                // Quick zoom
                HStack(spacing: 6) {
                    Button("5x") { setZoom(5.0) }
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(scale >= 4 && scale <= 6 ? Color.blue : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                    Button("15x") { setZoom(15.0) }
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(scale >= 13 && scale <= 17 ? Color.blue : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.black)
    }

    private var bottomControls: some View {
        VStack(spacing: 6) {
            // Threshold slider
            HStack {
                Image(systemName: "line.horizontal.3.decrease")
                    .foregroundColor(.orange)
                Text("Threshold")
                    .font(.caption2)
                    .foregroundColor(.orange)
                Slider(value: $thresholdPercentile, in: 0...95, step: 5) { _ in
                    updateThreshold()
                }
                Text("\(Int(thresholdPercentile))%")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .frame(width: 35)
            }
            .padding(.horizontal)

            // Zoom slider
            HStack {
                Image(systemName: "minus.magnifyingglass")
                Slider(value: $scale, in: 1...20) { _ in
                    updateVisibleRange(width: UIScreen.main.bounds.width)
                }
                Image(systemName: "plus.magnifyingglass")
            }
            .padding(.horizontal)

            // Quick zoom buttons
            HStack(spacing: 12) {
                Button("1x") { setZoom(1.0) }
                    .buttonStyle(.bordered)
                Button("5x") { setZoom(5.0) }
                    .buttonStyle(.bordered)
                Button("10x") { setZoom(10.0) }
                    .buttonStyle(.bordered)
                Button("20x") { setZoom(20.0) }
                    .buttonStyle(.bordered)
            }
            .font(.caption)
        }
        .padding()
        .background(Color(.systemGray6))
    }

    private func setZoom(_ newScale: CGFloat) {
        withAnimation(.easeInOut(duration: 0.3)) {
            scale = newScale
            lastScale = newScale
            updateVisibleRange(width: UIScreen.main.bounds.width)
        }
    }

    private func processSignal() {
        isProcessing = true

        DispatchQueue.global(qos: .userInitiated).async {
            let frames = PinchDetector.convertSensorReadings(sensorData)
            let signal = computeFusedSignal(frames: frames)

            // Compute statistics
            let sorted = signal.sorted()
            let maxVal = sorted.last ?? 1.0
            let meanVal = signal.reduce(0, +) / Float(max(signal.count, 1))

            // Auto-detect peaks above threshold
            let threshold = sorted[Int(Double(sorted.count) * 0.5)]  // 50th percentile
            let peaks = self.findAllPeaks(in: signal, minHeight: threshold, minDistance: 10)

            DispatchQueue.main.async {
                self.fusedSignal = signal
                self.visibleStartIndex = 0
                self.visibleEndIndex = signal.count
                self.signalMax = maxVal
                self.signalMean = meanVal
                self.autoDetectedPeaks = peaks
                self.updateThreshold()
                self.isProcessing = false
            }
        }
    }

    /// Find all local maxima above threshold
    private func findAllPeaks(in signal: [Float], minHeight: Float, minDistance: Int) -> [Int] {
        guard signal.count > 2 else { return [] }

        var peaks: [Int] = []
        var lastPeakIdx = -minDistance

        for i in 1..<(signal.count - 1) {
            // Local maximum check
            if signal[i] > signal[i-1] && signal[i] > signal[i+1] && signal[i] >= minHeight {
                if i - lastPeakIdx >= minDistance {
                    peaks.append(i)
                    lastPeakIdx = i
                }
            }
        }

        return peaks
    }

    private func updateThreshold() {
        guard !fusedSignal.isEmpty else { return }

        // Compute percentile threshold
        let sorted = fusedSignal.sorted()
        let percentileIndex = Int(Double(sorted.count) * thresholdPercentile / 100.0)
        let clampedIndex = min(max(percentileIndex, 0), sorted.count - 1)
        computedThreshold = sorted[clampedIndex]
    }

    private func computeFusedSignal(frames: [SensorFrame]) -> [Float] {
        guard frames.count > 2 else { return [] }

        var ax = [Float](), ay = [Float](), az = [Float]()
        var gx = [Float](), gy = [Float](), gz = [Float]()

        for frame in frames {
            ax.append(frame.ax); ay.append(frame.ay); az.append(frame.az)
            gx.append(frame.gx); gy.append(frame.gy); gz.append(frame.gz)
        }

        func tkeo(_ x: [Float]) -> [Float] {
            guard x.count >= 3 else { return Array(repeating: 0, count: x.count) }
            var y = [Float](repeating: 0, count: x.count)
            y[0] = x[0] * x[0]
            y[y.count - 1] = x[y.count - 1] * x[y.count - 1]
            for i in 1..<(x.count - 1) {
                let v = x[i] * x[i] - x[i - 1] * x[i + 1]
                y[i] = v > 0 ? v : 0
            }
            return y
        }

        let axT = tkeo(ax), ayT = tkeo(ay), azT = tkeo(az)
        let gxT = tkeo(gx), gyT = tkeo(gy), gzT = tkeo(gz)

        var aT = [Float](repeating: 0, count: axT.count)
        var gT = [Float](repeating: 0, count: gxT.count)
        for i in 0..<axT.count {
            aT[i] = sqrt(axT[i] * axT[i] + ayT[i] * ayT[i] + azT[i] * azT[i])
            gT[i] = sqrt(gxT[i] * gxT[i] + gyT[i] * gyT[i] + gzT[i] * gzT[i])
        }

        var result = [Float](repeating: 0, count: aT.count)
        for i in 0..<aT.count {
            result[i] = 1.0 * aT[i] + 1.5 * gT[i]
        }
        return result
    }

    private func updateVisibleRange(width: CGFloat) {
        guard !fusedSignal.isEmpty else { return }

        let totalSamples = fusedSignal.count
        let visibleSamples = Int(CGFloat(totalSamples) / scale)

        // Calculate center based on offset
        let centerRatio = 0.5 - (offset / (width * scale))
        let centerIndex = Int(CGFloat(totalSamples) * centerRatio)

        visibleStartIndex = max(0, centerIndex - visibleSamples / 2)
        visibleEndIndex = min(totalSamples, visibleStartIndex + visibleSamples)

        // Clamp
        if visibleEndIndex >= totalSamples {
            visibleEndIndex = totalSamples
            visibleStartIndex = max(0, visibleEndIndex - visibleSamples)
        }
    }

    private func handleTapWithProxy(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard !fusedSignal.isEmpty else { return }

        // Use ChartProxy to convert tap location to data value
        // This properly accounts for axis labels and padding
        guard let tappedXValue: Int = proxy.value(atX: location.x) else { return }

        // Clamp to valid range
        let clampedIndex = max(0, min(tappedXValue, fusedSignal.count - 1))

        // 1. Check if tapping on an existing confirmed mark -> REMOVE it
        if let existingIndex = userMarkedPeaks.firstIndex(where: { abs($0.peakIndex - clampedIndex) < 15 }) {
            userMarkedPeaks.remove(at: existingIndex)
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            return
        }

        // 2. Check if tapping near an auto-detected peak -> CONFIRM it
        if let nearbyAutoPeak = autoDetectedPeaks.first(where: { abs($0 - clampedIndex) < 15 }) {
            let timestamp = TimeInterval(nearbyAutoPeak) / TimeInterval(fs)
            let newPeak = LabeledPeak(
                timestamp: timestamp,
                peakIndex: nearbyAutoPeak,
                isConfirmed: true,
                positionContext: positionContext
            )
            userMarkedPeaks.append(newPeak)
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            return
        }

        // 3. Tapping elsewhere above threshold -> ADD new mark (snap to local max)
        let tappedValue = fusedSignal[clampedIndex]
        if tappedValue >= computedThreshold {
            let snappedIndex = findLocalPeak(near: clampedIndex, searchRadius: 10)
            let timestamp = TimeInterval(snappedIndex) / TimeInterval(fs)
            let newPeak = LabeledPeak(
                timestamp: timestamp,
                peakIndex: snappedIndex,
                isConfirmed: true,
                positionContext: positionContext
            )
            userMarkedPeaks.append(newPeak)
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
    }

    /// Find local maximum near given index
    private func findLocalPeak(near index: Int, searchRadius: Int) -> Int {
        guard !fusedSignal.isEmpty else { return index }

        let startIdx = max(0, index - searchRadius)
        let endIdx = min(fusedSignal.count - 1, index + searchRadius)

        var maxIdx = index
        var maxVal = fusedSignal[index]

        for i in startIdx...endIdx {
            if fusedSignal[i] > maxVal {
                maxVal = fusedSignal[i]
                maxIdx = i
            }
        }

        return maxIdx
    }
}

// MARK: - Saved Templates View

struct SavedTemplatesView: View {
    @ObservedObject private var trainingManager = TemplateTrainingManager.shared
    @State private var showingDeleteAlert = false
    @State private var deleteIndex: Int?

    var body: some View {
        List {
            if trainingManager.trainedTemplateSets.isEmpty {
                Section {
                    Text("No trained templates yet")
                        .foregroundColor(.secondary)
                    Text("Use Template Training on a session to create personalized templates.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(Array(trainingManager.trainedTemplateSets.enumerated()), id: \.offset) { index, set in
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(set.templateCount) templates")
                                    .font(.headline)
                                Spacer()
                                if let context = set.positionContext {
                                    Text(context.capitalized)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.2))
                                        .cornerRadius(6)
                                }
                            }

                            HStack {
                                Label("Session: \(set.sourceSessionId.prefix(8))...", systemImage: "doc")
                                Spacer()
                                Label(set.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteIndex = index
                            showingDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                Section {
                    Button {
                        trainingManager.syncToWatch()
                    } label: {
                        HStack {
                            Image(systemName: "applewatch")
                            Text("Sync All to Watch")
                        }
                    }
                }
            }
        }
        .navigationTitle("Saved Templates")
        .alert("Delete Template Set?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let index = deleteIndex {
                    trainingManager.deleteTemplateSet(at: index)
                }
            }
        } message: {
            Text("This will remove these templates.")
        }
    }
}

#Preview {
    NavigationStack {
        SavedTemplatesView()
    }
}
