import Foundation
import SwiftUI
import Charts

// MARK: - Export Data Models

/// Complete TKEO analysis export package
struct TKEOAnalysisExport: Codable {
    let sessionMetadata: ExportSessionMetadata
    let algorithmConfiguration: AlgorithmConfiguration
    let rawData: RawSensorData
    let analysisResults: AnalysisResults
    let debugInformation: DebugInformation
    let exportMetadata: ExportMetadata
    let watchDetectorMetadata: WatchDetectorMetadata?
}

/// Session metadata for export
struct ExportSessionMetadata: Codable {
    let sessionId: String
    let startTime: Date
    let endTime: Date?
    let duration: TimeInterval
    let totalPinches: Int
    let detectedPinches: Int
    let manualCorrections: Int
    let deviceInfo: ExportDeviceInfo
    let sessionNotes: String?
    let actualPinchCount: Int?
}

/// Device information for export
struct ExportDeviceInfo: Codable {
    let deviceModel: String
    let systemVersion: String
    let appVersion: String
    let samplingRate: Double
    let buildDate: Date
    let exportedFrom: String // "iOS" or "watchOS"
}

/// Algorithm configuration used for analysis
struct AlgorithmConfiguration: Codable {
    let tkeoParams: TKEOParameters
    let filterSettings: FilterSettings
    let templateParams: TemplateParameters
    let detectionPipeline: DetectionPipelineConfig
}

/// TKEO algorithm parameters
struct TKEOParameters: Codable {
    let sampleRate: Float
    let accelWeight: Float
    let gyroWeight: Float
    let madWindowSec: Float
    let gateThreshold: Float
    let refractoryPeriodMs: Float
    let minWidthMs: Float
    let maxWidthMs: Float
}

/// Filter configuration
struct FilterSettings: Codable {
    let bandpassLow: Float
    let bandpassHigh: Float
    let filterType: String
    let filterOrder: Int?
}

/// Template matching parameters
struct TemplateParameters: Codable {
    let nccThreshold: Float
    let windowPreMs: Float
    let windowPostMs: Float
    let templateCount: Int
    let templateMetadata: [TemplateMetadata]
}

/// Template metadata
struct TemplateMetadata: Codable {
    let index: Int
    let vectorLength: Int
    let channelsMeta: String
    let version: String
    let preMs: Float
    let postMs: Float
}

/// Detection pipeline configuration
struct DetectionPipelineConfig: Codable {
    let twoStageDetection: Bool
    let gateStage: String // "TKEO"
    let verifyStage: String // "Template Matching"
    let fusionMethod: String
}

/// Raw sensor data for export
struct RawSensorData: Codable {
    let sensorReadings: [ExportSensorReading]
    let dataQualityMetrics: DataQualityMetrics
    let motionInterruptions: [ExportMotionInterruption]
}

/// Individual sensor reading for export
struct ExportSensorReading: Codable {
    let timestamp: TimeInterval // Relative time from session start
    let absoluteTimestamp: Date
    let accelerationX: Double
    let accelerationY: Double
    let accelerationZ: Double
    let accelerationMagnitude: Double
    let rotationX: Double
    let rotationY: Double
    let rotationZ: Double
    let rotationMagnitude: Double
}

/// Data quality assessment
struct DataQualityMetrics: Codable {
    let totalSamples: Int
    let droppedSamples: Int
    let samplingRateStability: Double
    let signalToNoiseRatio: Double?
    let motionInterruptionCount: Int
    let dataCompletenessPercent: Double
}

/// Motion interruption events (export-specific)
struct ExportMotionInterruption: Codable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let reason: String
    let duration: TimeInterval
}

/// Analysis results from TKEO detection
struct AnalysisResults: Codable {
    let detectedEvents: [DetectedEvent]
    let gateEvents: [GateEvent]
    let performanceMetrics: PerformanceMetrics
    let processedSignals: ProcessedSignals
}

/// Detected pinch event
struct DetectedEvent: Codable {
    let eventId: String
    let tPeak: TimeInterval
    let tStart: TimeInterval
    let tEnd: TimeInterval
    let confidence: Float
    let gateScore: Float
    let nccScore: Float
    let templateIndex: Int?
    let isVerified: Bool
}

