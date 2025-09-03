//
//  VideoBasedScanner.swift
//  check-id
//
//  Created: September 2024
//  Purpose: Enhanced video-based ID scanner with frame-by-frame analysis
//

import SwiftUI
import AVFoundation
import Vision
import CoreImage

// MARK: - Video-Based Scanner Results

struct VideoScanResults {
    var extractedData: LicenseData
    var frameCount: Int
    var averageConfidence: Double
    var qualityScore: Double
    var processingTime: TimeInterval
    var frameAnalyses: [FrameAnalysis]
    var aggregatedText: String
    var barcodeData: String?
    var faceDetectionResults: FaceDetectionResults?
    var currentFrame: UIImage?
    var dataCompleteness: DataCompleteness
    var fieldProgress: FieldProgress
}

struct FieldProgress {
    let requiredFields: [String]
    let capturedFields: [String: String]
    let missingFields: [String]
    let progressPercentage: Double
    let isComplete: Bool
    let fieldStatuses: [String: FieldStatus]
}

enum FieldStatus {
    case notFound
    case partial
    case complete
    case excellent
}

struct DataCompleteness {
    let requiredFields: [String]
    let capturedFields: [String]
    let missingFields: [String]
    let completenessPercentage: Double
    let isComplete: Bool
    let validationStatus: ValidationStatus
}

enum ValidationStatus {
    case incomplete
    case partial
    case complete
    case excellent
}

struct FrameAnalysis {
    let frameIndex: Int
    let timestamp: TimeInterval
    let textExtracted: String
    let confidence: Double
    let quality: String
    let faceDetected: Bool
    let barcodeDetected: Bool
    let imageQuality: ImageQualityMetrics
}

struct ImageQualityMetrics {
    let brightness: Double
    let contrast: Double
    let sharpness: Double
    let blur: Double
    let overallQuality: String
}

struct FaceDetectionResults {
    let faceDetected: Bool
    let confidence: Double
    let faceRect: CGRect?
    let quality: String
    let timestamp: TimeInterval
}

// MARK: - Video-Based Scanner

class VideoBasedScanner: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var currentFrame: UIImage?
    @Published var qualityFeedback: QualityFeedback = .none
    @Published var scanProgress: Double = 0.0
    @Published var scanResults: VideoScanResults?
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureMovieFileOutput?
    var previewLayer: AVCaptureVideoPreviewLayer?
    private var frameProcessor: VideoFrameProcessor?
    private var scanTimer: Timer?
    private var scanDuration: TimeInterval = 5.0 // 5 seconds
    
    enum QualityFeedback {
        case none
        case good
        case poor
        case excellent
    }
    
    func startCameraPreview() {
        print("Starting camera preview for face recognition...")
        setupCaptureSession()
    }
    
    func startScanning(for side: LicenseSide) {
        print("Starting video scan for \(side) side...")
        isScanning = true
        scanProgress = 0.0
        qualityFeedback = .none
        
        // Check camera permissions first
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            if granted {
                print("Camera permission granted")
                // Setup capture session on background thread
                DispatchQueue.global(qos: .userInitiated).async {
                    self?.setupCaptureSession()
                    
                    // Start frame processing on background thread
                    self?.startFrameProcessing(for: side)
                    
                    DispatchQueue.main.async {
                        // Start scan timer on main thread
                        self?.scanTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                            self?.updateScanProgress()
                        }
                    }
                }
            } else {
                print("Camera permission denied")
                DispatchQueue.main.async { [weak self] in
                    self?.isScanning = false
                }
            }
        }
    }
    
    func stopScanning() {
        isScanning = false
        scanTimer?.invalidate()
        scanTimer = nil
        
        // Stop capture session on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.stopRunning()
            self?.frameProcessor?.stopProcessing()
        }
    }
    
    private func setupCaptureSession() {
        print("Setting up capture session...")
        captureSession = AVCaptureSession()
        
        guard let session = captureSession else {
            print("Failed to create capture session")
            DispatchQueue.main.async { [weak self] in
                self?.isScanning = false
            }
            return
        }
        
        // Configure session on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.configureCaptureSession(session)
        }
    }
    
    private func configureCaptureSession(_ session: AVCaptureSession) {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Failed to get camera device")
            DispatchQueue.main.async { [weak self] in
                self?.isScanning = false
            }
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                print("Failed to add camera input")
                DispatchQueue.main.async { [weak self] in
                    self?.isScanning = false
                }
                return
            }
            
            // Add video data output for real-time frame capture
            let videoDataOutput = AVCaptureVideoDataOutput()
            videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: .userInitiated))
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            
            if session.canAddOutput(videoDataOutput) {
                session.addOutput(videoDataOutput)
            } else {
                print("Failed to add video data output")
            }
            
            videoOutput = AVCaptureMovieFileOutput()
            if let videoOutput = videoOutput,
               session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            } else {
                print("Failed to add video output")
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.previewLayer = AVCaptureVideoPreviewLayer(session: session)
                self?.previewLayer?.videoGravity = .resizeAspectFill
            }
            
            // Start the session
            session.startRunning()
            print("Capture session started successfully")
            
            DispatchQueue.main.async {
                print("Capture session setup completed successfully")
            }
            
        } catch {
            print("Failed to setup capture session: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.isScanning = false
            }
        }
    }
    
    private func startFrameProcessing(for side: LicenseSide) {
        frameProcessor = VideoFrameProcessor()
        frameProcessor?.delegate = self
        frameProcessor?.startProcessing(session: captureSession, side: side, duration: scanDuration)
    }
    
    private func updateScanProgress() {
        guard isScanning else { return }
        
        // Ensure scanDuration is valid to prevent division by zero
        guard scanDuration > 0 else {
            print("Warning: scanDuration is zero or negative")
            stopScanning()
            return
        }
        
        // Calculate progress increment safely
        let increment = 0.1 / scanDuration
        
        // Ensure we don't exceed 1.0
        if scanProgress + increment <= 1.0 {
            scanProgress += increment
        } else {
            scanProgress = 1.0
        }
        
        if scanProgress >= 1.0 {
            stopScanning()
        }
    }
}

// MARK: - Video Frame Processor

class VideoFrameProcessor: NSObject {
    weak var delegate: VideoFrameProcessorDelegate?
    private var frameCount = 0
    private var extractedTexts: [String] = []
    private var confidenceScores: [Double] = []
    private var frameAnalyses: [FrameAnalysis] = []
    private var barcodeData: String?
    private var faceDetectionResults: FaceDetectionResults?
    private var scanStartTime: Date?
    private var capturedFrames: [UIImage] = []
    private var isProcessing = false
    
