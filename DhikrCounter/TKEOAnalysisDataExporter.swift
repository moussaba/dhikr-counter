import Foundation
import UIKit

// MARK: - Main Data Exporter

@MainActor
class TKEOAnalysisDataExporter {
    
    /// Prepare complete export data structure
    func prepareExportData(
        session: DhikrSession,
        sensorData: [SensorReading],
        detectedEvents: [PinchEvent],
        debugLogs: [String],
        options: TKEOExportOptions,
        watchDetectorMetadata: WatchDetectorMetadata? = nil
    ) async throws -> TKEOAnalysisExport {

        // Session metadata
        let sessionMetadata = ExportSessionMetadata(
            sessionId: session.id.uuidString,
            startTime: session.startTime,
            endTime: session.endTime,
            duration: session.sessionDuration,
            totalPinches: session.actualPinchCount ?? 0, // Use actual count if available, otherwise 0 to indicate no actual count
            detectedPinches: detectedEvents.count, // Always use detected events count
            manualCorrections: session.manualCorrections,
            deviceInfo: createExportDeviceInfo(from: session.deviceInfo),
            sessionNotes: session.sessionNotes,
            actualPinchCount: session.actualPinchCount // Keep original actual count
        )

        // Algorithm configuration (from current settings)
        let algorithmConfiguration = createAlgorithmConfiguration()

        // Raw sensor data
        let rawData = createRawSensorData(from: sensorData)

        // Analysis results
        let analysisResults = createAnalysisResults(from: detectedEvents)

        // Debug information
        let debugInformation = createDebugInformation(from: debugLogs, detectedEvents: detectedEvents)

        // Export metadata
        let exportMetadata = createExportMetadata(options: options)

        return TKEOAnalysisExport(
            sessionMetadata: sessionMetadata,
            algorithmConfiguration: algorithmConfiguration,
            rawData: rawData,
            analysisResults: analysisResults,
            debugInformation: debugInformation,
            exportMetadata: exportMetadata,
            watchDetectorMetadata: watchDetectorMetadata
        )
    }
    
    // MARK: - Data Conversion Methods
    
    private func createExportDeviceInfo(from deviceInfo: DeviceInfo) -> ExportDeviceInfo {
        return ExportDeviceInfo(
            deviceModel: deviceInfo.deviceModel,
            systemVersion: deviceInfo.systemVersion,
            appVersion: deviceInfo.appVersion,
            samplingRate: deviceInfo.samplingRate,
            buildDate: Date(),
            exportedFrom: "iOS"
        )
    }
    
    private func createAlgorithmConfiguration() -> AlgorithmConfiguration {
        // Read configuration from UserDefaults
        let userDefaults = UserDefaults.standard
        
        let tkeoParams = TKEOParameters(
            sampleRate: Float(userDefaults.double(forKey: "tkeo_sampleRate")) > 0 ? 
                Float(userDefaults.double(forKey: "tkeo_sampleRate")) : 50.0,
            accelWeight: Float(userDefaults.double(forKey: "tkeo_accelWeight")) > 0 ? 
                Float(userDefaults.double(forKey: "tkeo_accelWeight")) : 1.0,
            gyroWeight: Float(userDefaults.double(forKey: "tkeo_gyroWeight")) > 0 ? 
                Float(userDefaults.double(forKey: "tkeo_gyroWeight")) : 1.5,
            madWindowSec: 3.0,
            gateThreshold: Float(userDefaults.double(forKey: "tkeo_gateThreshold")) > 0 ? 
                Float(userDefaults.double(forKey: "tkeo_gateThreshold")) : 3.5,
            refractoryPeriodMs: Float(userDefaults.double(forKey: "tkeo_refractoryPeriod")) > 0 ? 
                Float(userDefaults.double(forKey: "tkeo_refractoryPeriod")) * 1000 : 150,
            minWidthMs: 60,
            maxWidthMs: 400
        )
        
        let filterSettings = FilterSettings(
            bandpassLow: Float(userDefaults.double(forKey: "tkeo_bandpassLow")) > 0 ? 
                Float(userDefaults.double(forKey: "tkeo_bandpassLow")) : 3.0,
            bandpassHigh: Float(userDefaults.double(forKey: "tkeo_bandpassHigh")) > 0 ? 
                Float(userDefaults.double(forKey: "tkeo_bandpassHigh")) : 20.0,
            filterType: "Bandpass Butterworth",
            filterOrder: 4
        )
        
        // Load template information
        let templates = PinchDetector.loadExportTemplates()
        let templateMetadata = templates.enumerated().map { index, template in
            TemplateMetadata(
                index: index,
                vectorLength: template.vectorLength,
                channelsMeta: template.channelsMeta,
                version: template.version,
                preMs: template.preMs,
                postMs: template.postMs
            )
        }
        
        let templateParams = TemplateParameters(
            nccThreshold: Float(userDefaults.double(forKey: "tkeo_templateConfidence")) > 0 ? 
                Float(userDefaults.double(forKey: "tkeo_templateConfidence")) : 0.6,
            windowPreMs: 150,
            windowPostMs: 250,
            templateCount: templates.count,
            templateMetadata: templateMetadata
        )
        
        let detectionPipeline = DetectionPipelineConfig(
            twoStageDetection: true,
            gateStage: "TKEO Energy Operator",
            verifyStage: "Template NCC Matching",
            fusionMethod: "Weighted Linear Fusion"
        )
        
        return AlgorithmConfiguration(
            tkeoParams: tkeoParams,
            filterSettings: filterSettings,
            templateParams: templateParams,
            detectionPipeline: detectionPipeline
        )
    }
    
