import SwiftUI

// MARK: - Main Export Sheet

struct TKEOAnalysisExportSheet: View {
    let session: DhikrSession
    let sensorData: [SensorReading]
    let detectedEvents: [PinchEvent]
    
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dataManager = PhoneSessionManager.shared
    
    @State private var exportOptions = TKEOExportOptions.default
    @State private var isExporting = false
    @State private var exportProgress: Double = 0.0
    @State private var exportStatus: String = ""
    @State private var showingShareSheet = false
    @State private var exportURLs: [URL] = []
    @State private var exportError: TKEOExportError?
    @State private var showingPreview = false
    @State private var previewData: TKEOAnalysisExport?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Export format selection
                    formatSelectionSection
                    
                    // Export options
                    optionsSection
                    
                    // Preview section
                    previewSection
                    
                    // Export button
                    exportButtonSection
                    
                    // Progress section (shown during export)
                    if isExporting {
                        progressSection
                    }
                    
                    // Error display
                    if let error = exportError {
                        errorSection(error)
                    }
                }
                .padding()
            }
            .navigationTitle("Export TKEO Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isExporting)
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if !exportURLs.isEmpty {
                ShareSheet(activityItems: exportURLs)
            }
        }
        .sheet(isPresented: $showingPreview) {
            if let previewData = previewData {
                TKEOExportPreviewSheet(exportData: previewData)
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.title)
                    .foregroundColor(.purple)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session \(session.id.uuidString.prefix(8))")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("\(String(format: "%.1f", session.sessionDuration))s • \(detectedEvents.count) events detected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Divider()
                .padding(.horizontal, -16)
        }
    }
    
    // MARK: - Format Selection
    
    private var formatSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundColor(.blue)
                Text("Export Formats")
                    .font(.headline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ForEach(TKEOExportFormat.allCases, id: \.self) { format in
                    FormatSelectionCard(
                        format: format,
                        isSelected: exportOptions.formats.contains(format),
                        onToggle: {
                            toggleFormat(format)
                        }
                    )
                }
            }
            
            Text("Select one or more formats to export. HTML includes embedded visualizations.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Options Section
    
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "gear")
                    .foregroundColor(.orange)
                Text("Export Options")
                    .font(.headline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            VStack(spacing: 12) {
                OptionToggleRow(
                    title: "Include Raw Data",
                    description: "Complete sensor readings and timestamps",
                    isOn: $exportOptions.includeRawData
                )
                
                OptionToggleRow(
                    title: "Include Debug Logs",
                    description: "Processing logs and diagnostic information",
                    isOn: $exportOptions.includeDebugLogs
                )
                
                OptionToggleRow(
                    title: "Include Chart Images",
                    description: "High-resolution plots embedded in reports",
                    isOn: $exportOptions.includeChartImages
                )
                
                if exportOptions.includeChartImages {
                    HStack {
                        Text("Image Format:")
                            .font(.subheadline)
                        Spacer()
                        Picker("Image Format", selection: $exportOptions.chartImageFormat) {
                            ForEach(ChartImageFormat.allCases, id: \.self) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 120)
                    }
                    
                    HStack {
                        Text("Compression:")
                            .font(.subheadline)
                        Spacer()
                        Picker("Compression", selection: $exportOptions.compressionLevel) {
                            ForEach(CompressionLevel.allCases, id: \.self) { level in
                                Text(level.rawValue).tag(level)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 120)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Preview Section
    
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "eye")
                    .foregroundColor(.green)
                Text("Preview")
                    .font(.headline)
                    .fontWeight(.medium)
                Spacer()
                
                Button("Generate Preview") {
                    generatePreview()
                }
                .buttonStyle(.bordered)
                .disabled(isExporting || exportOptions.formats.isEmpty)
            }
            
            Text("Preview the export data structure before generating files")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Export Button
    
    private var exportButtonSection: some View {
        VStack(spacing: 16) {
            Button(action: startExport) {
                HStack {
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.9)
                            .padding(.trailing, 4)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    
                    Text(isExporting ? "Exporting..." : "Export Analysis")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isExporting || exportOptions.formats.isEmpty)
            
            if exportOptions.formats.isEmpty {
                Text("Select at least one export format")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "hourglass")
                    .foregroundColor(.blue)
                Text("Export Progress")
                    .font(.headline)
                Spacer()
                Text("\(Int(exportProgress * 100))%")
                    .font(.headline)
                    .monospacedDigit()
            }
            
            ProgressView(value: exportProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
            
            if !exportStatus.isEmpty {
                Text(exportStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Error Section
    
    private func errorSection(_ error: TKEOExportError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("Export Error")
                    .font(.headline)
                    .foregroundColor(.red)
                Spacer()
                Button("Dismiss") {
                    exportError = nil
                }
                .buttonStyle(.bordered)
            }
            
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemRed).opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemRed), lineWidth: 1)
        )
    }
    
    // MARK: - Helper Methods
    
    private func toggleFormat(_ format: TKEOExportFormat) {
        if exportOptions.formats.contains(format) {
            exportOptions.formats.remove(format)
        } else {
            exportOptions.formats.insert(format)
        }
    }
    
    private func generatePreview() {
        Task { @MainActor in
            do {
                let exporter = TKEOAnalysisDataExporter()
                let exportData = try await exporter.prepareExportData(
                    session: session,
                    sensorData: sensorData,
                    detectedEvents: detectedEvents,
                    debugLogs: [], // Get from TKEO card if needed
                    options: exportOptions
                )
                
                await MainActor.run {
                    self.previewData = exportData
                    self.showingPreview = true
                }
            } catch {
                await MainActor.run {
                    self.exportError = error as? TKEOExportError ?? .noDataAvailable
                }
            }
        }
    }
    
    private func startExport() {
        Task { @MainActor in
            await performExport()
        }
    }
    
    @MainActor
    private func performExport() async {
        isExporting = true
        exportProgress = 0.0
        exportError = nil
        exportURLs = []
        exportStatus = "Preparing export data..."
        
        do {
            // Step 1: Prepare data (20%)
            let exporter = TKEOAnalysisDataExporter()
            let exportData = try await exporter.prepareExportData(
                session: session,
                sensorData: sensorData,
                detectedEvents: detectedEvents,
                debugLogs: [], // Get from detection card if needed
                options: exportOptions
            )
            
            exportProgress = 0.2
            exportStatus = "Generating chart images..."
            
            // Step 2: Generate charts if needed (40%)
            var chartImages: [String: Data] = [:]
            if exportOptions.includeChartImages {
                chartImages = try await TKEOChartImageExporter.exportAllChartImages(
                    sensorData: sensorData,
                    session: session,
                    detectedEvents: detectedEvents,
                    format: exportOptions.chartImageFormat
                )
            }
            
            exportProgress = 0.6
            exportStatus = "Creating export files..."
            
            // Step 3: Generate files (80%)
            let fileURLs = try await generateExportFiles(
                exportData: exportData,
                chartImages: chartImages
            )
            
            exportProgress = 1.0
            exportStatus = "Export complete!"
            
            exportURLs = fileURLs
            showingShareSheet = true
            
        } catch {
            exportError = error as? TKEOExportError ?? .noDataAvailable
        }
        
        isExporting = false
    }
    
    private func generateExportFiles(
        exportData: TKEOAnalysisExport,
        chartImages: [String: Data]
    ) async throws -> [URL] {
        
        var fileURLs: [URL] = []
        let sessionId = session.id.uuidString.prefix(8)
        let timestamp = DateFormatter.compactDateTime.string(from: Date())
        
        for format in exportOptions.formats {
            let fileName = "TKEO_Analysis_\(sessionId)_\(timestamp).\(format.fileExtension)"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            
            switch format {
            case .html:
                let htmlContent = TKEOHTMLReportGenerator.generateHTMLReport(
                    from: exportData,
                    chartImages: chartImages,
                    options: exportOptions
                )
                try htmlContent.write(to: tempURL, atomically: true, encoding: .utf8)
                
            case .json:
                let jsonData = try JSONEncoder().encode(exportData)
                try jsonData.write(to: tempURL)
                
            case .pdf:
                // Placeholder - would implement PDF generation
                let pdfContent = "PDF export not yet implemented"
                try pdfContent.write(to: tempURL, atomically: true, encoding: .utf8)
                
            case .csv:
                let csvContent = generateCSVContent(from: exportData)
                try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
            }
            
            fileURLs.append(tempURL)
        }
        
        return fileURLs
    }
    
    private func generateCSVContent(from exportData: TKEOAnalysisExport) -> String {
        var csv = "timestamp,accel_x,accel_y,accel_z,accel_magnitude,gyro_x,gyro_y,gyro_z,gyro_magnitude\n"
        
        for reading in exportData.rawData.sensorReadings {
            csv += "\(reading.timestamp),\(reading.accelerationX),\(reading.accelerationY),\(reading.accelerationZ),\(reading.accelerationMagnitude),\(reading.rotationX),\(reading.rotationY),\(reading.rotationZ),\(reading.rotationMagnitude)\n"
        }
        
        return csv
    }
}

// MARK: - Format Selection Card

struct FormatSelectionCard: View {
    let format: TKEOExportFormat
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 8) {
                Image(systemName: formatIcon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text(format.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text(".\(format.fileExtension)")
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(isSelected ? Color.accentColor : Color(.systemGray5))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var formatIcon: String {
        switch format {
        case .html: return "doc.richtext.fill"
        case .json: return "curlybraces"
        case .pdf: return "doc.fill"
        case .csv: return "tablecells.fill"
        }
    }
}

// MARK: - Option Toggle Row

struct OptionToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
            }
        }
    }
}