/// Gate-stage detection event
struct GateEvent: Codable {
    let eventId: String
    let timestamp: TimeInterval
    let tkeoValue: Float
    let threshold: Float
    let wasVerified: Bool
}

/// Performance metrics
struct PerformanceMetrics: Codable {
    let detectionRate: Double
    let falsePositiveRate: Double?
    let processingTimeMs: Double
    let gateStageDetections: Int
    let finalDetections: Int
    let rejectionRate: Double
}

/// Processed signal data for visualization
struct ProcessedSignals: Codable {
    let bandpassFiltered: SignalData
    let jerkSignals: SignalData
    let tkeoSignals: SignalData
    let fusionScore: SignalData
    let timestamps: [TimeInterval]
}

/// Signal data container
struct SignalData: Codable {
    let accelerationX: [Float]
    let accelerationY: [Float]
    let accelerationZ: [Float]
    let accelerationMagnitude: [Float]
    let rotationX: [Float]
    let rotationY: [Float]
    let rotationZ: [Float]
    let rotationMagnitude: [Float]
}

/// Debug information from analysis
struct DebugInformation: Codable {
    let processingLogs: [String]
    let intermediateResults: [String: AnyCodable]
    let templateMatchingDetails: [TemplateMatchingResult]
    let filterResponseData: FilterResponseData?
}

/// Template matching result details
struct TemplateMatchingResult: Codable {
    let templateIndex: Int
    let eventTimestamp: TimeInterval
    let nccScore: Float
    let windowStart: TimeInterval
    let windowEnd: TimeInterval
    let matched: Bool
}

/// Filter response characteristics
struct FilterResponseData: Codable {
    let frequencyResponse: [Float]
    let phaseResponse: [Float]
    let groupDelay: [Float]
    let frequencies: [Float]
}

/// Export metadata
struct ExportMetadata: Codable {
    let exportDate: Date
    let exportVersion: String
    let exportedBy: String
    let exportFormat: String
    let fileStructureVersion: String
    let checksums: [String: String]
}

/// Type-erased codable container for dynamic data
struct AnyCodable: Codable {
    let value: Any
    
    init<T>(_ value: T) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unable to decode AnyCodable"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AnyCodable($0) })
        case let dictValue as [String: Any]:
            try container.encode(dictValue.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Unable to encode AnyCodable"))
        }
    }
}

// MARK: - Export Format Types

/// Available export formats
enum TKEOExportFormat: String, CaseIterable {
    case html = "HTML Report"
    case json = "JSON Data"
    case pdf = "PDF Report"
    case csv = "CSV Data"
    
    var fileExtension: String {
        switch self {
        case .html: return "html"
        case .json: return "json"
        case .pdf: return "pdf"
        case .csv: return "csv"
        }
    }
    
    var mimeType: String {
        switch self {
        case .html: return "text/html"
        case .json: return "application/json"
        case .pdf: return "application/pdf"
        case .csv: return "text/csv"
        }
    }
}

/// Export options configuration
struct TKEOExportOptions {
    var formats: Set<TKEOExportFormat>
    var includeRawData: Bool
    var includeDebugLogs: Bool
    var includeChartImages: Bool
    var chartImageFormat: ChartImageFormat
    var compressionLevel: CompressionLevel
    
    static let `default` = TKEOExportOptions(
        formats: [.html, .json],
        includeRawData: true,
        includeDebugLogs: true,
        includeChartImages: true,
        chartImageFormat: .png,
        compressionLevel: .medium
    )
}

/// Chart image export format
enum ChartImageFormat: String, CaseIterable {
    case png = "PNG"
    case jpeg = "JPEG"
    
    var fileExtension: String {
        return rawValue.lowercased()
    }
}

/// Compression level for export packages
enum CompressionLevel: String, CaseIterable {
    case none = "None"
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    
    var compressionRatio: Float {
        switch self {
        case .none: return 0.0
        case .low: return 0.3
        case .medium: return 0.6
        case .high: return 0.8
        }
    }
}