    private func createRawSensorData(from sensorData: [SensorReading]) -> RawSensorData {
        guard !sensorData.isEmpty else {
            return RawSensorData(
                sensorReadings: [],
                dataQualityMetrics: DataQualityMetrics(
                    totalSamples: 0,
                    droppedSamples: 0,
                    samplingRateStability: 0.0,
                    signalToNoiseRatio: nil,
                    motionInterruptionCount: 0,
                    dataCompletenessPercent: 0.0
                ),
                motionInterruptions: []
            )
        }
        
        let startTime = sensorData.first!.motionTimestamp
        
        // Convert sensor readings
        let exportReadings = sensorData.map { reading in
            let accelMag = sqrt(pow(reading.userAcceleration.x, 2) + 
                               pow(reading.userAcceleration.y, 2) + 
                               pow(reading.userAcceleration.z, 2))
            let rotationMag = sqrt(pow(reading.rotationRate.x, 2) + 
                                  pow(reading.rotationRate.y, 2) + 
                                  pow(reading.rotationRate.z, 2))
            
            return ExportSensorReading(
                timestamp: reading.motionTimestamp - startTime,
                absoluteTimestamp: Date(timeIntervalSince1970: reading.epochTimestamp),
                accelerationX: reading.userAcceleration.x,
                accelerationY: reading.userAcceleration.y,
                accelerationZ: reading.userAcceleration.z,
                accelerationMagnitude: accelMag,
                rotationX: reading.rotationRate.x,
                rotationY: reading.rotationRate.y,
                rotationZ: reading.rotationRate.z,
                rotationMagnitude: rotationMag
            )
        }
        
        // Calculate data quality metrics
        let dataQualityMetrics = calculateDataQuality(from: sensorData)
        
        // Extract motion interruptions (simplified - would need actual interruption data)
        let motionInterruptions: [ExportMotionInterruption] = []
        
        return RawSensorData(
            sensorReadings: exportReadings,
            dataQualityMetrics: dataQualityMetrics,
            motionInterruptions: motionInterruptions
        )
    }
    
    private func calculateDataQuality(from sensorData: [SensorReading]) -> DataQualityMetrics {
        let totalSamples = sensorData.count
        
        // Calculate sampling rate stability
        var intervals: [TimeInterval] = []
        for i in 1..<sensorData.count {
            intervals.append(sensorData[i].motionTimestamp - sensorData[i-1].motionTimestamp)
        }
        
        let meanInterval = intervals.reduce(0, +) / Double(intervals.count)
        let variance = intervals.map { pow($0 - meanInterval, 2) }.reduce(0, +) / Double(intervals.count)
        let stability = 1.0 - (sqrt(variance) / meanInterval) // Higher is better
        
        // Simple SNR calculation (placeholder)
        let accelerations = sensorData.map { 
            sqrt(pow($0.userAcceleration.x, 2) + pow($0.userAcceleration.y, 2) + pow($0.userAcceleration.z, 2))
        }
        let meanAccel = accelerations.reduce(0, +) / Double(accelerations.count)
        let accelVariance = accelerations.map { pow($0 - meanAccel, 2) }.reduce(0, +) / Double(accelerations.count)
        let snr = meanAccel / sqrt(accelVariance)
        
        return DataQualityMetrics(
            totalSamples: totalSamples,
            droppedSamples: 0, // Would need to track this during collection
            samplingRateStability: stability,
            signalToNoiseRatio: snr,
            motionInterruptionCount: 0, // Would need actual interruption tracking
            dataCompletenessPercent: 100.0 // Assuming complete for now
        )
    }
    
