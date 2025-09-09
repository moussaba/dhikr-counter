import SwiftUI
import Charts

// MARK: - Chart Image Exporter

@MainActor
class TKEOChartImageExporter {
    
    /// Export multiple chart types for TKEO analysis
    static func exportAllChartImages(
        sensorData: [SensorReading],
        session: DhikrSession,
        detectedEvents: [PinchEvent],
        format: ChartImageFormat = .png
    ) async throws -> [String: Data] {
        
        var chartImages: [String: Data] = [:]
        
        // Define the 5 chart types matching the analysis plots
        let chartTypes: [TKEOChartType] = [
            .combinedOverview,
            .bandpassFiltered,
            .jerkSignals,
            .tkeoSignals,
            .fusionScore
        ]
        
        // Export each chart type
        for chartType in chartTypes {
            do {
                let imageData = try await exportChartImage(
                    chartType: chartType,
                    sensorData: sensorData,
                    session: session,
                    detectedEvents: detectedEvents,
                    format: format
                )
                chartImages[chartType.displayName] = imageData
            } catch {
                print("⚠️ Failed to export \(chartType.displayName): \(error)")
                // Continue with other charts even if one fails
            }
        }
        
        return chartImages
    }
    
    /// Export a single chart as image data
    static func exportChartImage(
        chartType: TKEOChartType,
        sensorData: [SensorReading],
        session: DhikrSession,
        detectedEvents: [PinchEvent],
        format: ChartImageFormat = .png,
        size: CGSize = CGSize(width: 800, height: 600)
    ) async throws -> Data {
        
        // Create the chart view based on type
        let chartView = createChartView(
            chartType: chartType,
            sensorData: sensorData,
            session: session,
            detectedEvents: detectedEvents
        )
        
        // Render the chart to image
        let renderer = ImageRenderer(content: chartView)
        renderer.proposedSize = .init(size)
        
        // Configure for high quality export
        renderer.scale = 2.0 // Retina quality
        
        guard let image = renderer.uiImage else {
            throw TKEOExportError.chartRenderingFailed(chartType.displayName)
        }
        
        // Convert to requested format
        switch format {
        case .png:
            guard let data = image.pngData() else {
                throw TKEOExportError.imageCompressionFailed(format.rawValue)
            }
            return data
        case .jpeg:
            guard let data = image.jpegData(compressionQuality: 0.9) else {
                throw TKEOExportError.imageCompressionFailed(format.rawValue)
            }
            return data
        }
    }
    
    /// Create chart view for the specified type
    private static func createChartView(
        chartType: TKEOChartType,
        sensorData: [SensorReading],
        session: DhikrSession,
        detectedEvents: [PinchEvent]
    ) -> some View {
        
        // Use the same working chart view from session details with specific plot type
        // Use fullScreen = true to exclude UI elements (export button, picker, etc.)
        return TKEOAnalysisPlotView(
            sensorData: sensorData,
            session: session,
            detectedEvents: detectedEvents,
            isFullScreen: true,
            plotType: convertToTKEOPlotType(chartType)
        )
    }
    
    /// Convert TKEOChartType to TKEOPlotType for the working session chart
    private static func convertToTKEOPlotType(_ chartType: TKEOChartType) -> TKEOAnalysisPlotView.TKEOPlotType {
        switch chartType {
        case .combinedOverview:
            return .combinedOverview
        case .bandpassFiltered:
            return .bandpassFiltered
        case .jerkSignals:
            return .jerkSignals
        case .tkeoSignals:
            return .tkeoSignals
        case .fusionScore:
            return .fusionScore
        }
    }
}

// MARK: - Chart Types for Export

enum TKEOChartType: String, CaseIterable {
    case combinedOverview = "combined_overview"
    case bandpassFiltered = "bandpass_filtered"
    case jerkSignals = "jerk_signals"
    case tkeoSignals = "tkeo_signals"
    case fusionScore = "fusion_score"
    
    var displayName: String {
        switch self {
        case .combinedOverview:
            return "Combined Overview"
        case .bandpassFiltered:
            return "Bandpass Filtered"
        case .jerkSignals:
            return "Jerk Signals"
        case .tkeoSignals:
            return "TKEO Signals"
        case .fusionScore:
            return "Fusion Score"
        }
    }
    
    var description: String {
        switch self {
        case .combinedOverview:
            return "Acceleration + Gyroscope magnitude with detected events"
        case .bandpassFiltered:
            return "Bandpass filtered signals (3-20Hz)"
        case .jerkSignals:
            return "Jerk (derivative of acceleration)"
        case .tkeoSignals:
            return "TKEO energy operator output"
        case .fusionScore:
            return "Fused detection score"
        }
    }
}

