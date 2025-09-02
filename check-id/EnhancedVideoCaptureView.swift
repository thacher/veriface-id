//
//  EnhancedVideoCaptureView.swift
//  check-id
//
//  Created: December 2024
//  Purpose: Enhanced video capture view with real-time quality feedback
//

import SwiftUI
import AVFoundation
import Vision

struct EnhancedVideoCaptureView: View {
    @StateObject private var scanner = VideoBasedScanner()
    @Environment(\.presentationMode) var presentationMode
    
    let side: LicenseSide
    let onScanComplete: (VideoScanResults) -> Void
    
    @State private var showingInstructions = true
    @State private var countdown = 3
    @State private var isCountingDown = false
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(scanner: scanner)
                .ignoresSafeArea()
            
            // Overlay UI
            VStack {
                // Top section
                topSection
                
                Spacer()
                
                // Center section with scan area
                scanArea
                
                Spacer()
                
                // Bottom section
                bottomSection
            }
            .padding()
            
            // Instructions overlay
            if showingInstructions {
                instructionsOverlay
            }
            
            // Countdown overlay
            if isCountingDown {
                countdownOverlay
            }
        }
        .onAppear {
            print("EnhancedVideoCaptureView appeared")
            // Don't auto-start scanning, let user tap the button
        }
        .onDisappear {
            scanner.stopScanning()
        }
    }
    
    private var topSection: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .foregroundColor(.white)
                .font(.system(size: 18, weight: .medium))
                
                Spacer()
                
                Text(side == .front ? "Front of License" : "Back of License")
                    .foregroundColor(.white)
                    .font(.system(size: 20, weight: .semibold))
                
                Spacer()
                
                // Quality indicator
                qualityIndicator
            }
            
            // Progress bar
            ProgressView(value: scanner.scanProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: .green))
                .background(Color.black.opacity(0.3))
                .cornerRadius(4)
        }
    }
    
    private var qualityIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(qualityColor)
                .frame(width: 12, height: 12)
            
            Text(qualityText)
                .foregroundColor(.white)
                .font(.system(size: 14, weight: .medium))
        }
    }
    
    private var qualityColor: Color {
        // Check if we have scan results with field progress
        if let results = scanner.scanResults {
            if results.fieldProgress.isComplete {
                return .green
            } else if results.fieldProgress.progressPercentage >= 75 {
                return .yellow
            } else if results.fieldProgress.progressPercentage >= 50 {
                return .orange
            } else {
                return .red
            }
        }
        
        // Fallback to image quality feedback
        switch scanner.qualityFeedback {
        case .excellent:
            return .green
        case .good:
            return .yellow
        case .poor:
            return .red
        case .none:
            return .gray
        }
    }
    
    private var qualityText: String {
        // Check if we have scan results with field progress
        if let results = scanner.scanResults {
            if results.fieldProgress.isComplete {
                return "Complete ✓"
            } else {
                let progress = Int(results.fieldProgress.progressPercentage)
                let captured = results.fieldProgress.capturedFields.count
                let total = results.fieldProgress.requiredFields.count
                return "\(progress)% (\(captured)/\(total))"
            }
        }
        
        // Fallback to image quality feedback
        switch scanner.qualityFeedback {
        case .excellent:
            return "Excellent"
        case .good:
            return "Good"
        case .poor:
            return "Poor"
        case .none:
            return "Analyzing..."
        }
    }
    
    private var scanArea: some View {
        VStack(spacing: 20) {
            // Scan frame with quality outline
            ZStack {
                // License frame guide with enhanced styling for completion
                RoundedRectangle(cornerRadius: 12)
                    .stroke(qualityColor, lineWidth: scanner.scanResults?.fieldProgress.isComplete == true ? 5 : 3)
                    .frame(width: 280, height: 180)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.1))
                    )
                    .overlay(
                        // Add completion indicator
                        Group {
                            if let results = scanner.scanResults, results.fieldProgress.isComplete {
                                VStack {
                                    HStack {
                                        Spacer()
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.system(size: 24))
                                            .background(Circle().fill(Color.white))
                                    }
                                    Spacer()
                                }
                                .padding(8)
                            }
                        }
                    )
                
                // Corner guides
                VStack {
                    HStack {
                        cornerGuide
                        Spacer()
                        cornerGuide
                    }
                    Spacer()
                    HStack {
                        cornerGuide
                        Spacer()
                        cornerGuide
                    }
                }
                .frame(width: 280, height: 180)
                
                // Center alignment guide
                if scanner.qualityFeedback == .poor {
                    Image(systemName: "hand.raised.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 24))
                        .opacity(0.8)
                }
            }
            
            // Instructions text
            Text(instructionText)
                .foregroundColor(.white)
                .font(.system(size: 16, weight: .medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }
    
    private var cornerGuide: some View {
        Rectangle()
            .fill(qualityColor)
            .frame(width: 20, height: 3)
            .rotationEffect(.degrees(45))
    }
    
    private var instructionText: String {
        // Check if we have scan results with field progress
        if let results = scanner.scanResults {
            if results.fieldProgress.isComplete {
                return "Perfect! All required fields captured ✓"
            } else {
                let missingCount = results.fieldProgress.missingFields.count
                let missingFields = results.fieldProgress.missingFields.prefix(3).joined(separator: ", ")
                let suffix = missingCount > 3 ? " and \(missingCount - 3) more" : ""
                return "Missing \(missingCount) field(s): \(missingFields)\(suffix)"
            }
        }
        
        // Fallback to image quality feedback
        switch scanner.qualityFeedback {
        case .excellent:
            return "Perfect! Keep holding steady"
        case .good:
            return "Good quality - hold steady"
        case .poor:
            return "Adjust position and lighting"
        case .none:
            return "Position license in frame"
        }
    }
    
    private var bottomSection: some View {
        VStack(spacing: 16) {
            // Scan status
            Text(scanStatusText)
                .foregroundColor(.white)
                .font(.system(size: 18, weight: .medium))
            
            // Action buttons
            HStack(spacing: 20) {
                Button("Restart") {
                    restartScan()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.8))
                .cornerRadius(8)
                
                Button("Done") {
                    completeScan()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.green.opacity(0.8))
                .cornerRadius(8)
            }
        }
    }
    
    private var scanStatusText: String {
        if scanner.isScanning {
            return "Scanning... \(Int(scanner.scanProgress * 100))%"
        } else if let results = scanner.scanResults {
            let progress = Int(results.fieldProgress.progressPercentage)
            let captured = results.fieldProgress.capturedFields.count
            let total = results.fieldProgress.requiredFields.count
            let status = results.fieldProgress.isComplete ? "Complete ✓" : "\(progress)% Complete"
            return "\(status) - \(captured)/\(total) fields - \(results.frameCount) frames analyzed"
        } else {
            return "Ready to scan"
        }
    }
    
    private var instructionsOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Image(systemName: "video.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.white)
                
                Text("Video-Based ID Scanning")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 12) {
                    InstructionRow(icon: "1.circle.fill", text: "Hold your device steady")
                    InstructionRow(icon: "2.circle.fill", text: "Position license in the frame")
                    InstructionRow(icon: "3.circle.fill", text: "Ensure good lighting")
                    InstructionRow(icon: "4.circle.fill", text: "Keep scanning for 5 seconds")
                }
                .padding(.horizontal, 20)
                
                Text("The system will analyze multiple frames for better accuracy")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                Button("Start Scanning") {
                    print("Start Scanning button tapped")
                    withAnimation {
                        showingInstructions = false
                        startCountdown()
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(Color.blue)
                .cornerRadius(12)
                .font(.system(size: 18, weight: .semibold))
            }
        }
    }
    
    private var countdownOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack {
                Text("\(countdown)")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Get ready...")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }
    
    private func startScanning() {
        print("EnhancedVideoCaptureView: Starting scan for \(side) side")
        if !scanner.isScanning {
            scanner.startScanning(for: side)
        } else {
            print("Scanner is already scanning, ignoring start request")
        }
    }
    
    private func startCountdown() {
        print("Starting countdown...")
        isCountingDown = true
        countdown = 3
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            print("Countdown: \(self.countdown)")
            self.countdown -= 1
            
            if self.countdown <= 0 {
                print("Countdown finished, starting scan...")
                timer.invalidate()
                self.isCountingDown = false
                self.startScanning()
            }
        }
    }
    
    private func restartScan() {
        scanner.stopScanning()
        startScanning()
    }
    
    private func completeScan() {
        if let results = scanner.scanResults {
            onScanComplete(results)
            presentationMode.wrappedValue.dismiss()
        } else {
            // If no results yet, wait a moment and try again
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let results = scanner.scanResults {
                    onScanComplete(results)
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }
}

// MARK: - Camera Preview View

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var scanner: VideoBasedScanner
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        // Add a loading indicator
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.color = .white
        activityIndicator.center = view.center
        activityIndicator.startAnimating()
        view.addSubview(activityIndicator)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Remove loading indicator when preview layer is ready
        if let previewLayer = scanner.previewLayer {
            // Remove activity indicator
            uiView.subviews.forEach { $0.removeFromSuperview() }
            
            // Add preview layer
            previewLayer.frame = uiView.bounds
            uiView.layer.addSublayer(previewLayer)
        }
    }
}

// MARK: - Instruction Row

struct InstructionRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.white)
                .frame(width: 24)
            
            Text(text)
                .font(.system(size: 16))
                .foregroundColor(.white)
            
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    EnhancedVideoCaptureView(
        side: .front,
        onScanComplete: { results in
            print("Scan completed: \(results.frameCount) frames")
        }
    )
}