// MARK: - Export Preview Sheet

struct TKEOExportPreviewSheet: View {
    let exportData: TKEOAnalysisExport
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    previewCard("Session Metadata", value: formatSessionMetadata())
                    previewCard("Algorithm Config", value: formatAlgorithmConfig())
                    previewCard("Detection Results", value: formatResults())
                    previewCard("Data Quality", value: formatDataQuality())
                }
                .padding()
            }
            .navigationTitle("Export Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func previewCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            Text(value)
                .font(.caption)
                .font(.system(.caption, design: .monospaced))
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
        }
    }
    
    private func formatSessionMetadata() -> String {
        let metadata = exportData.sessionMetadata
        return """
        Session ID: \(metadata.sessionId)
        Duration: \(String(format: "%.1f", metadata.duration))s
        Total Pinches: \(metadata.totalPinches)
        Detected: \(metadata.detectedPinches)
        Device: \(metadata.deviceInfo.deviceModel)
        Sample Rate: \(metadata.deviceInfo.samplingRate)Hz
        """
    }
    
    private func formatAlgorithmConfig() -> String {
        let config = exportData.algorithmConfiguration
        return """
        Sample Rate: \(config.tkeoParams.sampleRate)Hz
        Bandpass: \(config.filterSettings.bandpassLow)-\(config.filterSettings.bandpassHigh)Hz
        Gate Threshold: \(config.tkeoParams.gateThreshold)
        NCC Threshold: \(config.templateParams.nccThreshold)
        Templates: \(config.templateParams.templateCount)
        """
    }
    
    private func formatResults() -> String {
        let results = exportData.analysisResults
        return """
        Gate Events: \(results.performanceMetrics.gateStageDetections)
        Final Events: \(results.performanceMetrics.finalDetections)
        Processing Time: \(String(format: "%.1f", results.performanceMetrics.processingTimeMs))ms
        Detection Rate: \(String(format: "%.1f", results.performanceMetrics.detectionRate * 100))%
        """
    }
    
    private func formatDataQuality() -> String {
        let quality = exportData.rawData.dataQualityMetrics
        return """
        Total Samples: \(quality.totalSamples)
        Completeness: \(String(format: "%.1f", quality.dataCompletenessPercent))%
        Dropped Samples: \(quality.droppedSamples)
        Interruptions: \(quality.motionInterruptionCount)
        """
    }
}

// MARK: - Share Sheet
// Note: ShareSheet is already defined in DataVisualizationView.swift

// MARK: - Extensions

extension DateFormatter {
    static let compactDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}