// MARK: - Export Chart View

struct TKEOExportChartView: View {
    let chartType: TKEOChartType
    let sensorData: [SensorReading]
    let session: DhikrSession
    let detectedEvents: [PinchEvent]
    
    // Processed data for charts - computed from input data directly
    private var processedData: ProcessedSignalData? {
        // Use pre-computed data instead of async processing
        return createProcessedDataFromInputs()
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Chart title and metadata
            VStack(spacing: 8) {
                Text(chartType.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(chartType.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("Session: \(session.id.uuidString.prefix(8))")
                    Spacer()
                    Text("Duration: \(String(format: "%.1f", session.sessionDuration))s")
                    Spacer()
                    Text("Events: \(detectedEvents.count)")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            // The actual chart
            chartContent
                .frame(height: 400)
                .padding(.horizontal)
            
            // Legend
            chartLegend
                .padding(.horizontal)
        }
        .padding()
        .background(Color(.systemBackground))
        // No async processing needed - data computed directly from inputs
    }
    
    @ViewBuilder
    private var chartContent: some View {
        if let data = processedData {
            switch chartType {
            case .combinedOverview:
                Chart {
                    combinedOverviewChart(data: data)
                }
            case .bandpassFiltered:
                Chart {
                    bandpassFilteredChart(data: data)
                }
            case .jerkSignals:
                Chart {
                    jerkSignalsChart(data: data)
                }
            case .tkeoSignals:
                Chart {
                    tkeoSignalsChart(data: data)
                }
            case .fusionScore:
                Chart {
                    fusionScoreChart(data: data)
                }
            }
        } else {
            ProgressView("Processing signal data...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    @ViewBuilder
    private var chartLegend: some View {
        switch chartType {
        case .combinedOverview:
            HStack(spacing: 20) {
                ExportLegendItem(color: .blue, label: "Accel Magnitude")
                ExportLegendItem(color: .red, label: "Gyro Magnitude")
                ExportLegendItem(color: .green, label: "Gate Events")
                ExportLegendItem(color: .purple, label: "Verified Events")
            }
        case .bandpassFiltered:
            HStack(spacing: 20) {
                ExportLegendItem(color: .blue, label: "Filtered Accel X")
                ExportLegendItem(color: .red, label: "Filtered Accel Y")
                ExportLegendItem(color: .green, label: "Filtered Accel Z")
            }
        case .jerkSignals:
            HStack(spacing: 20) {
                ExportLegendItem(color: .blue, label: "Jerk X")
                ExportLegendItem(color: .red, label: "Jerk Y")
                ExportLegendItem(color: .green, label: "Jerk Z")
                ExportLegendItem(color: .purple, label: "Jerk Magnitude")
            }
        case .tkeoSignals:
            HStack(spacing: 20) {
                ExportLegendItem(color: .blue, label: "TKEO Accel")
                ExportLegendItem(color: .red, label: "TKEO Gyro")
                ExportLegendItem(color: .orange, label: "Gate Threshold")
            }
        case .fusionScore:
            HStack(spacing: 20) {
                ExportLegendItem(color: .purple, label: "Fusion Score")
                ExportLegendItem(color: .green, label: "Detection Events")
            }
        }
    }
    
    // MARK: - Chart Implementations
    
    @ChartContentBuilder
    private func combinedOverviewChart(data: ProcessedSignalData) -> some ChartContent {
        // Acceleration magnitude
        ForEach(Array(zip(data.timestamps, data.accelMagnitude).enumerated()), id: \.offset) { index, point in
            LineMark(
                x: .value("Time", point.0),
                y: .value("Acceleration", point.1)
            )
            .foregroundStyle(.blue)
            .interpolationMethod(.catmullRom)
        }
        
        // Gyroscope magnitude
        ForEach(Array(zip(data.timestamps, data.gyroMagnitude).enumerated()), id: \.offset) { index, point in
            LineMark(
                x: .value("Time", point.0),
                y: .value("Gyroscope", point.1)
            )
            .foregroundStyle(.red)
            .interpolationMethod(.catmullRom)
        }
        
        // Detected events
        ForEach(detectedEvents, id: \.tPeak) { event in
            RuleMark(x: .value("Event", event.tPeak))
                .foregroundStyle(event.confidence > 0.8 ? .purple : .green)
                .lineStyle(StrokeStyle(lineWidth: 2))
        }
    }
    
    @ChartContentBuilder
    private func bandpassFilteredChart(data: ProcessedSignalData) -> some ChartContent {
        ForEach(Array(zip(data.timestamps, data.filteredAccelX).enumerated()), id: \.offset) { index, point in
            LineMark(
                x: .value("Time", point.0),
                y: .value("Filtered X", point.1)
            )
            .foregroundStyle(.blue)
            .interpolationMethod(.catmullRom)
        }
        
        ForEach(Array(zip(data.timestamps, data.filteredAccelY).enumerated()), id: \.offset) { index, point in
            LineMark(
                x: .value("Time", point.0),
                y: .value("Filtered Y", point.1)
            )
            .foregroundStyle(.red)
            .interpolationMethod(.catmullRom)
        }
        
        ForEach(Array(zip(data.timestamps, data.filteredAccelZ).enumerated()), id: \.offset) { index, point in
            LineMark(
                x: .value("Time", point.0),
                y: .value("Filtered Z", point.1)
            )
            .foregroundStyle(.green)
            .interpolationMethod(.catmullRom)
        }
    }
    
    @ChartContentBuilder
    private func jerkSignalsChart(data: ProcessedSignalData) -> some ChartContent {
        ForEach(Array(zip(data.timestamps, data.jerkX).enumerated()), id: \.offset) { index, point in
            LineMark(
                x: .value("Time", point.0),
                y: .value("Jerk X", point.1)
            )
            .foregroundStyle(.blue)
            .interpolationMethod(.catmullRom)
        }
        
        ForEach(Array(zip(data.timestamps, data.jerkY).enumerated()), id: \.offset) { index, point in
            LineMark(
                x: .value("Time", point.0),
                y: .value("Jerk Y", point.1)
            )
            .foregroundStyle(.red)
            .interpolationMethod(.catmullRom)
        }
        
        ForEach(Array(zip(data.timestamps, data.jerkZ).enumerated()), id: \.offset) { index, point in
            LineMark(
                x: .value("Time", point.0),
                y: .value("Jerk Z", point.1)
            )
            .foregroundStyle(.green)
            .interpolationMethod(.catmullRom)
        }
        
        ForEach(Array(zip(data.timestamps, data.jerkMagnitude).enumerated()), id: \.offset) { index, point in
            LineMark(
                x: .value("Time", point.0),
                y: .value("Jerk Mag", point.1)
            )
            .foregroundStyle(.purple)
            .interpolationMethod(.catmullRom)
        }
    }
    
    @ChartContentBuilder
    private func tkeoSignalsChart(data: ProcessedSignalData) -> some ChartContent {
        ForEach(Array(zip(data.timestamps, data.tkeoAccel).enumerated()), id: \.offset) { index, point in
            LineMark(
                x: .value("Time", point.0),
                y: .value("TKEO Accel", point.1)
            )
            .foregroundStyle(.blue)
            .interpolationMethod(.catmullRom)
        }
        
        ForEach(Array(zip(data.timestamps, data.tkeoGyro).enumerated()), id: \.offset) { index, point in
            LineMark(
                x: .value("Time", point.0),
                y: .value("TKEO Gyro", point.1)
            )
            .foregroundStyle(.red)
            .interpolationMethod(.catmullRom)
        }
        
        // Gate threshold line
        RuleMark(y: .value("Threshold", data.gateThreshold))
            .foregroundStyle(.orange)
            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
    }
    
    @ChartContentBuilder
    private func fusionScoreChart(data: ProcessedSignalData) -> some ChartContent {
        ForEach(Array(zip(data.timestamps, data.fusionScore).enumerated()), id: \.offset) { index, point in
            LineMark(
                x: .value("Time", point.0),
                y: .value("Fusion Score", point.1)
            )
            .foregroundStyle(.purple)
            .interpolationMethod(.catmullRom)
        }
        
        // Detection events
        ForEach(detectedEvents, id: \.tPeak) { event in
            PointMark(
                x: .value("Event", event.tPeak),
                y: .value("Score", event.confidence)
            )
            .foregroundStyle(.green)
            .symbol(.circle)
            .symbolSize(50)
        }
    }
    
    // MARK: - Signal Processing
    
    private func createProcessedDataFromInputs() -> ProcessedSignalData? {
        // Convert sensor readings to timestamped arrays
        guard !sensorData.isEmpty else {
            return ProcessedSignalData.empty()
        }
        
        let startTime = sensorData.first!.motionTimestamp
        let timestamps = sensorData.map { $0.motionTimestamp - startTime }
        
        // Extract raw signals
        let accelX = sensorData.map { Float($0.userAcceleration.x) }
        let accelY = sensorData.map { Float($0.userAcceleration.y) }
        let accelZ = sensorData.map { Float($0.userAcceleration.z) }
        let gyroX = sensorData.map { Float($0.rotationRate.x) }
        let gyroY = sensorData.map { Float($0.rotationRate.y) }
        let gyroZ = sensorData.map { Float($0.rotationRate.z) }
        
        // Calculate magnitudes
        let accelMagnitude = zip3(accelX, accelY, accelZ).map { x, y, z in
            sqrt(x*x + y*y + z*z)
        }
        let gyroMagnitude = zip3(gyroX, gyroY, gyroZ).map { x, y, z in
            sqrt(x*x + y*y + z*z)
        }
        
        // Simplified signal processing (placeholder for real TKEO processing)
        let filteredAccelX = applyBandpassFilter(accelX)
        let filteredAccelY = applyBandpassFilter(accelY)
        let filteredAccelZ = applyBandpassFilter(accelZ)
        
        let jerkX = calculateDerivative(accelX)
        let jerkY = calculateDerivative(accelY)
        let jerkZ = calculateDerivative(accelZ)
        let jerkMagnitude = zip3(jerkX, jerkY, jerkZ).map { x, y, z in
            sqrt(x*x + y*y + z*z)
        }
        
        let tkeoAccel = calculateTKEO(accelMagnitude)
        let tkeoGyro = calculateTKEO(gyroMagnitude)
        let fusionScore = zip(tkeoAccel, tkeoGyro).map { a, g in
            1.0 * a + 1.5 * g  // Simple fusion
        }
        
        return ProcessedSignalData(
            timestamps: timestamps,
            accelMagnitude: accelMagnitude,
            gyroMagnitude: gyroMagnitude,
            filteredAccelX: filteredAccelX,
            filteredAccelY: filteredAccelY,
            filteredAccelZ: filteredAccelZ,
            jerkX: jerkX,
            jerkY: jerkY,
            jerkZ: jerkZ,
            jerkMagnitude: jerkMagnitude,
            tkeoAccel: tkeoAccel,
            tkeoGyro: tkeoGyro,
            fusionScore: fusionScore,
            gateThreshold: 3.5  // Default threshold
        )
    }
    
    // MARK: - Signal Processing Helpers
    
    private func applyBandpassFilter(_ signal: [Float]) -> [Float] {
        // Simplified bandpass filter (placeholder)
        return signal.map { $0 * 0.8 } // Just attenuate for now
    }
    
    private func calculateDerivative(_ signal: [Float]) -> [Float] {
        guard signal.count > 1 else { return [] }
        var derivative: [Float] = []
        for i in 1..<signal.count {
            derivative.append(signal[i] - signal[i-1])
        }
        return derivative
    }
    
    private func calculateTKEO(_ signal: [Float]) -> [Float] {
        guard signal.count >= 3 else { return [] }
        var tkeo: [Float] = [0.0] // First sample
        
        for i in 1..<(signal.count-1) {
            let energy = signal[i] * signal[i] - signal[i-1] * signal[i+1]
            tkeo.append(max(0, energy))
        }
        tkeo.append(0.0) // Last sample
        return tkeo
    }
}

// MARK: - Supporting Data Structures

struct ProcessedSignalData {
    let timestamps: [TimeInterval]
    let accelMagnitude: [Float]
    let gyroMagnitude: [Float]
    let filteredAccelX: [Float]
    let filteredAccelY: [Float]
    let filteredAccelZ: [Float]
    let jerkX: [Float]
    let jerkY: [Float]
    let jerkZ: [Float]
    let jerkMagnitude: [Float]
    let tkeoAccel: [Float]
    let tkeoGyro: [Float]
    let fusionScore: [Float]
    let gateThreshold: Float
    
    static func empty() -> ProcessedSignalData {
        return ProcessedSignalData(
            timestamps: [],
            accelMagnitude: [],
            gyroMagnitude: [],
            filteredAccelX: [],
            filteredAccelY: [],
            filteredAccelZ: [],
            jerkX: [],
            jerkY: [],
            jerkZ: [],
            jerkMagnitude: [],
            tkeoAccel: [],
            tkeoGyro: [],
            fusionScore: [],
            gateThreshold: 0.0
        )
    }
}

struct ExportLegendItem: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Error Types

enum TKEOExportError: LocalizedError {
    case chartRenderingFailed(String)
    case imageCompressionFailed(String)
    case noDataAvailable
    
    var errorDescription: String? {
        switch self {
        case .chartRenderingFailed(let chartName):
            return "Failed to render \(chartName) chart"
        case .imageCompressionFailed(let format):
            return "Failed to compress image as \(format)"
        case .noDataAvailable:
            return "No sensor data available for chart generation"
        }
    }
}

// MARK: - Helper Functions

func zip3<A, B, C>(_ a: [A], _ b: [B], _ c: [C]) -> [(A, B, C)] {
    return zip(zip(a, b), c).map { (($0.0, $0.1), $1) }.map { ($0.0, $0.1, $1) }
}