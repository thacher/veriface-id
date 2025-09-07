//
//  FaceRecognitionScanner.swift
//  check-id
//
//  Created: December 2024
//  Purpose: Dedicated face recognition scanner with liveness detection
//

import SwiftUI
import AVFoundation
import Vision

// MARK: - Face Recognition Scanner

class FaceRecognitionScanner: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var currentFrame: UIImage?
    @Published var faceDetected = false
    @Published var scanProgress: Double = 0.0
    @Published var faceResults: FaceRecognitionResults?
    @Published var currentCameraPosition: AVCaptureDevice.Position = .front
    @Published var currentGuidanceStep: FaceGuidanceStep = .center
    @Published var guidanceProgress: Double = 0.0
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var scanTimer: Timer?
    private var guidanceTimer: Timer?
    private var scanDuration: TimeInterval = 5.0
    private var faceDetectionResults: [FaceDetectionResult] = []
    private var scanStartTime: Date?
    private var currentCameraInput: AVCaptureDeviceInput?
    private var movementTracking = MovementTracking()
    
    struct FaceDetectionResult {
        let timestamp: TimeInterval
        let confidence: Double
        let faceRect: CGRect
        let quality: String
        let faceLandmarks: FaceLandmarks?
        let movementScore: Double
        let eyeOpenness: Double
        let smileIntensity: Double
        let headPose: HeadPose
    }
    
    struct FaceLandmarks {
        let leftEye: [CGPoint]
        let rightEye: [CGPoint]
        let nose: [CGPoint]
        let mouth: [CGPoint]
        let leftEyebrow: [CGPoint]
        let rightEyebrow: [CGPoint]
    }
    
    struct HeadPose {
        let pitch: Double // Up/down rotation
        let yaw: Double   // Left/right rotation
        let roll: Double  // Tilt rotation
    }
    
    struct MovementTracking {
        var eyeBlinkCount: Int = 0
        var smileDetections: Int = 0
        var headMovementCount: Int = 0
        var gazeDirectionChanges: Int = 0
        var lastBlinkTime: TimeInterval = 0
        var lastSmileTime: TimeInterval = 0
        var lastHeadMovementTime: TimeInterval = 0
        var lastGazeChangeTime: TimeInterval = 0
        var eyeOpennessHistory: [Double] = []
        var smileIntensityHistory: [Double] = []
        var headPoseHistory: [HeadPose] = []
    }
    
    enum FaceGuidanceStep: CaseIterable {
        case center, smile, lookLeft, lookRight, lookUp, lookDown, blink
        
        var instruction: String {
            switch self {
            case .center: return "Center your face"
            case .smile: return "Smile naturally"
            case .lookLeft: return "Look to the left"
            case .lookRight: return "Look to the right"
            case .lookUp: return "Look up"
            case .lookDown: return "Look down"
            case .blink: return "Blink naturally"
            }
        }
        
        var icon: String {
            switch self {
            case .center: return "face.smiling"
            case .smile: return "face.smiling.fill"
            case .lookLeft: return "arrow.left"
            case .lookRight: return "arrow.right"
            case .lookUp: return "arrow.up"
            case .lookDown: return "arrow.down"
            case .blink: return "eye"
            }
        }
        
        var duration: TimeInterval {
            switch self {
            case .center: return 1.5
            case .smile: return 1.0
            case .lookLeft: return 0.8
            case .lookRight: return 0.8
            case .lookUp: return 0.8
            case .lookDown: return 0.8
            case .blink: return 0.5
            }
        }
    }
    
    func startCameraPreview() {
        print("Starting camera preview for face recognition...")
        setupCaptureSession()
    }
    
    func switchCamera() {
        print("Switching camera from \(currentCameraPosition == .front ? "front" : "back") to \(currentCameraPosition == .front ? "back" : "front")")
        
        guard let session = captureSession else {
            print("No capture session available for camera switch")
            return
        }
        
        // Determine new camera position
        let newPosition: AVCaptureDevice.Position = currentCameraPosition == .front ? .back : .front
        
        // Get the new camera device
        guard let newCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
            print("Failed to get camera device for position: \(newPosition)")
            return
        }
        
        do {
            // Create new input
            let newInput = try AVCaptureDeviceInput(device: newCamera)
            
            // Begin configuration
            session.beginConfiguration()
            
            // Remove current input if it exists
            if let currentInput = currentCameraInput {
                session.removeInput(currentInput)
            }
            
            // Add new input
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                currentCameraInput = newInput
                currentCameraPosition = newPosition
                print("Successfully switched to \(newPosition == .front ? "front" : "back") camera")
            } else {
                print("Failed to add new camera input")
            }
            
            // Commit configuration
            session.commitConfiguration()
            
        } catch {
            print("Failed to switch camera: \(error)")
        }
    }
    
    func startFaceRecognition() {
        print("Starting face recognition with guidance...")
        isScanning = true
        scanProgress = 0.0
        guidanceProgress = 0.0
        faceDetected = false
        faceDetectionResults.removeAll()
        scanStartTime = Date()
        currentGuidanceStep = .center
        
        // Check camera permissions first
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            if granted {
                print("Camera permission granted for face recognition")
                DispatchQueue.global(qos: .userInitiated).async {
                    self?.setupCaptureSession()
                    
                    DispatchQueue.main.async {
                        // Start guidance timer
                        self?.startGuidanceSequence()
                        
                        // Start scan timer on main thread
                        self?.scanTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                            self?.updateScanProgress()
                        }
                    }
                }
            } else {
                print("Camera permission denied for face recognition")
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
        guidanceTimer?.invalidate()
        guidanceTimer = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }
    
    private func startGuidanceSequence() {
        print("Starting face guidance sequence...")
        guidanceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateGuidanceProgress()
        }
    }
    
    private func updateGuidanceProgress() {
        guard isScanning else { return }
        
        let currentStepDuration = currentGuidanceStep.duration
        let increment = 0.1 / currentStepDuration
        
        if guidanceProgress + increment <= 1.0 {
            guidanceProgress += increment
        } else {
            guidanceProgress = 1.0
            moveToNextGuidanceStep()
        }
    }
    
    private func moveToNextGuidanceStep() {
        let allSteps = FaceGuidanceStep.allCases
        guard let currentIndex = allSteps.firstIndex(of: currentGuidanceStep) else { return }
        
        let nextIndex = (currentIndex + 1) % allSteps.count
        currentGuidanceStep = allSteps[nextIndex]
        guidanceProgress = 0.0
        
        print("Moving to guidance step: \(currentGuidanceStep.instruction)")
    }
    
    private func setupCaptureSession() {
        print("Setting up face recognition capture session...")
        captureSession = AVCaptureSession()
        
        guard let session = captureSession else {
            print("Failed to create face recognition capture session")
            DispatchQueue.main.async { [weak self] in
                self?.isScanning = false
            }
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.configureFaceRecognitionSession(session)
        }
    }
    
    private func configureFaceRecognitionSession(_ session: AVCaptureSession) {
        // Use current camera position for face recognition
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition) else {
            print("Failed to get \(currentCameraPosition == .front ? "front" : "back") camera device")
            DispatchQueue.main.async { [weak self] in
                self?.isScanning = false
            }
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            currentCameraInput = input
            
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                print("Failed to add \(currentCameraPosition == .front ? "front" : "back") camera input")
                DispatchQueue.main.async { [weak self] in
                    self?.isScanning = false
                }
                return
            }
            
            // Add video data output for real-time face detection
            let videoDataOutput = AVCaptureVideoDataOutput()
            videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: .userInitiated))
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            
            if session.canAddOutput(videoDataOutput) {
                session.addOutput(videoDataOutput)
            } else {
                print("Failed to add video data output")
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.previewLayer = AVCaptureVideoPreviewLayer(session: session)
                self?.previewLayer?.videoGravity = .resizeAspectFill
            }
            
            // Start the session
            session.startRunning()
            print("Face recognition capture session started successfully")
            
        } catch {
            print("Failed to setup face recognition capture session: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.isScanning = false
            }
        }
    }
    
    private func updateScanProgress() {
        guard isScanning else { return }
        
        guard scanDuration > 0 else {
            print("Warning: scanDuration is zero or negative")
            stopScanning()
            return
        }
        
        let increment = 0.1 / scanDuration
        
        if scanProgress + increment <= 1.0 {
            scanProgress += increment
        } else {
            scanProgress = 1.0
        }
        
        if scanProgress >= 1.0 {
            finalizeFaceRecognition()
        }
    }
    
    private func finalizeFaceRecognition() {
        stopScanning()
        
        // Calculate face recognition results
        let avgConfidence = faceDetectionResults.isEmpty ? 0.0 : 
            faceDetectionResults.map { $0.confidence }.reduce(0, +) / Double(faceDetectionResults.count)
        
        let quality = determineOverallQuality()
        let livenessScore = calculateLivenessScore()
        
        let results = FaceRecognitionResults(
            confidence: avgConfidence,
            quality: quality,
            livenessScore: livenessScore,
            timestamp: Date().timeIntervalSince1970
        )
        
        print("Face recognition complete:")
        print("   Confidence: \(String(format: "%.2f", avgConfidence * 100))%")
        print("   Quality: \(quality)")
        print("   Liveness Score: \(String(format: "%.2f", livenessScore * 100))%")
        print("   Frames analyzed: \(faceDetectionResults.count)")
        
        DispatchQueue.main.async {
            self.faceResults = results
        }
    }
    
    private func determineOverallQuality() -> String {
        let detectionCount = faceDetectionResults.count
        let avgConfidence = faceDetectionResults.isEmpty ? 0.0 : 
            faceDetectionResults.map { $0.confidence }.reduce(0, +) / Double(faceDetectionResults.count)
        
        if detectionCount >= 30 && avgConfidence > 0.8 {
            return "Excellent"
        } else if detectionCount >= 20 && avgConfidence > 0.6 {
            return "Good"
        } else if detectionCount >= 10 && avgConfidence > 0.4 {
            return "Fair"
        } else {
            return "Poor"
        }
    }
    
    private func calculateLivenessScore() -> Double {
        guard !faceDetectionResults.isEmpty else { return 0.0 }
        
        var score = 0.0
        
        // Face detection consistency (25%)
        let avgConfidence = faceDetectionResults.map { $0.confidence }.reduce(0, +) / Double(faceDetectionResults.count)
        score += avgConfidence * 0.25
        
        // Detection frequency (20%)
        let detectionFrequency = min(Double(faceDetectionResults.count) / 50.0, 1.0) // Expect ~50 detections in 5 seconds
        score += detectionFrequency * 0.20
        
        // Quality consistency (15%)
        let qualityScores = faceDetectionResults.map { result in
            switch result.quality {
            case "Excellent": return 1.0
            case "Good": return 0.8
            case "Fair": return 0.6
            default: return 0.4
            }
        }
        let avgQuality = qualityScores.reduce(0, +) / Double(qualityScores.count)
        score += avgQuality * 0.15
        
        // Movement tracking (40%)
        let movementScore = calculateComprehensiveMovementScore()
        score += movementScore * 0.40
        
        return min(score, 1.0)
    }
    
    private func calculateComprehensiveMovementScore() -> Double {
        var score = 0.0
        
        // Eye movement analysis (30%)
        let eyeMovementScore = calculateEyeMovementScore()
        score += eyeMovementScore * 0.30
        
        // Smile detection (20%)
        let smileScore = calculateSmileDetectionScore()
        score += smileScore * 0.20
        
        // Head movement analysis (30%)
        let headMovementScore = calculateHeadMovementAnalysisScore()
        score += headMovementScore * 0.30
        
        // Natural movement patterns (20%)
        let naturalPatternScore = calculateNaturalPatternScore()
        score += naturalPatternScore * 0.20
        
        return score
    }
    
    private func calculateEyeMovementScore() -> Double {
        guard !faceDetectionResults.isEmpty else { return 0.0 }
        
        var score = 0.0
        
        // Check for natural blinking
        let blinkCount = movementTracking.eyeBlinkCount
        let expectedBlinks = min(Double(faceDetectionResults.count) / 30.0, 3.0) // Expect ~3 blinks in 5 seconds
        let blinkScore = min(Double(blinkCount) / expectedBlinks, 1.0)
        score += blinkScore * 0.4
        
        // Check eye openness variation
        let eyeOpennessValues = faceDetectionResults.map { $0.eyeOpenness }
        let eyeVariance = calculateVariance(eyeOpennessValues)
        let varianceScore = min(eyeVariance * 10, 1.0) // Normalize variance
        score += varianceScore * 0.3
        
        // Check for natural eye movement
        let eyeMovementScore = calculateEyeMovementVariation()
        score += eyeMovementScore * 0.3
        
        return score
    }
    
    private func calculateEyeMovementVariation() -> Double {
        guard faceDetectionResults.count >= 5 else { return 0.0 }
        
        let recentResults = Array(faceDetectionResults.suffix(10))
        var movementCount = 0
        
        for i in 1..<recentResults.count {
            let currentOpenness = recentResults[i].eyeOpenness
            let previousOpenness = recentResults[i-1].eyeOpenness
            let change = abs(currentOpenness - previousOpenness)
            
            if change > 0.1 { // Significant eye movement
                movementCount += 1
            }
        }
        
        let movementFrequency = Double(movementCount) / Double(recentResults.count - 1)
        return min(movementFrequency * 2, 1.0) // Normalize to 0-1
    }
    
    private func calculateSmileDetectionScore() -> Double {
        guard !faceDetectionResults.isEmpty else { return 0.0 }
        
        var score = 0.0
        
        // Check for smile detections
        let smileCount = movementTracking.smileDetections
        let expectedSmiles = 1.0 // Expect at least 1 smile
        let smileScore = min(Double(smileCount) / expectedSmiles, 1.0)
        score += smileScore * 0.5
        
        // Check smile intensity variation
        let smileIntensities = faceDetectionResults.map { $0.smileIntensity }
        let avgSmileIntensity = smileIntensities.reduce(0, +) / Double(smileIntensities.count)
        let intensityScore = min(avgSmileIntensity * 1.5, 1.0)
        score += intensityScore * 0.5
        
        return score
    }
    
    private func calculateHeadMovementAnalysisScore() -> Double {
        guard !faceDetectionResults.isEmpty else { return 0.0 }
        
        var score = 0.0
        
        // Check head movement count
        let headMovementCount = movementTracking.headMovementCount
        let expectedMovements = 2.0 // Expect at least 2 head movements
        let movementScore = min(Double(headMovementCount) / expectedMovements, 1.0)
        score += movementScore * 0.4
        
        // Check head pose variation
        let poseVariations = calculateHeadPoseVariation()
        score += poseVariations * 0.3
        
        // Check for natural head movement timing
        let timingScore = calculateHeadMovementTiming()
        score += timingScore * 0.3
        
        return score
    }
    
    private func calculateHeadPoseVariation() -> Double {
        guard faceDetectionResults.count >= 5 else { return 0.0 }
        
        let recentResults = Array(faceDetectionResults.suffix(10))
        var totalVariation = 0.0
        
        for i in 1..<recentResults.count {
            let currentPose = recentResults[i].headPose
            let previousPose = recentResults[i-1].headPose
            
            let pitchChange = abs(currentPose.pitch - previousPose.pitch)
            let yawChange = abs(currentPose.yaw - previousPose.yaw)
            let rollChange = abs(currentPose.roll - previousPose.roll)
            
            totalVariation += pitchChange + yawChange + rollChange
        }
        
        let avgVariation = totalVariation / Double(recentResults.count - 1)
        return min(avgVariation * 5, 1.0) // Normalize to 0-1
    }
    
    private func calculateHeadMovementTiming() -> Double {
        guard faceDetectionResults.count >= 3 else { return 0.0 }
        
        let recentResults = Array(faceDetectionResults.suffix(10))
        var movementIntervals: [TimeInterval] = []
        
        for i in 1..<recentResults.count {
            let currentPose = recentResults[i].headPose
            let previousPose = recentResults[i-1].headPose
            
            let poseChange = abs(currentPose.pitch - previousPose.pitch) + 
                           abs(currentPose.yaw - previousPose.yaw) + 
                           abs(currentPose.roll - previousPose.roll)
            
            if poseChange > 0.1 { // Significant movement
                let interval = recentResults[i].timestamp - recentResults[i-1].timestamp
                movementIntervals.append(interval)
            }
        }
        
        guard !movementIntervals.isEmpty else { return 0.0 }
        
        let avgInterval = movementIntervals.reduce(0, +) / Double(movementIntervals.count)
        
        // Natural head movement interval is 1-3 seconds
        if avgInterval >= 1.0 && avgInterval <= 3.0 {
            return 1.0
        } else if avgInterval >= 0.5 && avgInterval <= 5.0 {
            return 0.5
        } else {
            return 0.0
        }
    }
    
    private func calculateNaturalPatternScore() -> Double {
        guard !faceDetectionResults.isEmpty else { return 0.0 }
        
        var score = 0.0
        
        // Check for natural movement patterns
        let patternScore = analyzeMovementPatterns()
        score += patternScore * 0.5
        
        // Check for anti-spoofing indicators
        let antiSpoofScore = calculateAntiSpoofingScore()
        score += antiSpoofScore * 0.5
        
        return score
    }
    
    private func analyzeMovementPatterns() -> Double {
        guard faceDetectionResults.count >= 10 else { return 0.0 }
        
        let recentResults = Array(faceDetectionResults.suffix(20))
        
        // Check for natural variance in movements
        let eyeOpennessValues = recentResults.map { $0.eyeOpenness }
        let smileIntensities = recentResults.map { $0.smileIntensity }
        
        let eyeVariance = calculateVariance(eyeOpennessValues)
        let smileVariance = calculateVariance(smileIntensities)
        
        // Natural movements should have moderate variance (not too static, not too erratic)
        let eyeVarianceScore = min(max((eyeVariance - 0.01) / 0.05, 0.0), 1.0)
        let smileVarianceScore = min(max((smileVariance - 0.02) / 0.08, 0.0), 1.0)
        
        return (eyeVarianceScore + smileVarianceScore) / 2.0
    }
    
    private func calculateAntiSpoofingScore() -> Double {
        guard !faceDetectionResults.isEmpty else { return 0.0 }
        
        var score = 0.0
        
        // Check for natural timing patterns
        let timingScore = checkNaturalTiming()
        score += timingScore * 0.4
        
        // Check for realistic movement ranges
        let rangeScore = checkRealisticMovementRanges()
        score += rangeScore * 0.3
        
        // Check for movement correlation
        let correlationScore = checkMovementCorrelation()
        score += correlationScore * 0.3
        
        return score
    }
    
    private func checkNaturalTiming() -> Double {
        guard faceDetectionResults.count >= 5 else { return 0.0 }
        
        let recentResults = Array(faceDetectionResults.suffix(10))
        var naturalTimingCount = 0
        
        for i in 1..<recentResults.count {
            let interval = recentResults[i].timestamp - recentResults[i-1].timestamp
            
            // Natural movements should have reasonable intervals (not too fast, not too slow)
            if interval >= 0.1 && interval <= 2.0 {
                naturalTimingCount += 1
            }
        }
        
        return Double(naturalTimingCount) / Double(recentResults.count - 1)
    }
    
    private func checkRealisticMovementRanges() -> Double {
        guard !faceDetectionResults.isEmpty else { return 0.0 }
        
        let eyeOpennessValues = faceDetectionResults.map { $0.eyeOpenness }
        let smileIntensities = faceDetectionResults.map { $0.smileIntensity }
        
        // Check if values are within realistic ranges
        let eyeRange = eyeOpennessValues.max()! - eyeOpennessValues.min()!
        let smileRange = smileIntensities.max()! - smileIntensities.min()!
        
        let eyeRangeScore = min(eyeRange, 1.0) // Should have some variation
        let smileRangeScore = min(smileRange, 1.0) // Should have some variation
        
        return (eyeRangeScore + smileRangeScore) / 2.0
    }
    
    private func checkMovementCorrelation() -> Double {
        guard faceDetectionResults.count >= 5 else { return 0.0 }
        
        let recentResults = Array(faceDetectionResults.suffix(10))
        var correlationCount = 0
        
        for i in 1..<recentResults.count {
            let current = recentResults[i]
            let previous = recentResults[i-1]
            
            // Check if movements are correlated (not random)
            let eyeChange = abs(current.eyeOpenness - previous.eyeOpenness)
            let smileChange = abs(current.smileIntensity - previous.smileIntensity)
            
            // Natural movements should have some correlation
            if eyeChange > 0.05 || smileChange > 0.05 {
                correlationCount += 1
            }
        }
        
        return Double(correlationCount) / Double(recentResults.count - 1)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate for Face Recognition

extension FaceRecognitionScanner: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Convert to UIImage with proper orientation
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        // Create UIImage with proper orientation for front camera
        let frame = UIImage(cgImage: cgImage, scale: 1.0, orientation: .leftMirrored)
        
        // Update current frame for preview
        DispatchQueue.main.async {
            self.currentFrame = frame
        }
        
        // Perform face detection
        performFaceDetection(on: frame)
    }
    
        private func performFaceDetection(on frame: UIImage) {
        guard let cgImage = frame.cgImage else { return }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        // Create comprehensive face analysis request
        let faceLandmarksRequest = VNDetectFaceLandmarksRequest { [weak self] request, error in
            if let error = error {
                print("Face landmarks detection error: \(error)")
                return
            }
            
            guard let observations = request.results as? [VNFaceObservation],
                  let faceObservation = observations.first else {
                DispatchQueue.main.async {
                    self?.faceDetected = false
                }
                return
            }
            
            // STRICT FACE VALIDATION - Prevent false positives from objects
            guard self?.isValidFaceDetection(faceObservation: faceObservation) == true else {
                print("Face detection rejected - likely false positive from object")
                DispatchQueue.main.async {
                    self?.faceDetected = false
                }
                return
            }
            
            let hasFace = !observations.isEmpty
            let confidence = faceObservation.confidence
            let faceRect = faceObservation.boundingBox
            
            DispatchQueue.main.async {
                self?.faceDetected = hasFace
            }
            
            // Analyze face landmarks and movements
            if hasFace {
                let landmarks = self?.extractFaceLandmarks(from: faceObservation)
                let eyeOpenness = self?.calculateEyeOpenness(landmarks: landmarks) ?? 0.0
                let smileIntensity = self?.calculateSmileIntensity(landmarks: landmarks) ?? 0.0
                let headPose = self?.calculateHeadPose(from: faceObservation) ?? HeadPose(pitch: 0, yaw: 0, roll: 0)
                let movementScore = self?.calculateMovementScore(eyeOpenness: eyeOpenness, smileIntensity: smileIntensity, headPose: headPose) ?? 0.0
                
                // Track movements
                self?.trackMovements(eyeOpenness: eyeOpenness, smileIntensity: smileIntensity, headPose: headPose)
                
                let quality = self?.determineFaceQuality(confidence: confidence, faceRect: faceRect, landmarks: landmarks) ?? "Fair"
                let result = FaceDetectionResult(
                    timestamp: Date().timeIntervalSince1970,
                    confidence: Double(confidence),
                    faceRect: faceRect,
                    quality: quality,
                    faceLandmarks: landmarks,
                    movementScore: movementScore,
                    eyeOpenness: eyeOpenness,
                    smileIntensity: smileIntensity,
                    headPose: headPose
                )
                
                DispatchQueue.main.async {
                    self?.faceDetectionResults.append(result)
                }
            }
        }
        
        do {
            try requestHandler.perform([faceLandmarksRequest])
        } catch {
            print("Face landmarks detection request error: \(error)")
        }
    }
    
    private func extractFaceLandmarks(from observation: VNFaceObservation) -> FaceLandmarks? {
        guard let landmarks = observation.landmarks else { return nil }
        
        let leftEye = landmarks.leftEye?.normalizedPoints ?? []
        let rightEye = landmarks.rightEye?.normalizedPoints ?? []
        let nose = landmarks.nose?.normalizedPoints ?? []
        let mouth = landmarks.outerLips?.normalizedPoints ?? []
        let leftEyebrow = landmarks.leftEyebrow?.normalizedPoints ?? []
        let rightEyebrow = landmarks.rightEyebrow?.normalizedPoints ?? []
        
        return FaceLandmarks(
            leftEye: leftEye,
            rightEye: rightEye,
            nose: nose,
            mouth: mouth,
            leftEyebrow: leftEyebrow,
            rightEyebrow: rightEyebrow
        )
    }
    
    private func calculateEyeOpenness(landmarks: FaceLandmarks?) -> Double {
        guard let landmarks = landmarks,
              !landmarks.leftEye.isEmpty,
              !landmarks.rightEye.isEmpty else { return 0.0 }
        
        // Calculate eye aspect ratio (EAR) for both eyes
        let leftEAR = calculateEyeAspectRatio(eyePoints: landmarks.leftEye)
        let rightEAR = calculateEyeAspectRatio(eyePoints: landmarks.rightEye)
        
        // Average both eyes
        let avgEAR = (leftEAR + rightEAR) / 2.0
        
        // Normalize to 0-1 scale (typical EAR values are 0.2-0.3)
        let normalizedOpenness = min(max((avgEAR - 0.15) / 0.15, 0.0), 1.0)
        
        return normalizedOpenness
    }
    
    private func calculateEyeAspectRatio(eyePoints: [CGPoint]) -> Double {
        guard eyePoints.count >= 6 else { return 0.0 }
        
        // Calculate vertical distances
        let v1 = distance(from: eyePoints[1], to: eyePoints[5])
        let v2 = distance(from: eyePoints[2], to: eyePoints[4])
        
        // Calculate horizontal distance
        let h = distance(from: eyePoints[0], to: eyePoints[3])
        
        // Eye aspect ratio
        let ear = (v1 + v2) / (2.0 * h)
        
        return ear
    }
    
    private func calculateSmileIntensity(landmarks: FaceLandmarks?) -> Double {
        guard let landmarks = landmarks,
              !landmarks.mouth.isEmpty else { return 0.0 }
        
        // Calculate mouth aspect ratio (MAR)
        let mar = calculateMouthAspectRatio(mouthPoints: landmarks.mouth)
        
        // Normalize to 0-1 scale (typical MAR values are 0.3-0.8)
        let normalizedSmile = min(max((mar - 0.3) / 0.5, 0.0), 1.0)
        
        return normalizedSmile
    }
    
    private func calculateMouthAspectRatio(mouthPoints: [CGPoint]) -> Double {
        guard mouthPoints.count >= 8 else { return 0.0 }
        
        // Calculate vertical distances
        let v1 = distance(from: mouthPoints[2], to: mouthPoints[6])
        let v2 = distance(from: mouthPoints[3], to: mouthPoints[5])
        
        // Calculate horizontal distance
        let h = distance(from: mouthPoints[0], to: mouthPoints[4])
        
        // Mouth aspect ratio
        let mar = (v1 + v2) / (2.0 * h)
        
        return mar
    }
    
    private func calculateHeadPose(from observation: VNFaceObservation) -> HeadPose {
        // Use Vision framework's built-in head pose estimation
        let pitch = Double(observation.roll?.doubleValue ?? 0.0)
        let yaw = Double(observation.yaw?.doubleValue ?? 0.0)
        let roll = Double(observation.roll?.doubleValue ?? 0.0)
        
        return HeadPose(pitch: pitch, yaw: yaw, roll: roll)
    }
    
    private func calculateMovementScore(eyeOpenness: Double, smileIntensity: Double, headPose: HeadPose) -> Double {
        var score = 0.0
        
        // Eye movement score (30%)
        let eyeScore = min(eyeOpenness * 2.0, 1.0) // Normalize to 0-1
        score += eyeScore * 0.3
        
        // Smile detection score (20%)
        let smileScore = smileIntensity
        score += smileScore * 0.2
        
        // Head movement score (30%)
        let headMovementScore = calculateHeadMovementScore(headPose: headPose)
        score += headMovementScore * 0.3
        
        // Natural movement score (20%)
        let naturalMovementScore = calculateNaturalMovementScore()
        score += naturalMovementScore * 0.2
        
        return min(score, 1.0)
    }
    
    private func calculateHeadMovementScore(headPose: HeadPose) -> Double {
        // Calculate head movement based on pose changes
        let poseChange = abs(headPose.pitch) + abs(headPose.yaw) + abs(headPose.roll)
        let normalizedChange = min(poseChange / 0.5, 1.0) // Normalize to 0-1
        
        return normalizedChange
    }
    
    private func calculateNaturalMovementScore() -> Double {
        // Analyze movement patterns for naturalness
        let recentResults = Array(faceDetectionResults.suffix(10))
        guard recentResults.count >= 5 else { return 0.5 }
        
        var naturalnessScore = 0.0
        
        // Check for consistent but varied movements
        let movementVariance = calculateMovementVariance(recentResults)
        naturalnessScore += movementVariance * 0.5
        
        // Check for appropriate timing between movements
        let timingScore = calculateMovementTimingScore(recentResults)
        naturalnessScore += timingScore * 0.5
        
        return naturalnessScore
    }
    
    private func calculateMovementVariance(_ results: [FaceDetectionResult]) -> Double {
        guard results.count >= 3 else { return 0.0 }
        
        let eyeOpennessValues = results.map { $0.eyeOpenness }
        let variance = calculateVariance(eyeOpennessValues)
        
        // Normalize variance (too low = static, too high = erratic, medium = natural)
        let normalizedVariance = min(max((variance - 0.01) / 0.05, 0.0), 1.0)
        
        return normalizedVariance
    }
    
    private func calculateMovementTimingScore(_ results: [FaceDetectionResult]) -> Double {
        guard results.count >= 3 else { return 0.0 }
        
        var timingScore = 0.0
        
        // Check for natural blink timing (every 2-4 seconds)
        let blinkIntervals = calculateBlinkIntervals(results)
        let naturalBlinkScore = calculateNaturalBlinkScore(blinkIntervals)
        timingScore += naturalBlinkScore * 0.5
        
        // Check for natural head movement timing
        let headMovementIntervals = calculateHeadMovementIntervals(results)
        let naturalHeadScore = calculateNaturalHeadMovementScore(headMovementIntervals)
        timingScore += naturalHeadScore * 0.5
        
        return timingScore
    }
    
    private func calculateVariance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0.0 }
        
        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDifferences = values.map { pow($0 - mean, 2) }
        let variance = squaredDifferences.reduce(0, +) / Double(values.count)
        
        return variance
    }
    
    private func calculateBlinkIntervals(_ results: [FaceDetectionResult]) -> [TimeInterval] {
        var intervals: [TimeInterval] = []
        var lastBlinkTime: TimeInterval = 0
        
        for result in results {
            if result.eyeOpenness < 0.3 { // Eye closed threshold
                if lastBlinkTime > 0 {
                    intervals.append(result.timestamp - lastBlinkTime)
                }
                lastBlinkTime = result.timestamp
            }
        }
        
        return intervals
    }
    
    private func calculateNaturalBlinkScore(_ intervals: [TimeInterval]) -> Double {
        guard !intervals.isEmpty else { return 0.0 }
        
        let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
        
        // Natural blink interval is 2-4 seconds
        if avgInterval >= 2.0 && avgInterval <= 4.0 {
            return 1.0
        } else if avgInterval >= 1.0 && avgInterval <= 6.0 {
            return 0.5
        } else {
            return 0.0
        }
    }
    
    private func calculateHeadMovementIntervals(_ results: [FaceDetectionResult]) -> [TimeInterval] {
        var intervals: [TimeInterval] = []
        var lastMovementTime: TimeInterval = 0
        
        for i in 1..<results.count {
            let currentPose = results[i].headPose
            let previousPose = results[i-1].headPose
            
            let poseChange = abs(currentPose.pitch - previousPose.pitch) + 
                           abs(currentPose.yaw - previousPose.yaw) + 
                           abs(currentPose.roll - previousPose.roll)
            
            if poseChange > 0.1 { // Significant head movement
                if lastMovementTime > 0 {
                    intervals.append(results[i].timestamp - lastMovementTime)
                }
                lastMovementTime = results[i].timestamp
            }
        }
        
        return intervals
    }
    
    private func calculateNaturalHeadMovementScore(_ intervals: [TimeInterval]) -> Double {
        guard !intervals.isEmpty else { return 0.0 }
        
        let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
        
        // Natural head movement interval is 1-3 seconds
        if avgInterval >= 1.0 && avgInterval <= 3.0 {
            return 1.0
        } else if avgInterval >= 0.5 && avgInterval <= 5.0 {
            return 0.5
        } else {
            return 0.0
        }
    }
    
    private func trackMovements(eyeOpenness: Double, smileIntensity: Double, headPose: HeadPose) {
        let currentTime = Date().timeIntervalSince1970
        
        // Track eye blinks
        if eyeOpenness < 0.3 && currentTime - movementTracking.lastBlinkTime > 0.5 {
            movementTracking.eyeBlinkCount += 1
            movementTracking.lastBlinkTime = currentTime
        }
        
        // Track smiles
        if smileIntensity > 0.6 && currentTime - movementTracking.lastSmileTime > 1.0 {
            movementTracking.smileDetections += 1
            movementTracking.lastSmileTime = currentTime
        }
        
        // Track head movements
        if !movementTracking.headPoseHistory.isEmpty {
            let lastPose = movementTracking.headPoseHistory.last!
            let poseChange = abs(headPose.pitch - lastPose.pitch) + 
                           abs(headPose.yaw - lastPose.yaw) + 
                           abs(headPose.roll - lastPose.roll)
            
            if poseChange > 0.1 && currentTime - movementTracking.lastHeadMovementTime > 0.5 {
                movementTracking.headMovementCount += 1
                movementTracking.lastHeadMovementTime = currentTime
            }
        }
        
        // Store history for analysis
        movementTracking.eyeOpennessHistory.append(eyeOpenness)
        movementTracking.smileIntensityHistory.append(smileIntensity)
        movementTracking.headPoseHistory.append(headPose)
        
        // Keep history manageable
        if movementTracking.eyeOpennessHistory.count > 50 {
            movementTracking.eyeOpennessHistory.removeFirst()
        }
        if movementTracking.smileIntensityHistory.count > 50 {
            movementTracking.smileIntensityHistory.removeFirst()
        }
        if movementTracking.headPoseHistory.count > 50 {
            movementTracking.headPoseHistory.removeFirst()
        }
    }
    
    private func distance(from point1: CGPoint, to point2: CGPoint) -> Double {
        let dx = point1.x - point2.x
        let dy = point1.y - point2.y
        return sqrt(dx * dx + dy * dy)
    }
    
    private func determineFaceQuality(confidence: Float, faceRect: CGRect, landmarks: FaceLandmarks?) -> String {
        let confidenceScore = Double(confidence)
        
        // Check face size (should be reasonably large)
        let faceSize = faceRect.width * faceRect.height
        let sizeScore = min(faceSize * 4, 1.0) // Normalize to 0-1
        
        // Check face position (should be centered)
        let centerDistance = abs(faceRect.midX - 0.5) + abs(faceRect.midY - 0.5)
        let positionScore = max(0, 1.0 - centerDistance)
        
        // Check landmark quality
        let landmarkScore = landmarks != nil ? 1.0 : 0.5
        
        let overallScore = (confidenceScore + sizeScore + positionScore + landmarkScore) / 4.0
        
        if overallScore > 0.8 {
            return "Excellent"
        } else if overallScore > 0.6 {
            return "Good"
        } else if overallScore > 0.4 {
            return "Fair"
        } else {
            return "Poor"
        }
    }
    
    // MARK: - Strict Face Validation to Prevent False Positives
    
    private func isValidFaceDetection(faceObservation: VNFaceObservation) -> Bool {
        let confidence = Double(faceObservation.confidence)
        let faceRect = faceObservation.boundingBox
        
        // 1. MINIMUM CONFIDENCE THRESHOLD - Reasonable threshold for face detection
        guard confidence >= 0.3 else {
            print("Face detection rejected: Low confidence (\(String(format: "%.2f", confidence)))")
            return false
        }
        
        // 2. FACE SIZE VALIDATION - Must be reasonably sized (not too small, not too large)
        let faceArea = faceRect.width * faceRect.height
        guard faceArea >= 0.005 && faceArea <= 0.9 else {
            print("Face detection rejected: Invalid face size (\(String(format: "%.3f", faceArea)))")
            return false
        }
        
        // 3. FACE ASPECT RATIO VALIDATION - Must have human-like proportions
        let aspectRatio = faceRect.width / faceRect.height
        guard aspectRatio >= 0.5 && aspectRatio <= 1.2 else {
            print("Face detection rejected: Invalid aspect ratio (\(String(format: "%.2f", aspectRatio)))")
            return false
        }
        
        // 4. FACE POSITION VALIDATION - Must be reasonably positioned in frame
        let centerX = faceRect.midX
        let centerY = faceRect.midY
        let distanceFromCenter = sqrt(pow(centerX - 0.5, 2) + pow(centerY - 0.5, 2))
        guard distanceFromCenter <= 0.6 else {
            print("Face detection rejected: Too far from center (\(String(format: "%.2f", distanceFromCenter)))")
            return false
        }
        
        // 5. LANDMARK VALIDATION - Must have detectable facial landmarks
        guard let landmarks = faceObservation.landmarks else {
            print("Face detection rejected: No facial landmarks detected")
            return false
        }
        
        // 6. CRITICAL LANDMARK VALIDATION - Must have eyes and mouth (more lenient)
        let hasEyes = (landmarks.leftEye?.normalizedPoints.count ?? 0) >= 4 && 
                     (landmarks.rightEye?.normalizedPoints.count ?? 0) >= 4
        let hasMouth = (landmarks.outerLips?.normalizedPoints.count ?? 0) >= 6
        
        guard hasEyes && hasMouth else {
            print("Face detection rejected: Missing critical landmarks (eyes: \(hasEyes), mouth: \(hasMouth))")
            return false
        }
        
        print("Face detection validated successfully - confidence: \(String(format: "%.2f", confidence))")
        return true
    }
}
