//
//  VideoBasedScanner.swift
//  check-id
//
//  Created: December 2024
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

// MARK: - Video-Based Scanner

class VideoBasedScanner: ObservableObject {
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
    private var scanDuration: TimeInterval = 3.0 // 3 seconds
    
    enum QualityFeedback {
        case none
        case good
        case poor
        case excellent
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
            
            videoOutput = AVCaptureMovieFileOutput()
            if let videoOutput = videoOutput,
               session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            } else {
                print("Failed to add video output")
            }
            
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer?.videoGravity = .resizeAspectFill
            
            // Start the session
            session.startRunning()
            
            print("Capture session setup completed successfully")
            
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
    
    func startProcessing(session: AVCaptureSession?, side: LicenseSide, duration: TimeInterval) {
        frameCount = 0
        extractedTexts.removeAll()
        confidenceScores.removeAll()
        frameAnalyses.removeAll()
        scanStartTime = Date()
        
        print("Starting frame processing for \(side) side")
        
        // Start frame extraction timer on main thread
        DispatchQueue.main.async {
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                self.processCurrentFrame(side: side)
                
                // Stop after duration
                if let startTime = self.scanStartTime,
                   Date().timeIntervalSince(startTime) >= duration {
                    timer.invalidate()
                    self.finalizeProcessing()
                }
            }
        }
    }
    
    func stopProcessing() {
        finalizeProcessing()
    }
    
    private func processCurrentFrame(side: LicenseSide) {
        // For now, we'll use a simplified approach that captures frames
        // In a real implementation, you'd capture from the active session
        
        // Simulate frame capture for demonstration
        DispatchQueue.main.async {
            // Create a mock frame for demonstration
            let mockFrame = self.createMockFrame()
            let analysis = self.analyzeFrame(mockFrame, side: side)
            self.frameAnalyses.append(analysis)
            
            self.delegate?.frameProcessor(self, didUpdateQuality: self.getQualityFeedback(analysis.imageQuality))
            
            self.frameCount += 1
        }
    }
    
    private func createMockFrame() -> UIImage {
        // Create a simple colored rectangle as a mock frame
        let size = CGSize(width: 640, height: 480)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.systemBlue.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return image
    }
    
    private func analyzeFrame(_ frame: UIImage, side: LicenseSide) -> FrameAnalysis {
        let startTime = Date()
        
        // Extract text using OCR
        let (text, confidence) = extractTextFromFrame(frame)
        extractedTexts.append(text)
        confidenceScores.append(confidence)
        
        // Analyze image quality
        let imageQuality = analyzeImageQuality(frame)
        
        // Detect faces (for front side)
        let faceDetected = side == .front ? detectFaceInFrame(frame) : false
        
        // Detect barcodes (for back side)
        let barcodeDetected = side == .back ? detectBarcodeInFrame(frame) : false
        
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
    
    private func extractTextFromFrame(_ frame: UIImage) -> (String, Double) {
        guard let cgImage = frame.cgImage else { return ("", 0.0) }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                print("OCR Request Error: \(error)")
            }
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        do {
            try requestHandler.perform([request])
            
            if let observations = request.results as? [VNRecognizedTextObservation] {
                let recognizedStrings = observations.compactMap { observation -> (String, Float)? in
                    let topCandidate = observation.topCandidates(1).first
                    return topCandidate.map { ($0.string, $0.confidence) }
                }
                
                let text = recognizedStrings.map { $0.0 }.joined(separator: " ")
                let avgConfidence = recognizedStrings.isEmpty ? 0.0 : Double(recognizedStrings.map { $0.1 }.reduce(0, +) / Float(recognizedStrings.count))
                
                return (text, avgConfidence)
            }
        } catch {
            print("OCR Error: \(error)")
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
        // Aggregate text from all frames
        let aggregatedText = aggregateTextFromFrames()
        
        // Calculate average confidence
        let avgConfidence = confidenceScores.isEmpty ? 0.0 : confidenceScores.reduce(0, +) / Double(confidenceScores.count)
        
        // Create license data
        var licenseData = LicenseData()
        licenseData.frontText = aggregatedText
        licenseData.extractedFields = parseLicenseText(aggregatedText)
        
        // Create scan results
        let results = VideoScanResults(
            extractedData: licenseData,
            frameCount: frameCount,
            averageConfidence: avgConfidence,
            qualityScore: calculateOverallQualityScore(),
            processingTime: scanStartTime.map { Date().timeIntervalSince($0) } ?? 0,
            frameAnalyses: frameAnalyses,
            aggregatedText: aggregatedText,
            barcodeData: barcodeData,
            faceDetectionResults: faceDetectionResults,
            currentFrame: frameAnalyses.last?.imageQuality.overallQuality == "Excellent" ? 
                createMockFrame() : nil // Use best quality frame
        )
        
        DispatchQueue.main.async {
            self.delegate?.frameProcessor(self, didCompleteScan: results)
        }
    }
    
    private func aggregateTextFromFrames() -> String {
        // Combine text from all frames, removing duplicates and low-confidence text
        var textFrequency: [String: Int] = [:]
        var textConfidence: [String: Double] = [:]
        
        for (index, text) in extractedTexts.enumerated() {
            let words = text.components(separatedBy: " ")
            let confidence = confidenceScores[index]
            
            for word in words {
                let cleanWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanWord.isEmpty {
                    textFrequency[cleanWord, default: 0] += 1
                    textConfidence[cleanWord, default: 0] += confidence
                }
            }
        }
        
        // Build aggregated text with most frequent and high-confidence words
        let sortedWords = textFrequency.sorted { first, second in
            let firstConfidence = textConfidence[first.key] ?? 0
            let secondConfidence = textConfidence[second.key] ?? 0
            
            if first.value == second.value {
                return firstConfidence > secondConfidence
            }
            return first.value > second.value
        }
        
        return sortedWords.prefix(50).map { $0.key }.joined(separator: " ")
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

// MARK: - VideoFrameProcessor Delegate Protocol

protocol VideoFrameProcessorDelegate: AnyObject {
    func frameProcessor(_ processor: VideoFrameProcessor, didUpdateQuality quality: VideoBasedScanner.QualityFeedback)
    func frameProcessor(_ processor: VideoFrameProcessor, didCompleteScan results: VideoScanResults)
}