    private func createAnalysisResults(from detectedEvents: [PinchEvent]) -> AnalysisResults {
        print("📊 TKEOAnalysisDataExporter: createAnalysisResults called with \(detectedEvents.count) events")
        
        // Convert pinch events to detected events
        let exportedEvents = detectedEvents.enumerated().map { index, event in
            DetectedEvent(
                eventId: "event_\(index + 1)_\(Int(event.tPeak * 1000))",
                tPeak: TimeInterval(event.tPeak),
                tStart: TimeInterval(event.tStart),
                tEnd: TimeInterval(event.tEnd),
                confidence: event.confidence,
                gateScore: event.gateScore,
                nccScore: event.ncc,
                templateIndex: nil, // Would need to track which template matched
                isVerified: event.ncc >= 0.6 // Based on NCC threshold
            )
        }
        
        // Create gate events (simplified - would need actual gate detection data)
        let gateEvents = detectedEvents.enumerated().map { index, event in
            GateEvent(
                eventId: "gate_\(index + 1)",
                timestamp: TimeInterval(event.tPeak),
                tkeoValue: event.gateScore,
                threshold: 3.5, // Default threshold
                wasVerified: event.ncc >= 0.6
            )
        }
        
        // Performance metrics
        let finalEventCount = exportedEvents.count
        let gateEventCount = gateEvents.count
        let rejectionRate = gateEventCount > 0 ? 1.0 - (Double(finalEventCount) / Double(gateEventCount)) : 0.0
        
        let performanceMetrics = PerformanceMetrics(
            detectionRate: finalEventCount > 0 ? 1.0 : 0.0, // Would need ground truth for real rate
            falsePositiveRate: nil, // Would need manual validation
            processingTimeMs: 0.0, // Would need to track actual processing time
            gateStageDetections: gateEventCount,
            finalDetections: finalEventCount,
            rejectionRate: rejectionRate
        )
        
        // Processed signals (placeholder - would need actual signal processing data)
        let processedSignals = ProcessedSignals(
            bandpassFiltered: SignalData(
                accelerationX: [],
                accelerationY: [],
                accelerationZ: [],
                accelerationMagnitude: [],
                rotationX: [],
                rotationY: [],
                rotationZ: [],
                rotationMagnitude: []
            ),
            jerkSignals: SignalData(
                accelerationX: [],
                accelerationY: [],
                accelerationZ: [],
                accelerationMagnitude: [],
                rotationX: [],
                rotationY: [],
                rotationZ: [],
                rotationMagnitude: []
            ),
            tkeoSignals: SignalData(
                accelerationX: [],
                accelerationY: [],
                accelerationZ: [],
                accelerationMagnitude: [],
                rotationX: [],
                rotationY: [],
                rotationZ: [],
                rotationMagnitude: []
            ),
            fusionScore: SignalData(
                accelerationX: [],
                accelerationY: [],
                accelerationZ: [],
                accelerationMagnitude: [],
                rotationX: [],
                rotationY: [],
                rotationZ: [],
                rotationMagnitude: []
            ),
            timestamps: []
        )
        
        return AnalysisResults(
            detectedEvents: exportedEvents,
            gateEvents: gateEvents,
            performanceMetrics: performanceMetrics,
            processedSignals: processedSignals
        )
    }
    
    private func createDebugInformation(from debugLogs: [String], detectedEvents: [PinchEvent]) -> DebugInformation {
        // Template matching details (simplified)
        let templateMatchingDetails = detectedEvents.enumerated().map { index, event in
            TemplateMatchingResult(
                templateIndex: 0, // Would need actual template index
                eventTimestamp: TimeInterval(event.tPeak),
                nccScore: event.ncc,
                windowStart: TimeInterval(event.tStart),
                windowEnd: TimeInterval(event.tEnd),
                matched: event.ncc >= 0.6
            )
        }
        
        // Intermediate results (placeholder)
        let intermediateResults: [String: AnyCodable] = [
            "total_samples_processed": AnyCodable(0),
            "filter_initialization_time_ms": AnyCodable(0.0),
            "template_loading_time_ms": AnyCodable(0.0),
            "peak_detection_candidates": AnyCodable(0)
        ]
        
        return DebugInformation(
            processingLogs: debugLogs,
            intermediateResults: intermediateResults,
            templateMatchingDetails: templateMatchingDetails,
            filterResponseData: nil // Would include actual filter response if needed
        )
    }
    
    private func createExportMetadata(options: TKEOExportOptions) -> ExportMetadata {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        
        return ExportMetadata(
            exportDate: Date(),
            exportVersion: "1.0.0",
            exportedBy: "Dhikr Counter iOS App",
            exportFormat: options.formats.map { $0.rawValue }.joined(separator: ", "),
            fileStructureVersion: "2024.1",
            checksums: [:] // Would calculate actual checksums for files
        )
    }
}

// MARK: - Supporting Extensions

extension PinchDetector {
    static func loadExportTemplates() -> [PinchTemplate] {
        // Load from bundle or documents directory
        // This is a placeholder implementation
        guard let bundlePath = Bundle.main.path(forResource: "trained_templates", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: bundlePath)),
              let templateData = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            // Return default template if file doesn't exist
            return [PinchDetector.createDefaultTemplate()]
        }
        
        return templateData.compactMap { dict in
            guard let fs = dict["fs"] as? Double,
                  let preMs = dict["preMs"] as? Double,
                  let postMs = dict["postMs"] as? Double,
                  let vectorLength = dict["vectorLength"] as? Int,
                  let data = dict["data"] as? [Double],
                  let channelsMeta = dict["channelsMeta"] as? String,
                  let version = dict["version"] as? String else {
                return nil
            }
            
            return PinchTemplate(
                fs: Float(fs),
                preMs: Float(preMs),
                postMs: Float(postMs),
                vectorLength: vectorLength,
                data: data.map { Float($0) },
                channelsMeta: channelsMeta,
                version: version
            )
        }
    }
}