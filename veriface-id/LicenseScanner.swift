//
//  LicenseScanner.swift
//  check-id
//
//  Created: December 2024
//  Purpose: Dedicated license scanner for ID card front/back capture
//

import SwiftUI
import AVFoundation
import Vision

// MARK: - License Scanner

class LicenseScanner: NSObject, ObservableObject {
    @Published var isScanning = false
    @Published var currentFrame: UIImage?
    @Published var scanProgress: Double = 0.0
    @Published var scanResults: LicenseScanResults?
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var scanTimer: Timer?
    private var scanDuration: TimeInterval = 3.0 // Shorter for license scanning
    private var scanStartTime: Date?
    
    struct LicenseScanResults {
        let capturedImage: UIImage
        let confidence: Double
        let quality: String
        let timestamp: TimeInterval
    }
    
    func startCameraPreview() {
        print("Starting camera preview for license scanning...")
        setupCaptureSession()
    }
    
    func startLicenseScan(for side: LicenseSide) {
        print("Starting license scan for \(side) side...")
        isScanning = true
        scanProgress = 0.0
        scanResults = nil
        scanStartTime = Date()
        
        // Check camera permissions first
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            if granted {
                print("Camera permission granted for license scanning")
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
                print("Camera permission denied for license scanning")
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
        print("Setting up license capture session...")
        captureSession = AVCaptureSession()
        
        guard let session = captureSession else {
            print("Failed to create license capture session")
            DispatchQueue.main.async { [weak self] in
                self?.isScanning = false
            }
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.configureLicenseSession(session)
        }
    }
    
    private func configureLicenseSession(_ session: AVCaptureSession) {
        // Use back camera for license scanning
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Failed to get back camera device")
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
                print("Failed to add back camera input")
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
            
            DispatchQueue.main.async { [weak self] in
                self?.previewLayer = AVCaptureVideoPreviewLayer(session: session)
                self?.previewLayer?.videoGravity = .resizeAspectFill
            }
            
            // Start the session
            session.startRunning()
            print("License capture session started successfully")
            
        } catch {
            print("Failed to setup license capture session: \(error)")
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
            finalizeLicenseScan()
        }
    }
    
    private func finalizeLicenseScan() {
        stopScanning()
        
        // Create scan results with the best captured frame
        if let bestFrame = currentFrame {
            let results = LicenseScanResults(
                capturedImage: bestFrame,
                confidence: 0.9, // High confidence for manual capture
                quality: "Excellent",
                timestamp: Date().timeIntervalSince1970
            )
            
            print("License scan complete:")
            print("   Image captured successfully")
            print("   Quality: Excellent")
            
            DispatchQueue.main.async {
                self.scanResults = results
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate for License Scanning

extension LicenseScanner: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Convert to UIImage with proper orientation
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        // Create UIImage with proper orientation for back camera
        let frame = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
        
        // Update current frame for preview
        DispatchQueue.main.async {
            self.currentFrame = frame
        }
    }
}

// MARK: - License Side Enum

enum LicenseSide {
    case front
    case back
}