    func startProcessing(session: AVCaptureSession?, side: LicenseSide, duration: TimeInterval) {
        frameCount = 0
        extractedTexts.removeAll()
        confidenceScores.removeAll()
        frameAnalyses.removeAll()
        capturedFrames.removeAll()
        scanStartTime = Date()
        isProcessing = true
        
        print("Starting frame processing for \(side) side")
        
        // Start frame extraction timer on main thread
        DispatchQueue.main.async {
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                guard let self = self, self.isProcessing else {
                    timer.invalidate()
                    return
                }
                
                // Process the most recent captured frame
                if let latestFrame = self.capturedFrames.last {
                    self.processFrame(latestFrame, side: side)
                }
                
                // Process real-time feedback every few frames
                if self.frameCount % 5 == 0 {
                    self.processFrameForRealTimeFeedback(side: side)
                }
                
                // Stop after duration
                if let startTime = self.scanStartTime,
                   Date().timeIntervalSince(startTime) >= duration {
                    timer.invalidate()
                    self.isProcessing = false
                    self.finalizeProcessing()
                }
            }
        }
    }
    
    func addCapturedFrame(_ frame: UIImage) {
        // Keep only the most recent frames to avoid memory issues
        if capturedFrames.count > 10 {
            capturedFrames.removeFirst()
        }
        capturedFrames.append(frame)
        
        print("📸 Frame captured: \(capturedFrames.count) frames stored")
    }
    
    func stopProcessing() {
        isProcessing = false
        finalizeProcessing()
    }
    
    private func processFrame(_ frame: UIImage, side: LicenseSide) {
        print("🔍 Processing frame \(frameCount + 1) for \(side) side")
        
        let analysis = analyzeFrame(frame, side: side)
        frameAnalyses.append(analysis)
        
        print("📝 Frame \(frameCount + 1) analysis:")
        print("   Text extracted: \(analysis.textExtracted.count) characters")
        print("   Confidence: \(String(format: "%.2f", analysis.confidence * 100))%")
        print("   Quality: \(analysis.imageQuality.overallQuality)")
        
        self.delegate?.frameProcessor(self, didUpdateQuality: self.getQualityFeedback(analysis.imageQuality))
        
        self.frameCount += 1
    }
    
    private func processFrameForRealTimeFeedback(side: LicenseSide) {
        // Process current aggregated data for real-time feedback
        let currentText = aggregateTextFromFrames()
        
        // Create temporary license data for validation
        var tempLicenseData = LicenseData()
        if side == .front {
            tempLicenseData.frontText = currentText
            tempLicenseData.ocrExtractedFields = parseLicenseTextComprehensive(currentText)
        } else {
            tempLicenseData.barcodeData = currentText
            tempLicenseData.barcodeExtractedFields = parseBarcodeDataComprehensive(currentText)
        }
        
        // Check data completeness
        let dataCompleteness = validateDataCompleteness(licenseData: tempLicenseData, side: side)
        
        // Calculate field progress for specific driver's license fields
        let fieldProgress = calculateFieldProgress(side == .front ? tempLicenseData.ocrExtractedFields : tempLicenseData.barcodeExtractedFields)
        
        // Update quality feedback based on field progress and side
        let qualityFeedback: VideoBasedScanner.QualityFeedback
        if side == .back {
            // For back side (barcode), be more lenient since barcodes can be more challenging
            if fieldProgress.isComplete || fieldProgress.progressPercentage >= 80 {
                qualityFeedback = .excellent
            } else if fieldProgress.progressPercentage >= 60 {
                qualityFeedback = .good
            } else if fieldProgress.progressPercentage >= 40 {
                qualityFeedback = .good
            } else {
                qualityFeedback = .poor
            }
        } else {
            // For front side (OCR), use standard thresholds
            if fieldProgress.isComplete {
                qualityFeedback = .excellent
            } else if fieldProgress.progressPercentage >= 75 {
                qualityFeedback = .good
            } else if fieldProgress.progressPercentage >= 50 {
                qualityFeedback = .good
            } else {
                qualityFeedback = .poor
            }
        }
        
        DispatchQueue.main.async {
            self.delegate?.frameProcessor(self, didUpdateQuality: qualityFeedback)
        }
        
        print("🎥 Real-time Field Progress Check (\(side == .front ? "Front OCR" : "Back Barcode")):")
        print("   Progress: \(String(format: "%.1f", fieldProgress.progressPercentage))%")
        print("   Captured Fields: \(fieldProgress.capturedFields.count)/\(fieldProgress.requiredFields.count)")
        print("   Missing Fields: \(fieldProgress.missingFields)")
        print("   Is Complete: \(fieldProgress.isComplete)")
        print("   Quality Feedback: \(qualityFeedback)")
        print("   Data Completeness: \(String(format: "%.1f", dataCompleteness.completenessPercentage))%")
        
        // Log individual field statuses
        print("   Individual Field Status:")
        for field in fieldProgress.requiredFields {
            let status = fieldProgress.fieldStatuses[field] ?? .notFound
            let value = fieldProgress.capturedFields[field] ?? ""
            print("     \(field): \(status) - '\(value)'")
        }
    }
    
    private func analyzeFrame(_ frame: UIImage, side: LicenseSide) -> FrameAnalysis {
        let startTime = Date()
        
        // Extract text using OCR (for front side) or barcode (for back side)
        var text = ""
        var confidence = 0.0
        var barcodeDetected = false
        var faceDetected = false
        
        if side == .front {
            // Front side: OCR text extraction
            let (extractedText, textConfidence) = extractTextFromFrame(frame)
            text = extractedText
            confidence = textConfidence
            
            // Store for aggregation
            if !text.isEmpty {
                extractedTexts.append(text)
                confidenceScores.append(confidence)
            }
            
            // Face detection for front side
            faceDetected = detectFaceInFrame(frame)
        } else {
            // Back side: Barcode detection
            let (barcodeText, barcodeConfidence) = extractBarcodeFromFrame(frame)
            text = barcodeText
            confidence = barcodeConfidence
            barcodeDetected = !barcodeText.isEmpty
            
            // Store for aggregation
            if !text.isEmpty {
                extractedTexts.append(text)
                confidenceScores.append(confidence)
            }
        }
        
        // Analyze image quality
        let imageQuality = analyzeImageQuality(frame)
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        return FrameAnalysis(
            frameIndex: frameCount,
            timestamp: processingTime,
            textExtracted: text,
            confidence: confidence,
            quality: imageQuality.overallQuality,
            faceDetected: faceDetected,
            barcodeDetected: barcodeDetected,
            imageQuality: imageQuality
        )
    }
    
    private func extractBarcodeFromFrame(_ frame: UIImage) -> (String, Double) {
        guard let cgImage = frame.cgImage else { 
            print("❌ Failed to get CGImage for barcode detection")
            return ("", 0.0) 
        }
        
        print("🔍 Starting barcode extraction...")
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNDetectBarcodesRequest { request, error in
            if let error = error {
                print("❌ Barcode Request Error: \(error)")
            }
        }
        
        // Support all common barcode formats found on driver's licenses
        request.symbologies = [
            .pdf417,      // Most common on US driver's licenses
            .code128,     // Alternative format
            .code39,      // Alternative format
            .qr,          // Some modern licenses use QR codes
            .aztec,       // Some states use Aztec codes
            .code93,      // Alternative format
            .ean8,        // Alternative format
            .ean13,       // Alternative format
            .upce         // Alternative format
        ]
        
        do {
            try requestHandler.perform([request])
            
            guard let observations = request.results else {
                print("❌ Barcode detection failed - No observations")
                return ("", 0.0)
            }
            
            print("✅ Barcode detection found \(observations.count) barcode observations")
            
            // Process all detected barcodes and find the best one
            var bestBarcode = ""
            var bestConfidence = 0.0
            
            for (index, observation) in observations.enumerated() {
                let payload = observation.payloadStringValue ?? ""
                let confidence = Double(observation.confidence)
                let symbology = observation.symbology
                
                print("📋 Barcode \(index + 1):")
                print("   Type: \(symbology)")
                print("   Confidence: \(String(format: "%.1f", confidence * 100))%")
                print("   Payload length: \(payload.count) characters")
                print("   Payload preview: \(String(payload.prefix(100)))...")
                
                // Prefer PDF417 barcodes (most common on driver's licenses)
                if symbology == .pdf417 && confidence > bestConfidence {
                    bestBarcode = payload
                    bestConfidence = confidence
                } else if payload.count > bestBarcode.count && confidence > 0.5 {
                    // If no PDF417, prefer longer payloads with good confidence
                    bestBarcode = payload
                    bestConfidence = confidence
                }
            }
            
            if !bestBarcode.isEmpty {
                print("📝 Best barcode result:")
                print("   Type: PDF417 (Driver's License)")
                print("   Confidence: \(String(format: "%.1f", bestConfidence * 100))%")
                print("   Data length: \(bestBarcode.count) characters")
                print("   Data preview: \(String(bestBarcode.prefix(200)))...")
                
                return (bestBarcode, bestConfidence)
            } else {
                print("❌ No suitable barcode found")
                return ("", 0.0)
            }
            
        } catch {
            print("❌ Barcode detection error: \(error)")
        }
        
        return ("", 0.0)
    }
    
    private func extractTextFromFrame(_ frame: UIImage) -> (String, Double) {
        guard let cgImage = frame.cgImage else { 
            print("❌ Failed to get CGImage for OCR")
            return ("", 0.0) 
        }
        
        print("🔍 Starting OCR extraction...")
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                print("❌ OCR Request Error: \(error)")
            }
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        do {
            try requestHandler.perform([request])
            
            guard let observations = request.results else {
                print("❌ OCR Failed - No observations")
                return ("", 0.0)
            }
            
            print("✅ OCR found \(observations.count) text observations")
            
            let recognizedStrings = observations.compactMap { observation -> (String, Float)? in
                let topCandidate = observation.topCandidates(1).first
                return topCandidate.map { ($0.string, $0.confidence) }
            }
            
            let text = recognizedStrings.map { $0.0 }.joined(separator: " ")
            let avgConfidence = recognizedStrings.isEmpty ? 0.0 : Double(recognizedStrings.map { $0.1 }.reduce(0, +) / Float(recognizedStrings.count))
            
            print("📝 OCR Result: '\(text)' (confidence: \(String(format: "%.1f", avgConfidence * 100))%)")
            
            return (text, avgConfidence)
        } catch {
            print("❌ OCR Error: \(error)")
        }
        
        return ("", 0.0)
    }
    
    private func analyzeImageQuality(_ frame: UIImage) -> ImageQualityMetrics {
        guard let cgImage = frame.cgImage else {
            return ImageQualityMetrics(brightness: 0, contrast: 0, sharpness: 0, blur: 0, overallQuality: "Poor")
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bitsPerPixel = cgImage.bitsPerPixel
        let bytesPerPixel = bitsPerPixel / 8
        
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return ImageQualityMetrics(brightness: 0, contrast: 0, sharpness: 0, blur: 0, overallQuality: "Poor")
        }
        
        var totalBrightness: Double = 0
        var totalContrast: Double = 0
        var totalSharpness: Double = 0
        
        // Sample pixels for analysis (every 10th pixel for performance)
        let sampleStep = 10
        var sampleCount = 0
        
        for y in stride(from: 0, to: height, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                // Use safe arithmetic to prevent overflow
                let pixelIndex = y * bytesPerRow + x * bytesPerPixel
                
                // Check bounds more carefully
                if pixelIndex >= 0 && pixelIndex < CFDataGetLength(data) - bytesPerPixel &&
                   pixelIndex + 2 < CFDataGetLength(data) {
                    let r = Double(bytes[pixelIndex])
                    let g = Double(bytes[pixelIndex + 1])
                    let b = Double(bytes[pixelIndex + 2])
                    
                    // Calculate brightness
                    let brightness = (r + g + b) / 3.0
                    totalBrightness += brightness
                    
                    // Calculate contrast (simplified)
                    let maxChannel = max(r, g, b)
                    let minChannel = min(r, g, b)
                    let contrast = maxChannel - minChannel
                    totalContrast += contrast
                    
                    sampleCount += 1
                }
            }
        }
        
        let avgBrightness = sampleCount > 0 ? totalBrightness / Double(sampleCount) : 0
        let avgContrast = sampleCount > 0 ? totalContrast / Double(sampleCount) : 0
        
        // Calculate sharpness (edge detection)
        totalSharpness = calculateSharpness(bytes: bytes, width: width, height: height, bytesPerRow: bytesPerRow, bytesPerPixel: bytesPerPixel)
        
        // Determine overall quality
        let quality = determineOverallQuality(brightness: avgBrightness, contrast: avgContrast, sharpness: totalSharpness)
        
        return ImageQualityMetrics(
            brightness: avgBrightness,
            contrast: avgContrast,
            sharpness: totalSharpness,
            blur: 0, // Simplified for now
            overallQuality: quality
        )
    }
    
    private func calculateSharpness(bytes: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int, bytesPerPixel: Int) -> Double {
        var totalSharpness: Double = 0
        var sampleCount = 0
        
        // Sample every 20th pixel for edge detection
        let sampleStep = 20
        let totalBytes = height * bytesPerRow
        
        // Add safety checks to prevent overflow
        guard width > 0, height > 0, bytesPerRow > 0, bytesPerPixel > 0, totalBytes > 0 else {
            print("Warning: Invalid image dimensions for sharpness calculation")
            return 0.0
        }
        
        for y in stride(from: sampleStep, to: height - sampleStep, by: sampleStep) {
            for x in stride(from: sampleStep, to: width - sampleStep, by: sampleStep) {
                // Use safe arithmetic to prevent overflow
                let currentPixel = y * bytesPerRow + x * bytesPerPixel
                let rightPixel = y * bytesPerRow + (x + sampleStep) * bytesPerPixel
                let bottomPixel = (y + sampleStep) * bytesPerRow + x * bytesPerPixel
                
                // Check bounds more carefully
                if currentPixel >= 0 && currentPixel < totalBytes - bytesPerPixel &&
                   rightPixel >= 0 && rightPixel < totalBytes - bytesPerPixel &&
                   bottomPixel >= 0 && bottomPixel < totalBytes - bytesPerPixel &&
                   currentPixel + 2 < totalBytes &&
                   rightPixel + 2 < totalBytes &&
                   bottomPixel + 2 < totalBytes {
                    
                    let currentBrightness = (Double(bytes[currentPixel]) + Double(bytes[currentPixel + 1]) + Double(bytes[currentPixel + 2])) / 3.0
                    let rightBrightness = (Double(bytes[rightPixel]) + Double(bytes[rightPixel + 1]) + Double(bytes[rightPixel + 2])) / 3.0
                    let bottomBrightness = (Double(bytes[bottomPixel]) + Double(bytes[bottomPixel + 1]) + Double(bytes[bottomPixel + 2])) / 3.0
                    
                    let horizontalEdge = abs(currentBrightness - rightBrightness)
                    let verticalEdge = abs(currentBrightness - bottomBrightness)
                    
                    totalSharpness += horizontalEdge + verticalEdge
                    sampleCount += 1
                }
            }
        }
        
        return sampleCount > 0 ? totalSharpness / Double(sampleCount) : 0
    }
    
    private func determineOverallQuality(brightness: Double, contrast: Double, sharpness: Double) -> String {
        var score = 0
        
        if brightness > 50 && brightness < 200 { score += 1 }
        if contrast > 30 { score += 1 }
        if sharpness > 20 { score += 1 }
        
        switch score {
        case 3: return "Excellent"
        case 2: return "Good"
        case 1: return "Fair"
        default: return "Poor"
        }
    }
    
    private func detectFaceInFrame(_ frame: UIImage) -> Bool {
        guard let cgImage = frame.cgImage else { return false }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNDetectFaceRectanglesRequest { request, error in
            if let error = error {
                print("Face detection error: \(error)")
            }
        }
        
        do {
            try requestHandler.perform([request])
            return !(request.results?.isEmpty ?? true)
        } catch {
            print("Face detection error: \(error)")
            return false
        }
    }
    
    private func detectBarcodeInFrame(_ frame: UIImage) -> Bool {
        guard let cgImage = frame.cgImage else { return false }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNDetectBarcodesRequest { request, error in
            if let error = error {
                print("Barcode detection error: \(error)")
            }
        }
        
        request.symbologies = [.qr, .code128, .code39, .pdf417, .aztec]
        
        do {
            try requestHandler.perform([request])
            return !(request.results?.isEmpty ?? true)
        } catch {
            print("Barcode detection error: \(error)")
            return false
        }
    }
    
    private func getQualityFeedback(_ quality: ImageQualityMetrics) -> VideoBasedScanner.QualityFeedback {
        switch quality.overallQuality {
        case "Excellent": return .excellent
        case "Good": return .good
        case "Fair": return .poor
        default: return .poor
        }
    }
    
    private func finalizeProcessing() {
        // Aggregate text from all frames using intelligent combination
        let aggregatedText = aggregateTextFromFrames()
        
        // Calculate average confidence
        let avgConfidence = confidenceScores.isEmpty ? 0.0 : confidenceScores.reduce(0, +) / Double(confidenceScores.count)
        
        // Create license data using comprehensive parsing
        var licenseData = LicenseData()
        
        // Determine if this was front or back scan based on the side
        if let firstAnalysis = frameAnalyses.first {
            if firstAnalysis.barcodeDetected {
                // Back side: Parse barcode data
                licenseData.barcodeData = aggregatedText
                licenseData.barcodeType = "PDF417 (Driver's License)"
                licenseData.barcodeExtractedFields = parseBarcodeDataComprehensive(aggregatedText)
                
                print("🎥 Video Scan - Back Side Results:")
                print("   Barcode Data: \(aggregatedText)")
                print("   Extracted Fields: \(licenseData.barcodeExtractedFields)")
            } else {
                // Front side: Parse OCR text
                licenseData.frontText = aggregatedText
                licenseData.ocrExtractedFields = parseLicenseTextComprehensive(aggregatedText)
                
                print("🎥 Video Scan - Front Side Results:")
                print("   OCR Text: \(aggregatedText)")
                print("   Extracted Fields: \(licenseData.ocrExtractedFields)")
            }
        }
        
        // Create scan results with comprehensive data
        let results = VideoScanResults(
            extractedData: licenseData,
            frameCount: frameCount,
            averageConfidence: avgConfidence,
            qualityScore: calculateOverallQualityScore(),
            processingTime: scanStartTime.map { Date().timeIntervalSince($0) } ?? 0,
            frameAnalyses: frameAnalyses,
            aggregatedText: aggregatedText,
            barcodeData: licenseData.barcodeData,
            faceDetectionResults: faceDetectionResults,
            currentFrame: getBestQualityFrame(),
            dataCompleteness: validateDataCompleteness(licenseData: licenseData, side: frameAnalyses.first?.barcodeDetected == true ? .back : .front),
            fieldProgress: calculateFieldProgress(frameAnalyses.first?.barcodeDetected == true ? licenseData.barcodeExtractedFields : licenseData.ocrExtractedFields)
        )
        
        print("🎥 Video Scan Complete:")
        print("   Frames Analyzed: \(frameCount)")
        print("   Average Confidence: \(String(format: "%.2f", avgConfidence * 100))%")
        print("   Quality Score: \(String(format: "%.2f", results.qualityScore * 100))%")
        print("   Processing Time: \(String(format: "%.2f", results.processingTime))s")
        print("   Data Completeness: \(String(format: "%.1f", results.dataCompleteness.completenessPercentage))%")
        print("   Validation Status: \(results.dataCompleteness.validationStatus)")
        print("   Missing Fields: \(results.dataCompleteness.missingFields)")
        print("   Field Progress: \(String(format: "%.1f", results.fieldProgress.progressPercentage))%")
        print("   All Fields Complete: \(results.fieldProgress.isComplete)")
        print("   Captured Fields: \(results.fieldProgress.capturedFields.count)/\(results.fieldProgress.requiredFields.count)")
        
        // Log individual field statuses
        print("   Individual Field Status:")
        for field in results.fieldProgress.requiredFields {
            let status = results.fieldProgress.fieldStatuses[field] ?? .notFound
            let value = results.fieldProgress.capturedFields[field] ?? ""
            print("     \(field): \(status) - '\(value)'")
        }
        
        DispatchQueue.main.async {
            self.delegate?.frameProcessor(self, didCompleteScan: results)
        }
    }
    
    private func validateDataCompleteness(licenseData: LicenseData, side: LicenseSide) -> DataCompleteness {
        let requiredFields: [String]
        let capturedFields: [String]
        
        if side == .front {
            // Required fields for front of license
            requiredFields = [
                "Name", "Date of Birth", "Driver License Number", "State", 
                "Class", "Expiration Date", "Issue Date", "Sex", "Height", 
                "Weight", "Eye Color"
            ]
            capturedFields = Array(licenseData.ocrExtractedFields.keys)
        } else {
            // Required fields for back of license (barcode) - focus on key identification fields
            requiredFields = [
                "Name", "Date of Birth", "Driver License Number", "State",
                "Class", "Expiration Date", "Issue Date", "Sex", "Height", 
                "Eye Color", "Address", "City", "ZIP Code"
            ]
            capturedFields = Array(licenseData.barcodeExtractedFields.keys)
        }
        
        let missingFields = requiredFields.filter { !capturedFields.contains($0) }
        let completenessPercentage = Double(requiredFields.count - missingFields.count) / Double(requiredFields.count) * 100
        
        let isComplete = missingFields.isEmpty || completenessPercentage >= 85 // Allow 85% completion for barcode
        let validationStatus: ValidationStatus
        
        if completenessPercentage >= 90 {
            validationStatus = .excellent
        } else if completenessPercentage >= 75 {
            validationStatus = .complete
        } else if completenessPercentage >= 50 {
            validationStatus = .partial
        } else {
            validationStatus = .incomplete
        }
        
        print("📊 Data Completeness Validation:")
        print("   Side: \(side == .front ? "Front (OCR)" : "Back (Barcode)")")
        print("   Required Fields: \(requiredFields.count)")
        print("   Captured Fields: \(capturedFields.count)")
        print("   Missing Fields: \(missingFields.count)")
        print("   Completeness: \(String(format: "%.1f", completenessPercentage))%")
        print("   Validation Status: \(validationStatus)")
        print("   Is Complete: \(isComplete)")
        
        return DataCompleteness(
            requiredFields: requiredFields,
            capturedFields: capturedFields,
            missingFields: missingFields,
            completenessPercentage: completenessPercentage,
            isComplete: isComplete,
            validationStatus: validationStatus
        )
    }
    
    private func getBestQualityFrame() -> UIImage? {
        // Find the frame with the best quality for display
        let bestFrame = frameAnalyses.max { first, second in
            let firstQuality = getQualityScore(first.imageQuality)
            let secondQuality = getQualityScore(second.imageQuality)
            return firstQuality < secondQuality
        }
        
        // Return the actual best quality frame from captured frames
        if let bestAnalysis = bestFrame,
           bestAnalysis.frameIndex < capturedFrames.count {
            let frame = capturedFrames[bestAnalysis.frameIndex]
            // Ensure the frame is properly oriented for display
            return ContentView.processImageForDisplay(frame)
        }
        
        // Fallback to the most recent frame
        if let lastFrame = capturedFrames.last {
            return ContentView.processImageForDisplay(lastFrame)
        }
        
        return nil
    }
    
    private func getQualityScore(_ quality: ImageQualityMetrics) -> Double {
        switch quality.overallQuality {
        case "Excellent": return 1.0
        case "Good": return 0.8
        case "Fair": return 0.6
        default: return 0.4
        }
    }
    
    private func aggregateTextFromFrames() -> String {
        // Instead of simple concatenation, intelligently combine data from multiple frames
        // to get the most complete and accurate information
        
        var allTexts: [String] = []
        var allConfidences: [Double] = []
        
        // Collect all texts and confidences from frames
        for (_, analysis) in frameAnalyses.enumerated() {
            if !analysis.textExtracted.isEmpty {
                allTexts.append(analysis.textExtracted)
                allConfidences.append(analysis.confidence)
            }
        }
        
        // If we have multiple frames with text, use intelligent aggregation
        if allTexts.count > 1 {
            return aggregateMultipleFrameData(allTexts, confidences: allConfidences)
        } else if allTexts.count == 1 {
            return allTexts[0]
        }
        
        return ""
    }
    
    private func aggregateMultipleFrameData(_ texts: [String], confidences: [Double]) -> String {
        // Create a comprehensive dataset by combining unique information from all frames
        var fieldData: [String: (value: String, confidence: Double, frequency: Int)] = [:]
        
        for (textIndex, text) in texts.enumerated() {
            let confidence = confidences[textIndex]
            
            // Parse the text into individual fields
            let fields = parseTextIntoFields(text)
            
            // Aggregate field data, keeping the highest confidence version of each field
            for (fieldName, fieldValue) in fields {
                let key = fieldName.lowercased()
                
                if let existing = fieldData[key] {
                    // If this frame has higher confidence or more complete data, use it
                    if confidence > existing.confidence || 
                       (confidence == existing.confidence && fieldValue.count > existing.value.count) {
                        fieldData[key] = (value: fieldValue, confidence: confidence, frequency: existing.frequency + 1)
                    } else {
                        fieldData[key] = (value: existing.value, confidence: existing.confidence, frequency: existing.frequency + 1)
                    }
                } else {
                    fieldData[key] = (value: fieldValue, confidence: confidence, frequency: 1)
                }
            }
        }
        
        // Reconstruct the text from the best field data
        return reconstructTextFromFields(fieldData)
    }
    
    private func parseTextIntoFields(_ text: String) -> [String: String] {
        var fields: [String: String] = [:]
        
        // Extract key information patterns from the text
        let patterns: [(name: String, pattern: String)] = [
            ("name", #"([A-Z]+\s+[A-Z]+\s+[A-Z]+)"#),
            ("dob", #"DOB\s+(\d{1,2}/\d{1,2}/\d{4})"#),
            ("license", #"([A-Z]\d{6})"#),
            ("state", #"^([A-Z]+)\s+DRIVER\s+LICENSE"#),
            ("class", #"CLASS\s+([A-Z])"#),
            ("exp", #"EXP\s+(\d{1,2}/\d{1,2}/\d{4})"#),
            ("iss", #"ISS\s+(\d{1,2}/\d{1,2}/\d{4})"#),
            ("sex", #"([MF])\d"#),
            ("height", #"(\d{1,2})['\"]\s*[-]?\s*(\d{1,2})[\"]"#),
            ("weight", #"(\d{3})lb"#),
            ("eye_color", #"\b(BLU|BLUE|BRN|BROWN|GRN|GREEN|GRY|GRAY|HAZ|HAZEL|BLK|BLACK|AMB|AMBER|MUL|MULTI|PINK|PUR|PURPLE|YEL|YELLOW|WHI|WHITE|MAR|MARBLE|CHR|CHROME|GOL|GOLD|SIL|SILVER|COPPER|BURGUNDY|VIOLET|INDIGO|TEAL|TURQUOISE|AQUA|CYAN|LIME|OLIVE|NAVY|ROYAL|SKY|LIGHT|DARK|MED|MEDIUM)\b"#),
                                    ("address", #"(\d+\s+[A-Z\s]+(?:ST|STREET|AVE|AVENUE|RD|ROAD|DR|DRIVE|BLVD|BOULEVARD))"#),
            ("city_state_zip", #"([A-Z]+),\s+([A-Z]{2})\s+(\d{5}(?:-\d{4})?)"#),
            ("veteran", #"VETERAN"#),
            ("real_id", #"REAL ID"#)
        ]
        
        for (fieldName, pattern) in patterns {
            if let match = text.range(of: pattern, options: .regularExpression) {
                let fieldValue = String(text[match])
                fields[fieldName] = fieldValue
            }
        }
        
        return fields
    }
    
    private func reconstructTextFromFields(_ fieldData: [String: (value: String, confidence: Double, frequency: Int)]) -> String {
        // Reconstruct a comprehensive text from the best field data
        var reconstructedParts: [String] = []
        
        // Add fields in a logical order
        let fieldOrder = ["state", "name", "dob", "license", "class", "exp", "iss", "sex", "height", "weight", "eye_color", "address", "city_state_zip", "veteran", "real_id"]
        
        for fieldKey in fieldOrder {
            if let fieldInfo = fieldData[fieldKey] {
                reconstructedParts.append(fieldInfo.value)
            }
        }
        
        return reconstructedParts.joined(separator: " ")
    }
    
    private func calculateOverallQualityScore() -> Double {
        let qualityScores = frameAnalyses.map { analysis in
            switch analysis.imageQuality.overallQuality {
            case "Excellent": return 1.0
            case "Good": return 0.8
            case "Fair": return 0.6
            default: return 0.4
            }
        }
        
        return qualityScores.isEmpty ? 0.0 : qualityScores.reduce(0, +) / Double(qualityScores.count)
    }
    
    private func parseLicenseTextComprehensive(_ text: String) -> [String: String] {
        var fields: [String: String] = [:]
        
        // Extract name (THACHER ROBERT HAMILTON format)
        if let nameMatch = text.range(of: #"(\d+\s+)([A-Z]+\s+[A-Z]+\s+[A-Z]+)"#, options: .regularExpression) {
            let nameRange = text[nameMatch].range(of: #"[A-Z]+\s+[A-Z]+\s+[A-Z]+"#, options: .regularExpression)!
            let fullName = String(text[nameRange])
            let nameParts = fullName.components(separatedBy: " ")
            if nameParts.count >= 3 {
                let formattedName = convertAllCapsToProperCase("\(nameParts[0]) \(nameParts[1]) \(nameParts[2])")
                fields["Name"] = formattedName
            }
        } else if let nameMatch = text.range(of: #"([A-Z]+\s+[A-Z]+\s+[A-Z]+)"#, options: .regularExpression) {
            let fullName = String(text[nameMatch])
            let nameParts = fullName.components(separatedBy: " ")
            if nameParts.count >= 3 {
                let formattedName = convertAllCapsToProperCase("\(nameParts[0]) \(nameParts[1]) \(nameParts[2])")
                fields["Name"] = formattedName
            }
        }
        
        // Extract DOB
        if let dobMatch = text.range(of: #"DOB\s+(\d{1,2}/\d{1,2}/\d{4})"#, options: .regularExpression) {
            let dobRange = text[dobMatch].range(of: #"\d{1,2}/\d{1,2}/\d{4}"#, options: .regularExpression)!
            fields["Date of Birth"] = String(text[dobRange])
        }
        
        // Extract license number (C549417 format)
        if let licenseMatch = text.range(of: #"([A-Z]\d{6})"#, options: .regularExpression) {
            fields["Driver License Number"] = String(text[licenseMatch])
        } else if let licenseMatch = text.range(of: #"NO\s+([A-Z]\d{6})"#, options: .regularExpression) {
            let licenseRange = text[licenseMatch].range(of: #"[A-Z]\d{6}"#, options: .regularExpression)!
            fields["Driver License Number"] = String(text[licenseRange])
        }
        
        // Extract state from the beginning
        if let stateMatch = text.range(of: #"^([A-Z]+)\s+DRIVER\s+LICENSE"#, options: .regularExpression) {
            let stateRange = text[stateMatch].range(of: #"^[A-Z]+"#, options: .regularExpression)!
            let state = String(text[stateRange])
            let formattedState = convertAllCapsToProperCase(state)
            fields["State"] = formattedState
        }
        
        // Extract class
        if let classMatch = text.range(of: #"CLASS\s+([A-Z])"#, options: .regularExpression) {
            let classRange = text[classMatch].range(of: #"[A-Z]"#, options: .regularExpression)!
            fields["Class"] = String(text[classRange])
        }
        
        // Extract expiration date
        if let expMatch = text.range(of: #"EXP\s+(\d{1,2}/\d{1,2}/\d{4})"#, options: .regularExpression) {
            let expRange = text[expMatch].range(of: #"\d{1,2}/\d{1,2}/\d{4}"#, options: .regularExpression)!
            fields["Expiration Date"] = String(text[expRange])
        }
        
        // Extract issue date
        if let issMatch = text.range(of: #"ISS\s+(\d{1,2}/\d{1,2}/\d{4})"#, options: .regularExpression) {
            let issRange = text[issMatch].range(of: #"\d{1,2}/\d{1,2}/\d{4}"#, options: .regularExpression)!
            fields["Issue Date"] = String(text[issRange])
        }
        
        // Extract sex
        if let sexMatch = text.range(of: #"([MF])\d"#, options: .regularExpression) {
            let sexRange = text[sexMatch].range(of: #"[MF]"#, options: .regularExpression)!
            fields["Sex"] = text[sexRange] == "M" ? "Male" : "Female"
        } else if let sexMatch = text.range(of: #"SEX\s+([MF])"#, options: .regularExpression) {
            let sexRange = text[sexMatch].range(of: #"[MF]"#, options: .regularExpression)!
            fields["Sex"] = text[sexRange] == "M" ? "Male" : "Female"
        }
        
        // Extract height
        if let heightMatch = text.range(of: #"(\d{1,2})['\"]\s*[-]?\s*(\d{1,2})[\"]"#, options: .regularExpression) {
            let heightText = String(text[heightMatch])
            fields["Height"] = formatHeight(heightText)
        } else if let heightMatch = text.range(of: #"HGT\s+(\d{1,2}['\"]?\s*[-]?\s*\d{0,2}[\"]?)"#, options: .regularExpression) {
            let heightRange = text[heightMatch].range(of: #"\d{1,2}['\"]?\s*[-]?\s*\d{0,2}[\"]?"#, options: .regularExpression)!
            let heightText = String(text[heightRange])
            fields["Height"] = formatHeight(heightText)
        }
        
        // Extract weight
        if let weightMatch = text.range(of: #"(\d{3})lb"#, options: .regularExpression) {
            let weightRange = text[weightMatch].range(of: #"\d{3}"#, options: .regularExpression)!
            fields["Weight"] = "\(String(text[weightRange])) lbs"
        } else if let weightMatch = text.range(of: #"WGT\s+(\d{3})"#, options: .regularExpression) {
            let weightRange = text[weightMatch].range(of: #"\d{3}"#, options: .regularExpression)!
            fields["Weight"] = "\(String(text[weightRange])) lbs"
        }
        
        // Extract eye color
        if let eyeMatch = text.range(of: #"\b(BLU|BLUE|BRN|BROWN|GRN|GREEN|GRY|GRAY|HAZ|HAZEL|BLK|BLACK|AMB|AMBER|MUL|MULTI|PINK|PUR|PURPLE|YEL|YELLOW|WHI|WHITE|MAR|MARBLE|CHR|CHROME|GOL|GOLD|SIL|SILVER|COPPER|BURGUNDY|VIOLET|INDIGO|TEAL|TURQUOISE|AQUA|CYAN|LIME|OLIVE|NAVY|ROYAL|SKY|LIGHT|DARK|MED|MEDIUM)\b"#, options: .regularExpression) {
            let eyeColor = String(text[eyeMatch])
            let formattedEyeColor = convertAllCapsToProperCase(eyeColor)
            fields["Eye Color"] = formattedEyeColor
        } else if let eyeMatch = text.range(of: #"EYES\s+([A-Z]+)"#, options: .regularExpression) {
            let eyeRange = text[eyeMatch].range(of: #"[A-Z]+"#, options: .regularExpression)!
            let eyeColor = String(text[eyeRange])
            let formattedEyeColor = convertAllCapsToProperCase(eyeColor)
            fields["Eye Color"] = formattedEyeColor
        }
        
        // Extract veteran status
        if text.range(of: "VETERAN", options: .regularExpression) != nil {
            fields["Veteran Status"] = "Yes"
        }
        
        // Extract REAL ID indicator
        if text.range(of: "REAL ID", options: .regularExpression) != nil {
            fields["REAL ID"] = "Yes"
        }
        
        // Enhanced field extraction with additional patterns
        // Try alternative patterns for each field
        
        // Alternative name patterns
        if fields["Name"] == nil {
            if let nameMatch = text.range(of: #"([A-Z]+\s+[A-Z]+)"#, options: .regularExpression) {
                let fullName = String(text[nameMatch])
                let formattedName = convertAllCapsToProperCase(fullName)
                fields["Name"] = formattedName
            }
        }
        
        // Alternative DOB patterns
        if fields["Date of Birth"] == nil {
            if let dobMatch = text.range(of: #"(\d{1,2}/\d{1,2}/\d{4})"#, options: .regularExpression) {
                fields["Date of Birth"] = String(text[dobMatch])
            }
        }
        
        // Alternative license number patterns
        if fields["Driver License Number"] == nil {
            if let licenseMatch = text.range(of: #"([A-Z0-9]{6,8})"#, options: .regularExpression) {
                fields["Driver License Number"] = String(text[licenseMatch])
            }
        }
        
        // Alternative state patterns
        if fields["State"] == nil {
            if let stateMatch = text.range(of: #"([A-Z]{2})"#, options: .regularExpression) {
                let state = String(text[stateMatch])
                fields["State"] = state
            }
        }
        
        // Alternative class patterns
        if fields["Class"] == nil {
            if let classMatch = text.range(of: #"([A-Z])\s*CLASS"#, options: .regularExpression) {
                let classRange = text[classMatch].range(of: #"[A-Z]"#, options: .regularExpression)!
                fields["Class"] = String(text[classRange])
            }
        }
        
        // Alternative expiration date patterns
        if fields["Expiration Date"] == nil {
            if let expMatch = text.range(of: #"EXP\s*(\d{1,2}/\d{1,2}/\d{4})"#, options: .regularExpression) {
                let expRange = text[expMatch].range(of: #"\d{1,2}/\d{1,2}/\d{4}"#, options: .regularExpression)!
                fields["Expiration Date"] = String(text[expRange])
            }
        }
        
        // Alternative issue date patterns
        if fields["Issue Date"] == nil {
            if let issMatch = text.range(of: #"ISS\s*(\d{1,2}/\d{1,2}/\d{4})"#, options: .regularExpression) {
                let issRange = text[issMatch].range(of: #"\d{1,2}/\d{1,2}/\d{4}"#, options: .regularExpression)!
                fields["Issue Date"] = String(text[issRange])
            }
        }
        
        // Alternative sex patterns
        if fields["Sex"] == nil {
            if let sexMatch = text.range(of: #"([MF])\s*SEX"#, options: .regularExpression) {
                let sexRange = text[sexMatch].range(of: #"[MF]"#, options: .regularExpression)!
                fields["Sex"] = text[sexRange] == "M" ? "Male" : "Female"
            }
        }
        
        // Alternative height patterns
        if fields["Height"] == nil {
            if let heightMatch = text.range(of: #"(\d{1,2})['\"]"#, options: .regularExpression) {
                let heightText = String(text[heightMatch])
                fields["Height"] = formatHeight(heightText)
            }
        }
        
        // Alternative weight patterns
        if fields["Weight"] == nil {
            if let weightMatch = text.range(of: #"(\d{3})"#, options: .regularExpression) {
                let weightRange = text[weightMatch].range(of: #"\d{3}"#, options: .regularExpression)!
                fields["Weight"] = "\(String(text[weightRange])) lbs"
            }
        }
        
        // Alternative eye color patterns
        if fields["Eye Color"] == nil {
            if let eyeMatch = text.range(of: #"([A-Z]+)\s*EYES"#, options: .regularExpression) {
                let eyeRange = text[eyeMatch].range(of: #"[A-Z]+"#, options: .regularExpression)!
                let eyeColor = String(text[eyeRange])
                let formattedEyeColor = convertAllCapsToProperCase(eyeColor)
                fields["Eye Color"] = formattedEyeColor
            }
        }
        
        return fields
    }
    
    private func parseBarcodeDataComprehensive(_ barcodeData: String) -> [String: String] {
        var fields: [String: String] = [:]
        
        print("🔍 Parsing barcode data: \(barcodeData)")
        
        // Handle ANSI format barcode data
        if barcodeData.contains("ANSI") {
            print("📋 Detected ANSI format barcode")
            
            // First, extract license number from the end of ANSI data
            let lines = barcodeData.components(separatedBy: "\n")
            for line in lines {
                if line.contains("ANSI") && line.contains("DL") {
                    // Look for the license number at the end of the ANSI line
                    // Pattern: letter followed by numbers at the end
                    if let licenseMatch = line.range(of: #"([A-Z]\d+)$"#, options: .regularExpression) {
                        let license = String(line[licenseMatch])
                        fields["Driver License Number"] = license
                        print("   ✅ Found License from ANSI: \(fields["Driver License Number"]!)")
                        break // Stop after finding the first license number
                    }
                }
            }
            
            // Parse individual field codes
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedLine.count >= 3 {
                    let fieldCode = String(trimmedLine.prefix(3))
                    let fieldValue = String(trimmedLine.dropFirst(3))
                    
                    print("   Field \(fieldCode): '\(fieldValue)'")
                    
                    switch fieldCode {
                        case "DAC": fields["First Name"] = convertAllCapsToProperCase(fieldValue)
                        case "DAD": fields["Middle Name"] = convertAllCapsToProperCase(fieldValue)
                        case "DCS": fields["Last Name"] = convertAllCapsToProperCase(fieldValue)
                        case "DBB": fields["Date of Birth"] = formatDate(fieldValue)
                        case "DBA": fields["Expiration Date"] = formatDate(fieldValue)
                        case "DBC": fields["Sex"] = fieldValue == "1" ? "Male" : "Female"
                        case "DAU": 
                            if let inches = Int(fieldValue.replacingOccurrences(of: " in", with: "")) {
                                let feet = inches / 12
                                let remainingInches = inches % 12
                                if remainingInches == 0 {
                                    fields["Height"] = "\(feet)'"
                                } else {
                                    fields["Height"] = "\(feet)'\(remainingInches)\""
                                }
                            } else {
                                fields["Height"] = fieldValue
                            }
                        case "DAY": fields["Eye Color"] = convertAllCapsToProperCase(fieldValue)
                        case "DAZ": fields["Hair Color"] = convertAllCapsToProperCase(fieldValue)
                        case "DAW": fields["Weight"] = "\(fieldValue) lbs"
                        case "DAG": fields["Street Address"] = convertAllCapsToProperCase(fieldValue)
                        case "DAI": fields["City"] = convertAllCapsToProperCase(fieldValue)
                        case "DCA": 
                            // Skip DCA field as we already extracted license from ANSI header
                            if fields["Driver License Number"] == nil {
                                fields["License Number"] = fieldValue
                            }
                        case "DCD": fields["Class"] = fieldValue
                        case "DCF": fields["Restrictions"] = fieldValue
                        case "DCG": fields["Endorsements"] = fieldValue
                        case "DCH": fields["Issue Date"] = formatDate(fieldValue)
                        case "DCI": fields["State"] = fieldValue
                        case "DCJ": fields["Address"] = convertAllCapsToProperCase(fieldValue)
                        case "DCK": fields["City"] = convertAllCapsToProperCase(fieldValue)
                        case "DCL": fields["State"] = convertAllCapsToProperCase(fieldValue)
                        case "DCM": fields["ZIP Code"] = fieldValue
                        case "DAA": fields["Full Name"] = convertAllCapsToProperCase(fieldValue)
                        case "DAB": fields["Last Name"] = convertAllCapsToProperCase(fieldValue)
                        case "DAE": fields["Name Suffix"] = convertAllCapsToProperCase(fieldValue)
                        case "DAF": fields["Name Prefix"] = convertAllCapsToProperCase(fieldValue)
                        case "DAH": fields["Residence Address"] = convertAllCapsToProperCase(fieldValue)
                        case "DAJ": fields["State"] = convertAllCapsToProperCase(fieldValue)
                        case "DAK": fields["ZIP Code"] = fieldValue
                        case "DAL": fields["County"] = convertAllCapsToProperCase(fieldValue)
                        case "DAM": fields["Country"] = convertAllCapsToProperCase(fieldValue)
                        case "DAN": fields["Telephone"] = fieldValue
                        case "DAO": fields["Place of Birth"] = convertAllCapsToProperCase(fieldValue)
                        case "DAP": fields["Audit Information"] = fieldValue
                        case "DAQ": fields["Temporary Document Indicator"] = fieldValue
                        case "DAR": fields["Compliance Type"] = fieldValue
                        case "DAS": fields["Card Revision Date"] = formatDate(fieldValue)
                        case "DAT": fields["HAZMAT Endorsement Date"] = formatDate(fieldValue)
                        case "DAV": fields["Weight"] = "\(fieldValue) lbs"
                        case "DAX": fields["Race/Ethnicity"] = convertAllCapsToProperCase(fieldValue)
                        case "DBD": fields["Race/Ethnicity"] = convertAllCapsToProperCase(fieldValue)
                        case "DBE": fields["Audit Information"] = fieldValue
                        case "DBF": fields["Place of Birth"] = convertAllCapsToProperCase(fieldValue)
                        case "DBG": fields["Audit Information"] = fieldValue
                        case "DBH": fields["Organ Donor Indicator"] = fieldValue
                        case "DBI": fields["Veteran Indicator"] = fieldValue
                        case "DCB": fields["Document Discriminator"] = fieldValue
                        case "DCE": fields["Restrictions"] = fieldValue
                        case "DCN": fields["County"] = convertAllCapsToProperCase(fieldValue)
                        case "DCO": fields["Country"] = convertAllCapsToProperCase(fieldValue)
                        case "DCP": fields["Vehicle Class"] = fieldValue
                        case "DCQ": fields["Restrictions"] = fieldValue
                        case "DCR": fields["Endorsements"] = fieldValue
                        case "DCT": fields["First Name"] = convertAllCapsToProperCase(fieldValue)
                        case "DCU": fields["Middle Name"] = convertAllCapsToProperCase(fieldValue)
                        case "DCV": fields["Name Suffix"] = convertAllCapsToProperCase(fieldValue)
                        case "DCW": fields["Name Prefix"] = convertAllCapsToProperCase(fieldValue)
                        case "DCX": fields["Mailing Address"] = convertAllCapsToProperCase(fieldValue)
                        case "DCY": fields["Residence Address"] = convertAllCapsToProperCase(fieldValue)
                        case "DCZ": fields["City"] = convertAllCapsToProperCase(fieldValue)
                        default: 
                            if fieldValue.count > 2 && fieldValue != "NONE" && fieldValue != "UNK" && fieldValue != "N" {
                                let cleanFieldName = fieldCode.replacingOccurrences(of: "_", with: " ").capitalized
                                fields[cleanFieldName] = fieldValue
                            }
                    }
                }
            }
        } else if barcodeData.hasPrefix("^") {
            // AAMVA format
            print("📋 Detected AAMVA format barcode")
            let components = barcodeData.components(separatedBy: "$")
            for component in components {
                if component.count >= 3 {
                    let fieldCode = String(component.prefix(3))
                    let fieldValue = String(component.dropFirst(3))
                    
                    print("   Field \(fieldCode): '\(fieldValue)'")
                    
                    switch fieldCode {
                        case "DAC": fields["First Name"] = convertAllCapsToProperCase(fieldValue)
                        case "DCS": fields["Last Name"] = convertAllCapsToProperCase(fieldValue)
                        case "DAD": fields["Middle Name"] = convertAllCapsToProperCase(fieldValue)
                        case "DBB": fields["Date of Birth"] = formatDate(fieldValue)
                        case "DBA": fields["Expiration Date"] = formatDate(fieldValue)
                        case "DBC": fields["Sex"] = fieldValue == "1" ? "Male" : "Female"
                        case "DAU": 
                            if let inches = Int(fieldValue.replacingOccurrences(of: " in", with: "")) {
                                let feet = inches / 12
                                let remainingInches = inches % 12
                                if remainingInches == 0 {
                                    fields["Height"] = "\(feet)'"
                                } else {
                                    fields["Height"] = "\(feet)'\(remainingInches)\""
                                }
                            } else {
                                fields["Height"] = fieldValue
                            }
                        case "DAY": fields["Eye Color"] = convertAllCapsToProperCase(fieldValue)
                        case "DAZ": fields["Hair Color"] = convertAllCapsToProperCase(fieldValue)
                        case "DCA": 
                            if fieldValue.count >= 7 {
                                let cleanLicense = String(fieldValue.suffix(7))
                                fields["License Number"] = cleanLicense
                            } else {
                                fields["License Number"] = fieldValue
                            }
                        case "DCD": fields["Class"] = fieldValue
                        case "DCF": fields["Restrictions"] = fieldValue
                        case "DCG": fields["Endorsements"] = fieldValue
                        case "DCH": fields["Issue Date"] = formatDate(fieldValue)
                        case "DCI": fields["State"] = fieldValue
                        case "DCJ": fields["Address"] = convertAllCapsToProperCase(fieldValue)
                        case "DCK": fields["City"] = convertAllCapsToProperCase(fieldValue)
                        case "DCL": fields["State"] = convertAllCapsToProperCase(fieldValue)
                        case "DCM": fields["ZIP Code"] = fieldValue
                        case "DAG": fields["Street Address"] = convertAllCapsToProperCase(fieldValue)
                        case "DAI": fields["City"] = convertAllCapsToProperCase(fieldValue)
                        case "DAJ": fields["State"] = convertAllCapsToProperCase(fieldValue)
                        case "DAK": fields["ZIP Code"] = fieldValue
                        default: 
                            if fieldValue.count > 2 && fieldValue != "NONE" && fieldValue != "UNK" {
                                let cleanFieldName = fieldCode.replacingOccurrences(of: "_", with: " ").capitalized
                                fields[cleanFieldName] = fieldValue
                            }
                    }
                }
            }
        } else {
            // Try to parse as raw data with common patterns
            print("📋 Attempting to parse raw barcode data")
            parseRawBarcodeData(barcodeData, into: &fields)
            
            // Also try to parse embedded field codes (like DACROBERT, DADHAMILTON)
            parseEmbeddedFieldCodes(barcodeData, into: &fields)
            
            // Enhanced parsing for the specific format you provided
            parseEnhancedBarcodeFormat(barcodeData, into: &fields)
        }
        
        // Map barcode fields to required driver's license fields
        var mappedFields: [String: String] = [:]
        
        // Map name fields - try multiple name field combinations
        if let fullName = fields["Full Name"] {
            mappedFields["Name"] = fullName
        } else if let firstName = fields["First Name"], let lastName = fields["Last Name"] {
            let middleName = fields["Middle Name"] ?? ""
            if !middleName.isEmpty {
                mappedFields["Name"] = "\(firstName) \(middleName) \(lastName)"
            } else {
                mappedFields["Name"] = "\(firstName) \(lastName)"
            }
        } else if let firstName = fields["First Name"] {
            mappedFields["Name"] = firstName
        } else if let lastName = fields["Last Name"] {
            mappedFields["Name"] = lastName
        }
        
        // Map other fields directly
        if let dob = fields["Date of Birth"] {
            mappedFields["Date of Birth"] = dob
        }
        
        if let licenseNumber = fields["License Number"] {
            mappedFields["Driver License Number"] = licenseNumber
        }
        
        if let state = fields["State"] {
            mappedFields["State"] = state
        }
        
        if let licenseClass = fields["Class"] {
            mappedFields["Class"] = licenseClass
        }
        
        if let expiration = fields["Expiration Date"] {
            mappedFields["Expiration Date"] = expiration
        }
        
        if let issue = fields["Issue Date"] {
            mappedFields["Issue Date"] = issue
        }
        
        if let sex = fields["Sex"] {
            mappedFields["Sex"] = sex
        }
        
        if let height = fields["Height"] {
            mappedFields["Height"] = height
        }
        
        if let weight = fields["Weight"] {
            mappedFields["Weight"] = weight
        }
        
        if let eyeColor = fields["Eye Color"] {
            mappedFields["Eye Color"] = eyeColor
        }
        
        // Add additional fields that might be useful
        if let address = fields["Address"] ?? fields["Street Address"] ?? fields["Mailing Address"] ?? fields["Residence Address"] {
            mappedFields["Address"] = address
        }
        
        if let city = fields["City"] {
            mappedFields["City"] = city
        }
        
        if let zipCode = fields["ZIP Code"] {
            mappedFields["ZIP Code"] = zipCode
        }
        
        if let restrictions = fields["Restrictions"] {
            mappedFields["Restrictions"] = restrictions
        }
        
        if let endorsements = fields["Endorsements"] {
            mappedFields["Endorsements"] = endorsements
        }
        
        // Handle veteran status
        if let veteranIndicator = fields["Veteran Indicator"] {
            mappedFields["Veteran Status"] = veteranIndicator == "1" ? "Yes" : "No"
        }
        
        // Add all other fields from the barcode data
        for (key, value) in fields {
            if !mappedFields.keys.contains(key) && value.count > 0 && value != "NONE" && value != "UNK" && value != "N" {
                mappedFields[key] = value
            }
        }
        
        print("📊 Mapped barcode fields:")
        for (key, value) in mappedFields {
            print("   \(key): '\(value)'")
        }
        
        return mappedFields
    }
    
    private func parseEnhancedBarcodeFormat(_ barcodeData: String, into fields: inout [String: String]) {
        print("🔍 Enhanced barcode parsing for format: \(barcodeData)")
        
        // Split by newlines and process each line
        let lines = barcodeData.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty { continue }
            
            // Look for 3-letter field codes followed by data
            if trimmedLine.count >= 3 {
                let fieldCode = String(trimmedLine.prefix(3))
                let fieldValue = String(trimmedLine.dropFirst(3))
                
                print("   Enhanced parsing - Field \(fieldCode): '\(fieldValue)'")
                
                switch fieldCode {
                    case "DAC": 
                        if fields["First Name"] == nil {
                            fields["First Name"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DAD": 
                        if fields["Middle Name"] == nil {
                            fields["Middle Name"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DCS": 
                        if fields["Last Name"] == nil {
                            fields["Last Name"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DCU": 
                        if fields["Middle Name"] == nil {
                            fields["Middle Name"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DCA": 
                        if fields["License Number"] == nil {
                            fields["License Number"] = fieldValue
                        }
                    case "DBB": 
                        if fields["Date of Birth"] == nil {
                            fields["Date of Birth"] = formatDate(fieldValue)
                        }
                    case "DBA": 
                        if fields["Expiration Date"] == nil {
                            fields["Expiration Date"] = formatDate(fieldValue)
                        }
                    case "DBD": 
                        if fields["Issue Date"] == nil {
                            fields["Issue Date"] = formatDate(fieldValue)
                        }
                    case "DBC": 
                        if fields["Sex"] == nil {
                            fields["Sex"] = fieldValue == "1" ? "Male" : "Female"
                        }
                    case "DAU": 
                        if fields["Height"] == nil {
                            if let inches = Int(fieldValue.replacingOccurrences(of: " in", with: "")) {
                                let feet = inches / 12
                                let remainingInches = inches % 12
                                if remainingInches == 0 {
                                    fields["Height"] = "\(feet)'"
                                } else {
                                    fields["Height"] = "\(feet)'\(remainingInches)\""
                                }
                            } else {
                                fields["Height"] = fieldValue
                            }
                        }
                    case "DAY": 
                        if fields["Eye Color"] == nil {
                            fields["Eye Color"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DAZ": 
                        if fields["Hair Color"] == nil {
                            fields["Hair Color"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DAW": 
                        if fields["Weight"] == nil {
                            fields["Weight"] = "\(fieldValue) lbs"
                        }
                    case "DAG": 
                        if fields["Street Address"] == nil {
                            fields["Street Address"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DAI": 
                        if fields["City"] == nil {
                            fields["City"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DAJ": 
                        if fields["State"] == nil {
                            fields["State"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DAK": 
                        if fields["ZIP Code"] == nil {
                            fields["ZIP Code"] = fieldValue
                        }
                    case "DCD": 
                        if fields["Class"] == nil {
                            fields["Class"] = fieldValue
                        }
                    case "DCF": 
                        if fields["Restrictions"] == nil {
                            fields["Restrictions"] = fieldValue
                        }
                    case "DCG": 
                        if fields["Endorsements"] == nil {
                            fields["Endorsements"] = fieldValue
                        }
                    case "DCH": 
                        if fields["Issue Date"] == nil {
                            fields["Issue Date"] = formatDate(fieldValue)
                        }
                    case "DCI": 
                        if fields["State"] == nil {
                            fields["State"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DCJ": 
                        if fields["Address"] == nil {
                            fields["Address"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DCK": 
                        if fields["City"] == nil {
                            fields["City"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DCL": 
                        if fields["State"] == nil {
                            fields["State"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DCM": 
                        if fields["ZIP Code"] == nil {
                            fields["ZIP Code"] = fieldValue
                        }
                    case "DAA": 
                        if fields["Full Name"] == nil {
                            fields["Full Name"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DAB": 
                        if fields["Last Name"] == nil {
                            fields["Last Name"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DAE": 
                        if fields["Name Suffix"] == nil {
                            fields["Name Suffix"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DAF": 
                        if fields["Name Prefix"] == nil {
                            fields["Name Prefix"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DAH": 
                        if fields["Residence Address"] == nil {
                            fields["Residence Address"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DAL": 
                        if fields["County"] == nil {
                            fields["County"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DAM": 
                        if fields["Country"] == nil {
                            fields["Country"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DAN": 
                        if fields["Telephone"] == nil {
                            fields["Telephone"] = fieldValue
                        }
                    case "DAO": 
                        if fields["Place of Birth"] == nil {
                            fields["Place of Birth"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DAP": 
                        if fields["Audit Information"] == nil {
                            fields["Audit Information"] = fieldValue
                        }
                    case "DAQ": 
                        if fields["Temporary Document Indicator"] == nil {
                            fields["Temporary Document Indicator"] = fieldValue
                        }
                    case "DAR": 
                        if fields["Compliance Type"] == nil {
                            fields["Compliance Type"] = fieldValue
                        }
                    case "DAS": 
                        if fields["Card Revision Date"] == nil {
                            fields["Card Revision Date"] = formatDate(fieldValue)
                        }
                    case "DAT": 
                        if fields["HAZMAT Endorsement Date"] == nil {
                            fields["HAZMAT Endorsement Date"] = formatDate(fieldValue)
                        }
                    case "DAV": 
                        if fields["Weight"] == nil {
                            fields["Weight"] = "\(fieldValue) lbs"
                        }
                    case "DAX": 
                        if fields["Race/Ethnicity"] == nil {
                            fields["Race/Ethnicity"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DBE": 
                        if fields["Audit Information"] == nil {
                            fields["Audit Information"] = fieldValue
                        }
                    case "DBF": 
                        if fields["Place of Birth"] == nil {
                            fields["Place of Birth"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DBG": 
                        if fields["Audit Information"] == nil {
                            fields["Audit Information"] = fieldValue
                        }
                    case "DBH": 
                        if fields["Organ Donor Indicator"] == nil {
                            fields["Organ Donor Indicator"] = fieldValue
                        }
                    case "DBI": 
                        if fields["Veteran Indicator"] == nil {
                            fields["Veteran Indicator"] = fieldValue
                        }
                    case "DCB": 
                        if fields["Document Discriminator"] == nil {
                            fields["Document Discriminator"] = fieldValue
                        }
                    case "DCE": 
                        if fields["Restrictions"] == nil {
                            fields["Restrictions"] = fieldValue
                        }
                    case "DCN": 
                        if fields["County"] == nil {
                            fields["County"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DCO": 
                        if fields["Country"] == nil {
                            fields["Country"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DCP": 
                        if fields["Vehicle Class"] == nil {
                            fields["Vehicle Class"] = fieldValue
                        }
                    case "DCQ": 
                        if fields["Restrictions"] == nil {
                            fields["Restrictions"] = fieldValue
                        }
                    case "DCR": 
                        if fields["Endorsements"] == nil {
                            fields["Endorsements"] = fieldValue
                        }
                    case "DCT": 
                        if fields["First Name"] == nil {
                            fields["First Name"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DCV": 
                        if fields["Name Suffix"] == nil {
                            fields["Name Suffix"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DCW": 
                        if fields["Name Prefix"] == nil {
                            fields["Name Prefix"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DCX": 
                        if fields["Mailing Address"] == nil {
                            fields["Mailing Address"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DCY": 
                        if fields["Residence Address"] == nil {
                            fields["Residence Address"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DCZ": 
                        if fields["City"] == nil {
                            fields["City"] = convertAllCapsToProperCase(fieldValue)
                        }
                    case "DDA": 
                        if fields["Audit Information"] == nil {
                            fields["Audit Information"] = fieldValue
                        }
                    case "DDB": 
                        if fields["Audit Information"] == nil {
                            fields["Audit Information"] = fieldValue
                        }
                    case "DDC": 
                        if fields["Audit Information"] == nil {
                            fields["Audit Information"] = fieldValue
                        }
                    case "DDD": 
                        if fields["Audit Information"] == nil {
                            fields["Audit Information"] = fieldValue
                        }
                    case "DDE": 
                        if fields["Audit Information"] == nil {
                            fields["Audit Information"] = fieldValue
                        }
                    case "DDF": 
                        if fields["Audit Information"] == nil {
                            fields["Audit Information"] = fieldValue
                        }
                    case "DDG": 
                        if fields["Audit Information"] == nil {
                            fields["Audit Information"] = fieldValue
                        }
                    case "DDH": 
                        if fields["Audit Information"] == nil {
                            fields["Audit Information"] = fieldValue
                        }
                    case "DDI": 
                        if fields["Audit Information"] == nil {
                            fields["Audit Information"] = fieldValue
                        }
                    case "DDJ": 
                        if fields["Audit Information"] == nil {
                            fields["Audit Information"] = fieldValue
                        }
                    case "DDK": 
                        if fields["Audit Information"] == nil {
                            fields["Audit Information"] = fieldValue
                        }
                    case "DDL": 
                        if fields["Audit Information"] == nil {
                            fields["Audit Information"] = fieldValue
                        }
                    default:
                        // If it's a 3-letter code but not recognized, still try to extract it
                        if fieldValue.count > 2 && fieldValue != "NONE" && fieldValue != "UNK" && fieldValue != "N" {
                            let cleanFieldName = fieldCode.replacingOccurrences(of: "_", with: " ").capitalized
                            if fields[cleanFieldName] == nil {
                                fields[cleanFieldName] = convertAllCapsToProperCase(fieldValue)
                            }
                        }
                }
            }
        }
    }
    
    private func parseEmbeddedFieldCodes(_ barcodeData: String, into fields: inout [String: String]) {
        print("🔍 Parsing embedded field codes in: \(barcodeData)")
        
        // Split by common delimiters and look for embedded field codes
        let possibleDelimiters = ["\n", "\r", " ", "$", "^", "|"]
        
        // Try different delimiters
        for delimiter in possibleDelimiters {
            let components = barcodeData.components(separatedBy: delimiter)
            for component in components {
                let trimmedComponent = component.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedComponent.isEmpty { continue }
                
                // Look for embedded field codes (3-letter codes followed by data)
                if trimmedComponent.count >= 6 {
                    let fieldCode = String(trimmedComponent.prefix(3))
                    let fieldValue = String(trimmedComponent.dropFirst(3))
                    
                    print("   Found embedded field: \(fieldCode) = '\(fieldValue)'")
                    
                    switch fieldCode {
                        case "DAC": 
                            if fields["First Name"] == nil {
                                fields["First Name"] = convertAllCapsToProperCase(fieldValue)
                            }
                        case "DAD": 
                            if fields["Middle Name"] == nil {
                                fields["Middle Name"] = convertAllCapsToProperCase(fieldValue)
                            }
                        case "DCS": 
                            if fields["Last Name"] == nil {
                                fields["Last Name"] = convertAllCapsToProperCase(fieldValue)
                            }
                        case "DCA": 
                            if fields["License Number"] == nil {
                                fields["License Number"] = fieldValue
                            }
                        case "DBB": 
                            if fields["Date of Birth"] == nil {
                                fields["Date of Birth"] = formatDate(fieldValue)
                            }
                        case "DBA": 
                            if fields["Expiration Date"] == nil {
                                fields["Expiration Date"] = formatDate(fieldValue)
                            }
                        case "DBC": 
                            if fields["Sex"] == nil {
                                fields["Sex"] = fieldValue == "1" ? "Male" : "Female"
                            }
                        case "DAU": 
                            if fields["Height"] == nil {
                                if let inches = Int(fieldValue.replacingOccurrences(of: " in", with: "")) {
                                    let feet = inches / 12
                                    let remainingInches = inches % 12
                                    if remainingInches == 0 {
                                        fields["Height"] = "\(feet)'"
                                    } else {
                                        fields["Height"] = "\(feet)'\(remainingInches)\""
                                    }
                                } else {
                                    fields["Height"] = fieldValue
                                }
                            }
                        case "DAY": 
                            if fields["Eye Color"] == nil {
                                fields["Eye Color"] = convertAllCapsToProperCase(fieldValue)
                            }
                        case "DAZ": 
                            if fields["Hair Color"] == nil {
                                fields["Hair Color"] = convertAllCapsToProperCase(fieldValue)
                            }
                        case "DAW": 
                            if fields["Weight"] == nil {
                                fields["Weight"] = "\(fieldValue) lbs"
                            }
                        case "DAG": 
                            if fields["Street Address"] == nil {
                                fields["Street Address"] = convertAllCapsToProperCase(fieldValue)
                            }
                        case "DAI": 
                            if fields["City"] == nil {
                                fields["City"] = convertAllCapsToProperCase(fieldValue)
                            }
                        case "DCD": 
                            if fields["Class"] == nil {
                                fields["Class"] = fieldValue
                            }
                        case "DCF": 
                            if fields["Restrictions"] == nil {
                                fields["Restrictions"] = fieldValue
                            }
                        case "DCG": 
                            if fields["Endorsements"] == nil {
                                fields["Endorsements"] = fieldValue
                            }
                        case "DCH": 
                            if fields["Issue Date"] == nil {
                                fields["Issue Date"] = formatDate(fieldValue)
                            }
                        case "DCI": 
                            if fields["State"] == nil {
                                fields["State"] = fieldValue
                            }
                        case "DCJ": 
                            if fields["Address"] == nil {
                                fields["Address"] = convertAllCapsToProperCase(fieldValue)
                            }
                        case "DCK": 
                            if fields["City"] == nil {
                                fields["City"] = convertAllCapsToProperCase(fieldValue)
                            }
                        case "DCL": 
                            if fields["State"] == nil {
                                fields["State"] = convertAllCapsToProperCase(fieldValue)
                            }
                        case "DCM": 
                            if fields["ZIP Code"] == nil {
                                fields["ZIP Code"] = fieldValue
                            }
                        default:
                            // If it's a 3-letter code but not recognized, still try to extract it
                            if fieldValue.count > 2 && fieldValue != "NONE" && fieldValue != "UNK" && fieldValue != "N" {
                                let cleanFieldName = fieldCode.replacingOccurrences(of: "_", with: " ").capitalized
                                if fields[cleanFieldName] == nil {
                                    fields[cleanFieldName] = convertAllCapsToProperCase(fieldValue)
                                }
                            }
                    }
                }
            }
        }
        
        // Also try to find field codes in the entire string without delimiters
        let fieldCodePatterns = [
            ("DAC", "First Name"),
            ("DAD", "Middle Name"), 
            ("DCS", "Last Name"),
            ("DCA", "License Number"),
            ("DBB", "Date of Birth"),
            ("DBA", "Expiration Date"),
            ("DBC", "Sex"),
            ("DAU", "Height"),
            ("DAY", "Eye Color"),
            ("DAZ", "Hair Color"),
            ("DAW", "Weight"),
            ("DAG", "Street Address"),
            ("DAI", "City"),
            ("DCD", "Class"),
            ("DCF", "Restrictions"),
            ("DCG", "Endorsements"),
            ("DCH", "Issue Date"),
            ("DCI", "State"),
            ("DCJ", "Address"),
            ("DCL", "State"),
            ("DCM", "ZIP Code")
        ]
        
        for (fieldCode, fieldName) in fieldCodePatterns {
            if fields[fieldName] == nil {
                let pattern = "\(fieldCode)([A-Z0-9]+)"
                if let match = barcodeData.range(of: pattern, options: .regularExpression) {
                    let fieldValue = String(barcodeData[match].dropFirst(3))
                    print("   Found pattern match: \(fieldCode) = '\(fieldValue)'")
                    
                    switch fieldCode {
                        case "DAC": fields["First Name"] = convertAllCapsToProperCase(fieldValue)
                        case "DAD": fields["Middle Name"] = convertAllCapsToProperCase(fieldValue)
                        case "DCS": fields["Last Name"] = convertAllCapsToProperCase(fieldValue)
                        case "DCA": fields["License Number"] = fieldValue
                        case "DBB": fields["Date of Birth"] = formatDate(fieldValue)
                        case "DBA": fields["Expiration Date"] = formatDate(fieldValue)
                        case "DBC": fields["Sex"] = fieldValue == "1" ? "Male" : "Female"
                        case "DAU": 
                            if let inches = Int(fieldValue.replacingOccurrences(of: " in", with: "")) {
                                let feet = inches / 12
                                let remainingInches = inches % 12
                                if remainingInches == 0 {
                                    fields["Height"] = "\(feet)'"
                                } else {
                                    fields["Height"] = "\(feet)'\(remainingInches)\""
                                }
                            } else {
                                fields["Height"] = fieldValue
                            }
                        case "DAY": fields["Eye Color"] = convertAllCapsToProperCase(fieldValue)
                        case "DAZ": fields["Hair Color"] = convertAllCapsToProperCase(fieldValue)
                        case "DAW": fields["Weight"] = "\(fieldValue) lbs"
                        case "DAG": fields["Street Address"] = convertAllCapsToProperCase(fieldValue)
                        case "DAI": fields["City"] = convertAllCapsToProperCase(fieldValue)
                        case "DCD": fields["Class"] = fieldValue
                        case "DCF": fields["Restrictions"] = fieldValue
                        case "DCG": fields["Endorsements"] = fieldValue
                        case "DCH": fields["Issue Date"] = formatDate(fieldValue)
                        case "DCI": fields["State"] = fieldValue
                        case "DCJ": fields["Address"] = convertAllCapsToProperCase(fieldValue)
                        case "DCK": fields["City"] = convertAllCapsToProperCase(fieldValue)
                        case "DCL": fields["State"] = convertAllCapsToProperCase(fieldValue)
                        case "DCM": fields["ZIP Code"] = fieldValue
                        default: break
                    }
                }
            }
        }
    }
    
    private func parseRawBarcodeData(_ barcodeData: String, into fields: inout [String: String]) {
        // Try to extract common patterns from raw barcode data
        let lines = barcodeData.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty { continue }
            
            // Try to match common field patterns
            if let nameMatch = trimmedLine.range(of: #"([A-Z]+\s+[A-Z]+\s+[A-Z]+)"#, options: .regularExpression) {
                fields["Name"] = convertAllCapsToProperCase(String(trimmedLine[nameMatch]))
            }
            
            if let dobMatch = trimmedLine.range(of: #"(\d{1,2}/\d{1,2}/\d{4})"#, options: .regularExpression) {
                fields["Date of Birth"] = String(trimmedLine[dobMatch])
            }
            
            if let licenseMatch = trimmedLine.range(of: #"([A-Z]\d{6,})"#, options: .regularExpression) {
                fields["License Number"] = String(trimmedLine[licenseMatch])
            }
            
            if let stateMatch = trimmedLine.range(of: #"^([A-Z]{2})"#, options: .regularExpression) {
                fields["State"] = String(trimmedLine[stateMatch])
            }
            
            if let classMatch = trimmedLine.range(of: #"CLASS\s+([A-Z])"#, options: .regularExpression) {
                let classRange = trimmedLine[classMatch].range(of: #"[A-Z]"#, options: .regularExpression)!
                fields["Class"] = String(trimmedLine[classRange])
            }
            
            if let expMatch = trimmedLine.range(of: #"EXP\s+(\d{1,2}/\d{1,2}/\d{4})"#, options: .regularExpression) {
                let expRange = trimmedLine[expMatch].range(of: #"\d{1,2}/\d{1,2}/\d{4}"#, options: .regularExpression)!
                fields["Expiration Date"] = String(trimmedLine[expRange])
            }
            
            if let issMatch = trimmedLine.range(of: #"ISS\s+(\d{1,2}/\d{1,2}/\d{4})"#, options: .regularExpression) {
                let issRange = trimmedLine[issMatch].range(of: #"\d{1,2}/\d{1,2}/\d{4}"#, options: .regularExpression)!
                fields["Issue Date"] = String(trimmedLine[issRange])
            }
            
            if let sexMatch = trimmedLine.range(of: #"([MF])\d"#, options: .regularExpression) {
                let sexRange = trimmedLine[sexMatch].range(of: #"[MF]"#, options: .regularExpression)!
                fields["Sex"] = trimmedLine[sexRange] == "M" ? "Male" : "Female"
            }
            
            if let heightMatch = trimmedLine.range(of: #"(\d{1,2})['\"]\s*[-]?\s*(\d{1,2})[\"]"#, options: .regularExpression) {
                let heightText = String(trimmedLine[heightMatch])
                fields["Height"] = formatHeight(heightText)
            }
            
            if let weightMatch = trimmedLine.range(of: #"(\d{3})lb"#, options: .regularExpression) {
                let weightRange = trimmedLine[weightMatch].range(of: #"\d{3}"#, options: .regularExpression)!
                fields["Weight"] = "\(String(trimmedLine[weightRange])) lbs"
            }
            
            if let eyeMatch = trimmedLine.range(of: #"\b(BLU|BLUE|BRN|BROWN|GRN|GREEN|GRY|GRAY|HAZ|HAZEL|BLK|BLACK|AMB|AMBER|MUL|MULTI|PINK|PUR|PURPLE|YEL|YELLOW|WHI|WHITE|MAR|MARBLE|CHR|CHROME|GOL|GOLD|SIL|SILVER|COPPER|BURGUNDY|VIOLET|INDIGO|TEAL|TURQUOISE|AQUA|CYAN|LIME|OLIVE|NAVY|ROYAL|SKY|LIGHT|DARK|MED|MEDIUM)\b"#, options: .regularExpression) {
                let eyeColor = String(trimmedLine[eyeMatch])
                fields["Eye Color"] = convertAllCapsToProperCase(eyeColor)
            }
        }
    }
    
    private func convertAllCapsToProperCase(_ text: String) -> String {
        let words = text.components(separatedBy: " ")
        let isAllCaps = words.allSatisfy { word in
            let cleanWord = word.trimmingCharacters(in: .punctuationCharacters)
            return cleanWord.isEmpty || 
                   cleanWord.count <= 2 || 
                   cleanWord.range(of: #"^\d+$"#, options: .regularExpression) != nil ||
                   cleanWord.range(of: #"^[A-Z]{2,}$"#, options: .regularExpression) != nil
        }
        
        if isAllCaps {
            return text.capitalized
        }
        return text
    }
    
    private func formatHeight(_ heightText: String) -> String {
        let cleanHeight = heightText.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
        
        if let dashRange = cleanHeight.range(of: "-") {
            let feet = String(cleanHeight[..<dashRange.lowerBound])
            let inches = String(cleanHeight[dashRange.upperBound...])
            
            if let feetInt = Int(feet), let inchesInt = Int(inches) {
                let totalInches = feetInt * 12 + inchesInt
                return "\(feetInt)'\(inchesInt)\" (\(totalInches)\")"
            }
        }
        
        if let inches = Int(cleanHeight) {
            if inches > 12 {
                let feet = inches / 12
                let remainingInches = inches % 12
                if remainingInches == 0 {
                    return "\(feet)' (\(inches)\")"
                } else {
                    return "\(feet)'\(remainingInches)\" (\(inches)\")"
                }
            } else {
                return "\(inches)\""
            }
        }
        
        return heightText
    }
    
    private func formatDate(_ dateString: String) -> String {
        if dateString.count == 8 && dateString.range(of: "^\\d{8}$", options: .regularExpression) != nil {
            let month = String(dateString.prefix(2))
            let day = String(dateString.dropFirst(2).prefix(2))
            let year = String(dateString.dropFirst(4))
            return "\(month)/\(day)/\(year)"
        }
        return dateString
    }
    
    private func parseLicenseText(_ text: String) -> [String: String] {
        // Simplified parsing - this would be enhanced based on your specific needs
        var fields: [String: String] = [:]
        
        // Extract name pattern
        if let nameMatch = text.range(of: #"([A-Z]+\s+[A-Z]+\s+[A-Z]+)"#, options: .regularExpression) {
            fields["Name"] = String(text[nameMatch])
        }
        
        // Extract DOB
        if let dobMatch = text.range(of: #"(\d{1,2}/\d{1,2}/\d{4})"#, options: .regularExpression) {
            fields["Date of Birth"] = String(text[dobMatch])
        }
        
        // Extract license number
        if let licenseMatch = text.range(of: #"([A-Z]\d{6,})"#, options: .regularExpression) {
            fields["License Number"] = String(text[licenseMatch])
        }
        
        return fields
    }
    
    private func calculateFieldProgress(_ extractedFields: [String: String]) -> FieldProgress {
        var capturedFields: [String: String] = [:]
        var missingFields: [String] = []
        var fieldStatuses: [String: FieldStatus] = [:]
        
        // Determine if this is front or back side based on the fields present
        let hasBarcodeFields = extractedFields.keys.contains { key in
            ["License Number", "First Name", "Last Name", "Full Name"].contains(key)
        }
        
        let requiredFields: [String]
        if hasBarcodeFields {
            // Back side (barcode) - focus on key identification fields
            requiredFields = [
                "Name", "Date of Birth", "Driver License Number", "State", 
                "Class", "Expiration Date", "Issue Date", "Sex", "Height", 
                "Eye Color", "Address", "City", "ZIP Code"
            ]
        } else {
            // Front side (OCR) - all standard fields
            requiredFields = [
                "Name", "Date of Birth", "Driver License Number", "State", 
                "Class", "Expiration Date", "Issue Date", "Sex", "Height", 
                "Weight", "Eye Color"
            ]
        }
        
        for field in requiredFields {
            if let value = extractedFields[field], !value.isEmpty {
                capturedFields[field] = value
                
                // Determine field status based on completeness
                if value.count > 10 {
                    fieldStatuses[field] = .excellent
                } else if value.count > 5 {
                    fieldStatuses[field] = .complete
                } else if value.count > 2 {
                    fieldStatuses[field] = .partial
                } else {
                    fieldStatuses[field] = .notFound
                }
            } else {
                capturedFields[field] = ""
                missingFields.append(field)
                fieldStatuses[field] = .notFound
            }
        }
        
        let progressPercentage = Double(requiredFields.count - missingFields.count) / Double(requiredFields.count) * 100
        let isComplete = missingFields.isEmpty || progressPercentage >= 85 // Allow 85% completion
        
        print("📊 Field Progress Analysis:")
        print("   Side: \(hasBarcodeFields ? "Back (Barcode)" : "Front (OCR)")")
        print("   Required Fields: \(requiredFields.count)")
        print("   Captured Fields: \(capturedFields.count - missingFields.count)")
        print("   Missing Fields: \(missingFields.count)")
        print("   Progress: \(String(format: "%.1f", progressPercentage))%")
        print("   Is Complete: \(isComplete)")
        
        return FieldProgress(
            requiredFields: requiredFields,
            capturedFields: capturedFields,
            missingFields: missingFields,
            progressPercentage: progressPercentage,
            isComplete: isComplete,
            fieldStatuses: fieldStatuses
        )
    }
}

// MARK: - License Side Enum

enum LicenseSide {
    case front
    case back
}

// MARK: - VideoBasedScanner Delegate Extension

extension VideoBasedScanner: VideoFrameProcessorDelegate {
    func frameProcessor(_ processor: VideoFrameProcessor, didUpdateQuality quality: QualityFeedback) {
        DispatchQueue.main.async {
            self.qualityFeedback = quality
        }
    }
    
    func frameProcessor(_ processor: VideoFrameProcessor, didCompleteScan results: VideoScanResults) {
        DispatchQueue.main.async {
            self.scanResults = results
            self.isScanning = false
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension VideoBasedScanner: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Convert to UIImage with proper orientation
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        // Create UIImage with proper orientation
        let frame = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
        
        // Apply image processing for better display
        let processedFrame = processFrameForDisplay(frame)
        
        // Update current frame for preview
        DispatchQueue.main.async {
            self.currentFrame = processedFrame
        }
        
        // Send processed frame to processor for analysis
        frameProcessor?.addCapturedFrame(processedFrame)
    }
    
    private func processFrameForDisplay(_ frame: UIImage) -> UIImage {
        // Apply the same processing as static images for consistency
        return ContentView.processImageForDisplay(frame)
    }
}

// MARK: - VideoFrameProcessor Delegate Protocol

protocol VideoFrameProcessorDelegate: AnyObject {
    func frameProcessor(_ processor: VideoFrameProcessor, didUpdateQuality quality: VideoBasedScanner.QualityFeedback)
    func frameProcessor(_ processor: VideoFrameProcessor, didCompleteScan results: VideoScanResults)
}
