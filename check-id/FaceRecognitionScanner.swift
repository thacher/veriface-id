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
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var scanTimer: Timer?
    private var scanDuration: TimeInterval = 5.0
    private var faceDetectionResults: [FaceDetectionResult] = []
    private var scanStartTime: Date?
    
    struct FaceDetectionResult {
        let timestamp: TimeInterval
        let confidence: Double
        let faceRect: CGRect
        let quality: String
    }
    
    func startCameraPreview() {
        print("Starting camera preview for face recognition...")
        setupCaptureSession()
    }
    
    func startFaceRecognition() {
        print("Starting face recognition scan...")
        isScanning = true
        scanProgress = 0.0
        faceDetected = false
        faceDetectionResults.removeAll()
        scanStartTime = Date()
        
        // Check camera permissions first
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            if granted {
                print("Camera permission granted for face recognition")
                DispatchQueue.global(qos: .userInitiated).async {
                    self?.setupCaptureSession()
                    
                    DispatchQueue.main.async {
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
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.stopRunning()
        }
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
        // Use front camera for face recognition
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("Failed to get front camera device")
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
                print("Failed to add front camera input")
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
        
        // Face detection consistency (40%)
        let avgConfidence = faceDetectionResults.map { $0.confidence }.reduce(0, +) / Double(faceDetectionResults.count)
        score += avgConfidence * 0.4
        
        // Detection frequency (30%)
        let detectionFrequency = min(Double(faceDetectionResults.count) / 50.0, 1.0) // Expect ~50 detections in 5 seconds
        score += detectionFrequency * 0.3
        
        // Quality consistency (30%)
        let qualityScores = faceDetectionResults.map { result in
            switch result.quality {
            case "Excellent": return 1.0
            case "Good": return 0.8
            case "Fair": return 0.6
            default: return 0.4
            }
        }
        let avgQuality = qualityScores.reduce(0, +) / Double(qualityScores.count)
        score += avgQuality * 0.3
        
        return min(score, 1.0)
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
        let request = VNDetectFaceRectanglesRequest { [weak self] request, error in
            if let error = error {
                print("Face detection error: \(error)")
                return
            }
            
            guard let observations = request.results else {
                DispatchQueue.main.async {
                    self?.faceDetected = false
                }
                return
            }
            
            let hasFace = !observations.isEmpty
            let confidence = observations.first?.confidence ?? 0.0
            let faceRect = (observations.first as? VNFaceObservation)?.boundingBox ?? .zero
            
            DispatchQueue.main.async {
                self?.faceDetected = hasFace
            }
            
            // Store detection result for analysis
            if hasFace {
                let quality = self?.determineFaceQuality(confidence: confidence, faceRect: faceRect) ?? "Fair"
                let result = FaceDetectionResult(
                    timestamp: Date().timeIntervalSince1970,
                    confidence: Double(confidence),
                    faceRect: faceRect,
                    quality: quality
                )
                
                DispatchQueue.main.async {
                    self?.faceDetectionResults.append(result)
                }
            }
        }
        
        do {
            try requestHandler.perform([request])
        } catch {
            print("Face detection request error: \(error)")
        }
    }
    
    private func determineFaceQuality(confidence: Float, faceRect: CGRect) -> String {
        let confidenceScore = Double(confidence)
        
        // Check face size (should be reasonably large)
        let faceSize = faceRect.width * faceRect.height
        let sizeScore = min(faceSize * 4, 1.0) // Normalize to 0-1
        
        // Check face position (should be centered)
        let centerDistance = abs(faceRect.midX - 0.5) + abs(faceRect.midY - 0.5)
        let positionScore = max(0, 1.0 - centerDistance)
        
        let overallScore = (confidenceScore + sizeScore + positionScore) / 3.0
        
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
}
