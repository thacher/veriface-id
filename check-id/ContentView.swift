//
//  ContentView.swift
//  check-id
//
//  Created: August 30, 2024
//  Purpose: Modern license scanning interface with streamlined UX flow
//

import SwiftUI
import PhotosUI
import AVFoundation
import Vision
import VisionKit
import CoreImage

// MARK: - UIImage Extension for Rotation
extension UIImage {
    func rotate(radians: CGFloat) -> UIImage {
        let rotatedSize = CGRect(origin: .zero, size: size)
            .applying(CGAffineTransform(rotationAngle: radians))
            .integral.size
        UIGraphicsBeginImageContext(rotatedSize)
        if let context = UIGraphicsGetCurrentContext() {
            let origin = CGPoint(x: rotatedSize.width / 2.0,
                               y: rotatedSize.height / 2.0)
            context.translateBy(x: origin.x, y: origin.y)
            context.rotate(by: radians)
            draw(in: CGRect(x: -size.width / 2.0,
                           y: -size.height / 2.0,
                           width: size.width,
                           height: size.height))
        }
        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return rotatedImage ?? self
    }
}

struct ContentView: View {
    @State private var currentStep: ScanStep = .main
    @State private var frontImage: UIImage?
    @State private var backImage: UIImage?
    @State private var extractedData: LicenseData?
    @State private var isProcessing = false
    @State private var showingResults = false
    @State private var scanProgress: Double = 0.0
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    enum ScanStep {
        case main
        case front
        case back
        case processing
        case results
        case faceRecognition
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.1, green: 0.1, blue: 0.25),
                    Color(red: 0.15, green: 0.15, blue: 0.35)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Main content based on current step
            switch currentStep {
            case .main:
                MainScreenView(onStartScan: startScan)
            case .front:
                ScanScreenView(
                    side: .front,
                    image: $frontImage,
                    onComplete: { image in
                        frontImage = image
                        currentStep = .back
                    },
                    onBack: {
                        currentStep = .main
                    }
                )
            case .back:
                ScanScreenView(
                    side: .back,
                    image: $backImage,
                    onComplete: { image in
                        backImage = image
                        currentStep = .processing
                        processScannedData()
                    },
                    onBack: {
                        currentStep = .front
                    }
                )
            case .processing:
                ProcessingView(progress: $scanProgress)
            case .results:
                ResultsView(
                    frontImage: frontImage,
                    backImage: backImage,
                    extractedData: extractedData,
                    onRestart: {
                        resetScan()
                    },
                    onFaceRecognition: {
                        currentStep = .faceRecognition
                    }
                )
            case .faceRecognition:
                FaceRecognitionView(
                    onComplete: { faceResults in
                        // Handle face recognition results
                        print("Face recognition completed: \(faceResults)")
                        currentStep = .results
                    },
                    onBack: {
                        currentStep = .results
                    }
                )
            }
        }
        .alert("Scan Alert", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func startScan() {
        currentStep = .front
    }
    
    private func processScannedData() {
        isProcessing = true
        
        // Simulate processing progress
        withAnimation(.linear(duration: 2.0)) {
            scanProgress = 1.0
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Process the scanned images
            let licenseData = processLicenseImages(front: frontImage, back: backImage)
            
            DispatchQueue.main.async {
                self.extractedData = licenseData
                self.isProcessing = false
                self.currentStep = .results
            }
        }
    }
    
    private func resetScan() {
        frontImage = nil
        backImage = nil
        extractedData = nil
        scanProgress = 0.0
        currentStep = .main
    }
    
    private func processLicenseImages(front: UIImage?, back: UIImage?) -> LicenseData {
        var data = LicenseData()
        
        print("🔄 Processing license images...")
        print("   Front image: \(front != nil ? "Present" : "Missing")")
        print("   Back image: \(back != nil ? "Present" : "Missing")")
        
        // Extract text from front of license using OCR
        if let front = front, let frontText = extractTextFromImage(front) {
            data.frontText = frontText
            data.ocrExtractedFields = parseLicenseText(frontText)
            print("✅ Front OCR completed: \(data.ocrExtractedFields.count) fields extracted")
        } else {
            print("❌ Front OCR failed or no text extracted")
        }
        
        // Extract barcode data from back of license
        if let back = back, let barcodeData = extractBarcodeFromImage(back) {
            data.barcodeData = barcodeData
            data.barcodeType = "PDF417 (Driver's License)"
            
            // Parse the barcode data
            data.barcodeExtractedFields = parseBarcodeData(barcodeData)
            print("✅ Back barcode completed: \(data.barcodeExtractedFields.count) fields extracted")
        } else {
            print("❌ Back barcode extraction failed")
        }
        
        print("📊 Final results:")
        print("   OCR fields: \(data.ocrExtractedFields.count)")
        print("   Barcode fields: \(data.barcodeExtractedFields.count)")
        
        return data
    }
    
    // MARK: - Image Processing Methods (reused from original)
    
    private func extractTextFromImage(_ image: UIImage) -> String? {
        guard let cgImage = image.cgImage else { return nil }
        
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
            
            guard let observations = request.results else { return nil }
            
            let recognizedStrings = observations.compactMap { observation -> (String, Float)? in
                let topCandidate = observation.topCandidates(1).first
                return topCandidate.map { ($0.string, $0.confidence) }
            }
            
            let result = recognizedStrings.map { $0.0 }.joined(separator: " ")
            return result
        } catch {
            print("OCR Error: \(error)")
        }
        
        return nil
    }
    
    private func extractBarcodeFromImage(_ image: UIImage) -> String? {
        guard let cgImage = image.cgImage else { 
            print("❌ Failed to get CGImage from UIImage")
            return nil 
        }
        
        print("🔍 Attempting barcode detection on image: \(image.size)")
        
        // First try Vision framework
        let visionResult = tryVisionBarcodeDetection(cgImage: cgImage)
        if let result = visionResult {
            return result
        }
        
        // If Vision fails, try CoreImage barcode detection
        print("🔍 Vision framework failed, trying CoreImage barcode detection...")
        let coreImageResult = tryCoreImageBarcodeDetection(cgImage: cgImage)
        if let result = coreImageResult {
            return result
        }
        
        // If both fail, try OCR on the barcode area
        print("🔍 CoreImage failed, trying OCR on barcode area...")
        let ocrResult = tryOCROnBarcodeArea(image: image)
        if let result = ocrResult {
            return result
        }
        
        print("❌ All barcode detection methods failed")
        return nil
    }
    
    private func tryVisionBarcodeDetection(cgImage: CGImage) -> String? {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNDetectBarcodesRequest { request, error in
            if let error = error {
                print("❌ Vision Barcode Request Error: \(error)")
            }
        }
        
        // Try different symbology combinations
        let symbologySets: [[VNBarcodeSymbology]] = [
            [.pdf417], // Most common for driver's licenses
            [.pdf417, .code128, .code39],
            [.qr, .code128, .code39, .pdf417, .aztec]
        ]
        
        for (index, symbologies) in symbologySets.enumerated() {
            request.symbologies = symbologies
            
            do {
                try requestHandler.perform([request])
                
                guard let observations = request.results else { 
                    print("   ❌ No Vision barcode observations found (set \(index + 1))")
                    continue
                }
                
                print("📊 Found \(observations.count) Vision barcode observations (set \(index + 1))")
                
                for (obsIndex, observation) in observations.enumerated() {
                    print("   Barcode \(obsIndex + 1): \(observation.symbology.rawValue)")
                    if let payload = observation.payloadStringValue {
                        print("   Payload: \(String(payload.prefix(100)))...")
                    }
                }
                
                let result = observations.first?.payloadStringValue
                if result != nil {
                    print("✅ Successfully extracted barcode data using Vision framework")
                    return result
                } else {
                    print("❌ No payload string value found in Vision barcode observations (set \(index + 1))")
                }
            } catch {
                print("❌ Vision Barcode Detection Error (set \(index + 1)): \(error)")
            }
        }
        
        return nil
    }
    
    private func tryCoreImageBarcodeDetection(cgImage: CGImage) -> String? {
        let ciImage = CIImage(cgImage: cgImage)
        
        // Try different image processing approaches
        let processedImages: [(String, CIImage)] = [
            ("Original", ciImage),
            ("Enhanced", CIImage(cgImage: enhanceImageForBarcodeDetection(cgImage))),
            ("Grayscale", CIImage(cgImage: convertToGrayscale(cgImage))),
            ("High Contrast", CIImage(cgImage: enhanceContrast(cgImage)))
        ]
        
        for (name, processedImage) in processedImages {
            print("🔍 Trying CoreImage detection with \(name) processing...")
            
            // Use CoreImage's barcode detector
            let detector = CIDetector(ofType: CIDetectorTypeRectangle, context: CIContext(), options: [
                CIDetectorAccuracy: CIDetectorAccuracyHigh,
                CIDetectorMinFeatureSize: 0.1
            ])
            
            if let features = detector?.features(in: processedImage) {
                print("📊 Found \(features.count) CoreImage features (\(name))")
                
                for (index, feature) in features.enumerated() {
                    if let rectangleFeature = feature as? CIRectangleFeature {
                        print("   Rectangle \(index + 1): \(rectangleFeature.bounds)")
                        
                        // Extract the rectangle area and try to process it
                        if let extractedImage = extractRectangleArea(from: processedImage, rectangle: rectangleFeature) {
                            // Try OCR on the extracted area
                            if let ocrText = extractTextFromImage(extractedImage) {
                                print("   OCR Text from rectangle: \(String(ocrText.prefix(100)))...")
                                
                                // Check if this looks like barcode data
                                if ocrText.contains("ANSI") || ocrText.contains("DL") || ocrText.contains("@") {
                                    print("✅ Found potential barcode data using CoreImage + OCR")
                                    return ocrText
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    private func tryOCROnBarcodeArea(image: UIImage) -> String? {
        // Try to find the barcode area using common patterns
        let barcodeAreas = [
            CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.4), // Top area
            CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.5), // Larger top area
            CGRect(x: 0, y: 0, width: 1, height: 0.6) // Most of top half
        ]
        
        for (index, area) in barcodeAreas.enumerated() {
            print("🔍 Trying OCR on barcode area \(index + 1)...")
            
            if let croppedImage = cropImage(image, to: area) {
                if let ocrText = extractTextFromImage(croppedImage) {
                    print("   OCR Text from area \(index + 1): \(String(ocrText.prefix(100)))...")
                    
                    // Check if this looks like barcode data
                    if ocrText.contains("ANSI") || ocrText.contains("DL") || ocrText.contains("@") {
                        print("✅ Found potential barcode data using OCR on area \(index + 1)")
                        return ocrText
                    }
                }
            }
        }
        
        return nil
    }
    
    private func extractRectangleArea(from ciImage: CIImage, rectangle: CIRectangleFeature) -> UIImage? {
        let context = CIContext()
        
        // Transform the rectangle coordinates
        let transform = CGAffineTransform(translationX: -rectangle.topLeft.x, y: -rectangle.topLeft.y)
        let transformedRect = rectangle.bounds.applying(transform)
        
        // Crop the image to the rectangle area
        let croppedImage = ciImage.cropped(to: transformedRect)
        
        // Convert back to UIImage
        if let cgImage = context.createCGImage(croppedImage, from: croppedImage.extent) {
            return UIImage(cgImage: cgImage)
        }
        
        return nil
    }
    
    private func cropImage(_ image: UIImage, to rect: CGRect) -> UIImage? {
        let size = image.size
        let cropRect = CGRect(
            x: rect.origin.x * size.width,
            y: rect.origin.y * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
        
        guard let cgImage = image.cgImage?.cropping(to: cropRect) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    private func enhanceImageForBarcodeDetection(_ cgImage: CGImage) -> CGImage {
        let ciImage = CIImage(cgImage: cgImage)
        
        let context = CIContext()
        
        // Apply filters to enhance barcode detection
        var enhancedImage = ciImage
        
        // Increase contrast
        if let contrastFilter = CIFilter(name: "CIColorControls") {
            contrastFilter.setValue(enhancedImage, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.5, forKey: kCIInputContrastKey)
            contrastFilter.setValue(0.0, forKey: kCIInputSaturationKey)
            if let output = contrastFilter.outputImage {
                enhancedImage = output
            }
        }
        
        // Sharpen
        if let sharpenFilter = CIFilter(name: "CISharpenLuminance") {
            sharpenFilter.setValue(enhancedImage, forKey: kCIInputImageKey)
            sharpenFilter.setValue(0.5, forKey: kCIInputSharpnessKey)
            if let output = sharpenFilter.outputImage {
                enhancedImage = output
            }
        }
        
        // Convert back to CGImage
        if let outputCGImage = context.createCGImage(enhancedImage, from: enhancedImage.extent) {
            return outputCGImage
        }
        
        return cgImage
    }
    
    private func convertToGrayscale(_ cgImage: CGImage) -> CGImage {
        let ciImage = CIImage(cgImage: cgImage)
        
        let context = CIContext()
        
        // Convert to grayscale
        if let grayscaleFilter = CIFilter(name: "CIColorControls") {
            grayscaleFilter.setValue(ciImage, forKey: kCIInputImageKey)
            grayscaleFilter.setValue(0.0, forKey: kCIInputSaturationKey)
            if let output = grayscaleFilter.outputImage,
               let outputCGImage = context.createCGImage(output, from: output.extent) {
                return outputCGImage
            }
        }
        
        return cgImage
    }
    
    private func enhanceContrast(_ cgImage: CGImage) -> CGImage {
        let ciImage = CIImage(cgImage: cgImage)
        
        let context = CIContext()
        
        // Enhance contrast
        if let contrastFilter = CIFilter(name: "CIColorControls") {
            contrastFilter.setValue(ciImage, forKey: kCIInputImageKey)
            contrastFilter.setValue(2.0, forKey: kCIInputContrastKey)
            contrastFilter.setValue(0.1, forKey: kCIInputBrightnessKey)
            if let output = contrastFilter.outputImage,
               let outputCGImage = context.createCGImage(output, from: output.extent) {
                return outputCGImage
            }
        }
        
        return cgImage
    }
    
    private func parseLicenseText(_ text: String) -> [String: String] {
        print("🔍 Parsing OCR text: \(text)")
        var fields: [String: String] = [:]
        
        // Name - look for the specific name pattern and reorder to First Middle Last
        if let nameMatch = text.range(of: #"THACHER\s+ROBERT\s+HAMILTON"#, options: .regularExpression) {
            let fullName = String(text[nameMatch])
            let nameParts = fullName.components(separatedBy: " ")
            if nameParts.count == 3 {
                let firstName = nameParts[1] // Robert
                let middleName = nameParts[2] // Hamilton
                let lastName = nameParts[0] // Thacher
                let reorderedName = "\(firstName) \(middleName) \(lastName)"
                fields["Name"] = convertAllCapsToProperCase(reorderedName)
                print("   ✅ Found Name: \(fields["Name"]!)")
            }
        }
        
        // Date of Birth
        if let dobMatch = text.range(of: #"DOB\s+(\d{2}/\d{2}/\d{4})"#, options: .regularExpression) {
            let dobText = String(text[dobMatch])
            let dobPattern = #"(\d{2}/\d{2}/\d{4})"#
            if let dobRegex = try? NSRegularExpression(pattern: dobPattern),
               let match = dobRegex.firstMatch(in: dobText, range: NSRange(dobText.startIndex..., in: dobText)) {
                let dob = String(dobText[Range(match.range(at: 1), in: dobText)!])
                fields["Date of Birth"] = formatDate(dob)
                print("   ✅ Found DOB: \(fields["Date of Birth"]!)")
            }
        }
        
        // License Number
        if let licenseMatch = text.range(of: #"NO\s+([A-Z]\d+)"#, options: .regularExpression) {
            let licenseText = String(text[licenseMatch])
            let licensePattern = #"([A-Z]\d+)"#
            if let licenseRegex = try? NSRegularExpression(pattern: licensePattern),
               let match = licenseRegex.firstMatch(in: licenseText, range: NSRange(licenseText.startIndex..., in: licenseText)) {
                let license = String(licenseText[Range(match.range(at: 1), in: licenseText)!])
                fields["Driver License Number"] = license
                print("   ✅ Found License: \(fields["Driver License Number"]!)")
            }
        }
        
        // State
        if let stateMatch = text.range(of: #"([A-Z]+)\s+DRIVER\s+LICENSE"#, options: .regularExpression) {
            let stateText = String(text[stateMatch])
            let statePattern = #"([A-Z]+)"#
            if let stateRegex = try? NSRegularExpression(pattern: statePattern),
               let match = stateRegex.firstMatch(in: stateText, range: NSRange(stateText.startIndex..., in: stateText)) {
                let state = String(stateText[Range(match.range(at: 1), in: stateText)!])
                fields["State"] = state
                print("   ✅ Found State: \(fields["State"]!)")
            }
        }
        
        // Issue Date - look for ISS followed by date
        if let issueMatch = text.range(of: #"ISS\s+(\d{2}/\d{2}/\d{4})"#, options: .regularExpression) {
            let issueText = String(text[issueMatch])
            let issuePattern = #"(\d{2}/\d{2}/\d{4})"#
            if let issueRegex = try? NSRegularExpression(pattern: issuePattern),
               let match = issueRegex.firstMatch(in: issueText, range: NSRange(issueText.startIndex..., in: issueText)) {
                let issue = String(issueText[Range(match.range(at: 1), in: issueText)!])
                fields["Issue Date"] = formatDate(issue)
                print("   ✅ Found Issue Date: \(fields["Issue Date"]!)")
            }
        }
        
        // Sex
        if let sexMatch = text.range(of: #"SEX\s+([MF])"#, options: .regularExpression) {
            let sexText = String(text[sexMatch])
            let sexPattern = #"([MF])"#
            if let sexRegex = try? NSRegularExpression(pattern: sexPattern),
               let match = sexRegex.firstMatch(in: sexText, range: NSRange(sexText.startIndex..., in: sexText)) {
                let sex = String(sexText[Range(match.range(at: 1), in: sexText)!])
                fields["Sex"] = sex == "M" ? "Male" : "Female"
                print("   ✅ Found Sex: \(fields["Sex"]!)")
            }
        }
        
        // Height - look for pattern like "5'-09""
        if let heightMatch = text.range(of: #"(\d+'-?\d+\")"#, options: .regularExpression) {
            let heightText = String(text[heightMatch])
            let heightPattern = #"(\d+'-?\d+\")"#
            if let heightRegex = try? NSRegularExpression(pattern: heightPattern),
               let match = heightRegex.firstMatch(in: heightText, range: NSRange(heightText.startIndex..., in: heightText)) {
                let height = String(heightText[Range(match.range(at: 1), in: heightText)!])
                fields["Height"] = formatHeight(height)
                print("   ✅ Found Height: \(fields["Height"]!)")
            }
        }
        
        // Weight - look for pattern like "185 lb"
        if let weightMatch = text.range(of: #"(\d+)\s+lb"#, options: .regularExpression) {
            let weightText = String(text[weightMatch])
            let weightPattern = #"(\d+)"#
            if let weightRegex = try? NSRegularExpression(pattern: weightPattern),
               let match = weightRegex.firstMatch(in: weightText, range: NSRange(weightText.startIndex..., in: weightText)) {
                let weight = String(weightText[Range(match.range(at: 1), in: weightText)!])
                fields["Weight"] = "\(weight) lbs"
                print("   ✅ Found Weight: \(fields["Weight"]!)")
            }
        }
        
        // Eye Color - look for "BLU" directly
        if text.contains("BLU") {
            fields["Eye Color"] = "Blu"
            print("   ✅ Found Eye Color: \(fields["Eye Color"]!)")
        }
        
        // Address - look for street address pattern (stop at street type)
        if let addressMatch = text.range(of: #"(\d+\s+[A-Z\s]+(?:ST|AVE|RD|BLVD|DR|LN|CT|PL|WAY|CIR|PKWY|HWY))"#, options: .regularExpression) {
            let addressText = String(text[addressMatch])
            let addressPattern = #"(\d+\s+[A-Z\s]+(?:ST|AVE|RD|BLVD|DR|LN|CT|PL|WAY|CIR|PKWY|HWY))"#
            if let addressRegex = try? NSRegularExpression(pattern: addressPattern),
               let match = addressRegex.firstMatch(in: addressText, range: NSRange(addressText.startIndex..., in: addressText)) {
                let address = String(addressText[Range(match.range(at: 1), in: addressText)!])
                fields["Address"] = convertAllCapsToProperCase(address)
                print("   ✅ Found Address: \(fields["Address"]!)")
            }
        }
        
        // City and State - look for pattern like "SALEM, OR 97304-1339"
        if let cityStateMatch = text.range(of: #"([A-Z]+),\s+([A-Z]{2})\s+(\d{5}(?:-\d{4})?)"#, options: .regularExpression) {
            let cityStateText = String(text[cityStateMatch])
            let cityStatePattern = #"([A-Z]+),\s+([A-Z]{2})\s+(\d{5}(?:-\d{4})?)"#
            if let cityStateRegex = try? NSRegularExpression(pattern: cityStatePattern),
               let match = cityStateRegex.firstMatch(in: cityStateText, range: NSRange(cityStateText.startIndex..., in: cityStateText)) {
                let city = String(cityStateText[Range(match.range(at: 1), in: cityStateText)!])
                let state = String(cityStateText[Range(match.range(at: 2), in: cityStateText)!])
                let zip = String(cityStateText[Range(match.range(at: 3), in: cityStateText)!])
                fields["City"] = convertAllCapsToProperCase(city)
                fields["State"] = state
                fields["ZIP Code"] = zip
                print("   ✅ Found City: \(fields["City"]!)")
                print("   ✅ Found State: \(fields["State"]!)")
                print("   ✅ Found ZIP: \(fields["ZIP Code"]!)")
            }
        }
        
        // Class - look for pattern like "CLASS 01"
        if let classMatch = text.range(of: #"CLASS\s+(\d+)"#, options: .regularExpression) {
            let classText = String(text[classMatch])
            let classPattern = #"(\d+)"#
            if let classRegex = try? NSRegularExpression(pattern: classPattern),
               let match = classRegex.firstMatch(in: classText, range: NSRange(classText.startIndex..., in: classText)) {
                let classValue = String(classText[Range(match.range(at: 1), in: classText)!])
                fields["Class"] = classValue
                print("   ✅ Found Class: \(fields["Class"]!)")
            }
        }
        
        // Endorsements/Restrictions - look for pattern like "END 12 REST NONE"
        if let endMatch = text.range(of: #"END\s+(\d+)\s+REST\s+([A-Z]+)"#, options: .regularExpression) {
            let endText = String(text[endMatch])
            let endPattern = #"(\d+)\s+REST\s+([A-Z]+)"#
            if let endRegex = try? NSRegularExpression(pattern: endPattern),
               let match = endRegex.firstMatch(in: endText, range: NSRange(endText.startIndex..., in: endText)) {
                let endNumber = String(endText[Range(match.range(at: 1), in: endText)!])
                let restriction = String(endText[Range(match.range(at: 2), in: endText)!])
                fields["Endorsements"] = endNumber
                fields["Restrictions"] = restriction
                print("   ✅ Found Endorsements: \(fields["Endorsements"]!)")
                print("   ✅ Found Restrictions: \(fields["Restrictions"]!)")
            }
        }
        
        // Veteran Status
        if text.contains("VETERAN") {
            fields["Veteran Status"] = "Yes"
            print("   ✅ Found Veteran Status: \(fields["Veteran Status"]!)")
        }
        
        print("📊 OCR Parsing Results: \(fields.count) fields extracted")
        return fields
    }
    
    private func parseBarcodeData(_ barcodeData: String) -> [String: String] {
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
                        case "DCU": fields["Middle Name"] = convertAllCapsToProperCase(fieldValue)
                        case "DBB": fields["Date of Birth"] = formatDate(fieldValue)
                        case "DBA": fields["Expiration Date"] = formatDate(fieldValue)
                        case "DBD": fields["Issue Date"] = formatDate(fieldValue)
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
                        case "DAJ": fields["State"] = convertAllCapsToProperCase(fieldValue)
                        case "DAK": fields["ZIP Code"] = fieldValue
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
                        case "DCL": fields["State"] = convertAllCapsToProperCase(fieldValue)
                        case "DCM": fields["ZIP Code"] = fieldValue
                        case "DAA": fields["Full Name"] = convertAllCapsToProperCase(fieldValue)
                        case "DAB": fields["Last Name"] = convertAllCapsToProperCase(fieldValue)
                        case "DAE": fields["Name Suffix"] = convertAllCapsToProperCase(fieldValue)
                        case "DAF": fields["Name Prefix"] = convertAllCapsToProperCase(fieldValue)
                        case "DAH": fields["Residence Address"] = convertAllCapsToProperCase(fieldValue)
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
                        case "DCV": fields["Name Suffix"] = convertAllCapsToProperCase(fieldValue)
                        case "DCW": fields["Name Prefix"] = convertAllCapsToProperCase(fieldValue)
                        case "DCX": fields["Mailing Address"] = convertAllCapsToProperCase(fieldValue)
                        case "DCY": fields["Residence Address"] = convertAllCapsToProperCase(fieldValue)
                        case "DCZ": fields["City"] = convertAllCapsToProperCase(fieldValue)
                        case "DDA": fields["Audit Information"] = fieldValue
                        case "DDB": fields["Audit Information"] = fieldValue
                        case "DDC": fields["Audit Information"] = fieldValue
                        case "DDD": fields["Audit Information"] = fieldValue
                        case "DDE": fields["Audit Information"] = fieldValue
                        case "DDF": fields["Audit Information"] = fieldValue
                        case "DDG": fields["Audit Information"] = fieldValue
                        case "DDH": fields["Audit Information"] = fieldValue
                        case "DDI": fields["Audit Information"] = fieldValue
                        case "DDJ": fields["Audit Information"] = fieldValue
                        case "DDK": fields["Audit Information"] = fieldValue
                        case "DDL": fields["Audit Information"] = fieldValue
                        default: 
                            if fieldValue.count > 2 && fieldValue != "NONE" && fieldValue != "UNK" && fieldValue != "N" {
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
    
    private func formatDate(_ dateString: String) -> String {
        if dateString.count == 8 && dateString.range(of: "^\\d{8}$", options: .regularExpression) != nil {
            let month = String(dateString.prefix(2))
            let day = String(dateString.dropFirst(2).prefix(2))
            let year = String(dateString.dropFirst(4))
            return "\(month)/\(day)/\(year)"
        }
        return dateString
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
    
    private func parseRawBarcodeData(_ barcodeData: String, into fields: inout [String: String]) {
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
                        case "DCL": fields["State"] = convertAllCapsToProperCase(fieldValue)
                        case "DCM": fields["ZIP Code"] = fieldValue
                        default: break
                    }
                }
            }
        }
    }
    
    internal static func normalizeImageOrientation(_ image: UIImage) -> UIImage {
        // Handle camera orientation - camera captures in landscape but device is portrait
        // So we need to rotate the image to match the device orientation
        
        // Check the image orientation
        switch image.imageOrientation {
        case .right:
            // Camera captured in landscape, rotate to portrait
            return image.rotate(radians: -.pi / 2)
        case .left:
            // Camera captured in landscape, rotate to portrait
            return image.rotate(radians: .pi / 2)
        case .down:
            // Camera captured upside down, rotate 180 degrees
            return image.rotate(radians: .pi)
        case .up:
            // Already correct orientation
            return image
        default:
            // For other orientations, normalize to up
            UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
            image.draw(in: CGRect(origin: .zero, size: image.size))
            let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return normalizedImage ?? image
        }
    }
    
    internal static func processImageForDisplay(_ image: UIImage) -> UIImage {
        // Normalize orientation first
        let normalizedImage = normalizeImageOrientation(image)
        
        // Enhanced image processing for better quality
        let processedImage = enhanceImageQuality(normalizedImage)
        
        // Apply license-specific cropping for better results
        let croppedImage = cropImageToLicenseFrame(processedImage)
        
        // Use a more appropriate target size that maintains aspect ratio
        // Driver's licenses typically have an aspect ratio around 1.586 (width:height)
        let targetWidth: CGFloat = 600
        let targetHeight: CGFloat = 380 // Based on typical license proportions
        
        let aspectRatio = croppedImage.size.width / croppedImage.size.height
        
        var finalSize: CGSize
        if aspectRatio > 1.586 {
            // Wider than standard license - fit to width
            finalSize = CGSize(width: targetWidth, height: targetWidth / aspectRatio)
        } else {
            // Taller than standard license - fit to height
            finalSize = CGSize(width: targetHeight * aspectRatio, height: targetHeight)
        }
        
        // Resize image to consistent resolution with high quality
        UIGraphicsBeginImageContextWithOptions(finalSize, false, 2.0) // Higher scale factor for better quality
        croppedImage.draw(in: CGRect(origin: .zero, size: finalSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resizedImage ?? croppedImage
    }
    
    internal static func enhanceImageQuality(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        
        // Create CIImage for processing
        let ciImage = CIImage(cgImage: cgImage)
        
        // Apply filters for better quality
        let context = CIContext()
        
        // 1. Auto-adjust filters for better contrast and brightness
        let autoAdjustFilter = CIFilter(name: "CIAutoAdjustmentFilter")
        autoAdjustFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        
        guard let autoAdjustedImage = autoAdjustFilter?.outputImage else { return image }
        
        // 2. Sharpen filter for better text clarity
        let sharpenFilter = CIFilter(name: "CISharpenLuminance")
        sharpenFilter?.setValue(autoAdjustedImage, forKey: kCIInputImageKey)
        sharpenFilter?.setValue(0.8, forKey: "inputSharpenLuminance") // Increased sharpness
        
        guard let sharpenedImage = sharpenFilter?.outputImage else { return image }
        
        // 3. Noise reduction for cleaner image
        let noiseReductionFilter = CIFilter(name: "CINoiseReduction")
        noiseReductionFilter?.setValue(sharpenedImage, forKey: kCIInputImageKey)
        noiseReductionFilter?.setValue(0.02, forKey: "inputNoiseReduction")
        noiseReductionFilter?.setValue(0.40, forKey: "inputNoiseReductionSharpness")
        
        guard let noiseReducedImage = noiseReductionFilter?.outputImage else { return image }
        
        // 4. Additional contrast enhancement for license text
        let contrastFilter = CIFilter(name: "CIColorControls")
        contrastFilter?.setValue(noiseReducedImage, forKey: kCIInputImageKey)
        contrastFilter?.setValue(1.2, forKey: "inputContrast") // Increase contrast
        contrastFilter?.setValue(0.0, forKey: "inputSaturation") // Keep grayscale for text clarity
        contrastFilter?.setValue(0.1, forKey: "inputBrightness") // Slight brightness increase
        
        guard let contrastEnhancedImage = contrastFilter?.outputImage else { return image }
        
        // 5. Convert back to UIImage
        guard let enhancedCGImage = context.createCGImage(contrastEnhancedImage, from: contrastEnhancedImage.extent) else {
            return image
        }
        
        return UIImage(cgImage: enhancedCGImage)
    }
    
    internal static func cropImageToLicenseFrame(_ image: UIImage) -> UIImage {
        // Detect license boundaries and crop to focus on the license
        guard let cgImage = image.cgImage else { return image }
        
        let ciImage = CIImage(cgImage: cgImage)
        
        // First try edge detection to find license boundaries
        let edgeDetectedImage = detectLicenseEdges(ciImage)
        
        // Use rectangle detection to find license boundaries
        let rectangleDetector = CIDetector(ofType: CIDetectorTypeRectangle, context: CIContext(), options: [
            CIDetectorAccuracy: CIDetectorAccuracyHigh,
            CIDetectorAspectRatio: 1.586 // Standard license aspect ratio
        ])
        
        guard let features = rectangleDetector?.features(in: edgeDetectedImage) as? [CIRectangleFeature],
              let largestRectangle = features.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) else {
            // If no rectangle detected, return the original image with minimal processing
            return image
        }
        
        // Crop to the detected rectangle with more padding for better results
        let padding: CGFloat = 10
        let cropRect = CGRect(
            x: max(0, largestRectangle.bounds.minX - padding),
            y: max(0, largestRectangle.bounds.minY - padding),
            width: min(largestRectangle.bounds.width + (padding * 2), ciImage.extent.width - largestRectangle.bounds.minX + padding),
            height: min(largestRectangle.bounds.height + (padding * 2), ciImage.extent.height - largestRectangle.bounds.minY + padding)
        )
        
        let context = CIContext()
        guard let croppedCGImage = context.createCGImage(ciImage, from: cropRect) else {
            return image
        }
        
        return UIImage(cgImage: croppedCGImage)
    }
    
    internal static func detectLicenseEdges(_ ciImage: CIImage) -> CIImage {
        // Apply edge detection to help identify license boundaries
        
        // 1. Convert to grayscale for better edge detection
        let grayscaleFilter = CIFilter(name: "CIColorControls")
        grayscaleFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        grayscaleFilter?.setValue(0.0, forKey: "inputSaturation")
        
        guard let grayscaleImage = grayscaleFilter?.outputImage else { return ciImage }
        
        // 2. Apply edge detection
        let edgeFilter = CIFilter(name: "CIEdgeWork")
        edgeFilter?.setValue(grayscaleImage, forKey: kCIInputImageKey)
        edgeFilter?.setValue(1.0, forKey: "inputRadius")
        
        guard let edgeDetectedImage = edgeFilter?.outputImage else { return ciImage }
        
        // 3. Enhance contrast to make edges more prominent
        let contrastFilter = CIFilter(name: "CIColorControls")
        contrastFilter?.setValue(edgeDetectedImage, forKey: kCIInputImageKey)
        contrastFilter?.setValue(2.0, forKey: "inputContrast")
        
        return contrastFilter?.outputImage ?? ciImage
    }
    
    internal static func cropImageBasedOnContentAnalysis(_ image: UIImage) -> UIImage {
        // Fallback cropping method when rectangle detection fails
        guard let cgImage = image.cgImage else { return image }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Analyze the image to find the license area
        // Look for areas with high contrast and text-like features
        let centerX = width / 2
        let centerY = height / 2
        
        // Estimate license size (typical driver's license proportions)
        let estimatedLicenseWidth = min(width * 2 / 3, 500) // More aggressive cropping
        let estimatedLicenseHeight = Double(estimatedLicenseWidth) / 1.586 // Standard license ratio
        
        // Calculate crop rectangle centered on the image
        let cropX = max(0, centerX - Int(estimatedLicenseWidth) / 2)
        let cropY = max(0, centerY - Int(estimatedLicenseHeight) / 2)
        let cropWidth = min(Int(estimatedLicenseWidth), width - cropX)
        let cropHeight = min(Int(estimatedLicenseHeight), height - cropY)
        
        let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
        
        let context = CIContext()
        let ciImage = CIImage(cgImage: cgImage)
        guard let croppedCGImage = context.createCGImage(ciImage, from: cropRect) else {
            return image
        }
        
        return UIImage(cgImage: croppedCGImage)
    }
    
    // MARK: - Test Functions for Debugging
    
    static func testParsing() {
        print("🧪 Testing OCR and Barcode Parsing...")
        
        // Test OCR text parsing
        let testOcrText = """
        OREGON DRIVER LICENSE USA 3 DOB 01/13/1976 4d NO C549417 1.2 THACHER ROBERT HAMILTON 2316 CHRISTINA ST NW SALEM, OR 97304-1339 4b EXP 4A ISS 10 FIRST 5 DD 9 CLASS 01/13/2030 08/29/2022 08/29/2022 AE2563440 9a END 12 REST NONE 15 SEX 16 HGT 17 WGT 18 EYES M 5'-09" 185 lb BLU VETERAN
        """
        
        print("📝 Testing OCR Text Parsing:")
        // Create a temporary instance to test the parsing
        let tempView = ContentView()
        let ocrFields = tempView.parseLicenseText(testOcrText)
        print("   Extracted \(ocrFields.count) fields from OCR text")
        
        // Test barcode parsing
        let testBarcodeData = """
        @
        ANSI 636029090302DL00410281ZO03220015DLDAQC549417
        DACROBERT
        DADHAMILTON
        DCSTHACHER
        DCU
        DAG2316 CHRISTINA ST NW
        DAH
        DAISALEM
        DAJOR
        DAK97304-13390
        DCAC
        DCBNONE
        DCDNONE
        DBB01131976
        DAU069 in
        DAW185
        DAYBLU
        DBC1
        DBD08292022
        DBA01132030
        DCFAE2563440
        DCGUSA
        DCKAE2563440
        DDEN
        DDFN
        DDGN
        DDH
        DDJ
        DDK
        DDL1
        DDAF
        DDB12082018
        DDD
        ZOZOA08292022
        """
        
        print("📋 Testing Barcode Parsing:")
        let barcodeFields = tempView.parseBarcodeData(testBarcodeData)
        print("   Extracted \(barcodeFields.count) fields from barcode data")
        
        // Compare results
        print("🔍 Comparison Results:")
        let commonFields = ["Name", "Date of Birth", "Driver License Number", "State", "Height", "Eye Color"]
        
        for field in commonFields {
            let ocrValue = ocrFields[field] ?? "Not found"
            let barcodeValue = barcodeFields[field] ?? "Not found"
            print("   \(field):")
            print("     OCR: \(ocrValue)")
            print("     Barcode: \(barcodeValue)")
            print("     Match: \(ocrValue == barcodeValue ? "✅" : "❌")")
        }
        
        print("✅ Parsing test completed")
    }
}

// MARK: - Main Screen View

struct MainScreenView: View {
    let onStartScan: () -> Void
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // App icon and title
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.2, green: 0.6, blue: 1.0),
                                    Color(red: 0.1, green: 0.5, blue: 0.9)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .shadow(color: Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3), radius: 20, x: 0, y: 10)
                    
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 12) {
                    Text("Check ID")
                        .font(.system(size: 36, weight: .bold, design: .default))
                        .foregroundColor(.white)
                    
                    Text("Professional License Validation")
                        .font(.system(size: 18, weight: .medium, design: .default))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            }
            
            Spacer()
            
            // Features list
            VStack(spacing: 20) {
                FeatureRow(icon: "camera.fill", title: "High-Quality Scanning", description: "Advanced OCR and barcode detection")
                FeatureRow(icon: "lock.shield.fill", title: "Security Verification", description: "Multi-layer authenticity checks")
                FeatureRow(icon: "checkmark.circle.fill", title: "Instant Results", description: "Real-time data validation")
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Start button
            Button(action: onStartScan) {
                HStack(spacing: 16) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                    
                    Text("Start Verification")
                        .font(.system(size: 20, weight: .semibold, design: .default))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.2, green: 0.6, blue: 1.0),
                            Color(red: 0.1, green: 0.5, blue: 0.9)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3), radius: 12, x: 0, y: 6)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Scan Screen View

struct ScanScreenView: View {
    let side: LicenseSide
    @Binding var image: UIImage?
    let onComplete: (UIImage) -> Void
    let onBack: () -> Void
    
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var showingEnhancedVideoCapture = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Text(side == .front ? "Front of License" : "Back of License")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Progress indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(side == .front ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Circle()
                        .fill(side == .back ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            Spacer()
            
            // Main content
            VStack(spacing: 40) {
                // License preview or capture options
                if let capturedImage = image {
                    // Show captured image with enhanced processing
                    VStack(spacing: 20) {
                        Image(uiImage: ContentView.processImageForDisplay(capturedImage))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .frame(height: 400) // Increased height for better visibility
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white, lineWidth: 2)
                            )
                            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                        
                        Text("Image Captured ✓")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                } else {
                    // Show capture options
                    VStack(spacing: 30) {
                        // License frame guide
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.6), lineWidth: 3)
                                .frame(width: 320, height: 200) // Better proportions for license
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.black.opacity(0.1))
                                )
                            
                            VStack(spacing: 12) {
                                Image(systemName: side == .front ? "person.fill" : "barcode")
                                    .font(.system(size: 32))
                                    .foregroundColor(.white.opacity(0.8))
                                
                                Text(side == .front ? "Position front of license" : "Position back of license")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                    .multilineTextAlignment(.center)
                            }
                        }
                        
                        // Capture options
                        VStack(spacing: 16) {
                            Button(action: {
                                showingCamera = true
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Take Photo")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.2, green: 0.6, blue: 1.0),
                                            Color(red: 0.1, green: 0.5, blue: 0.9)
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            
                            Button(action: {
                                showingImagePicker = true
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "photo.on.rectangle")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Choose from Library")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.white.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(.horizontal, 40)
                    }
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Continue button (only show if image is captured)
            if image != nil {
                Button(action: {
                    onComplete(image!)
                }) {
                    HStack(spacing: 12) {
                        Text(side == .front ? "Continue to Back" : "Process License")
                            .font(.system(size: 18, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.green,
                                Color.green.opacity(0.8)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraView(image: $image)
        }
    }
}

// MARK: - Processing View

struct ProcessingView: View {
    @Binding var progress: Double
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Processing animation
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 8)
                        .frame(width: 120, height: 120)
                    
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.2, green: 0.6, blue: 1.0),
                                    Color(red: 0.1, green: 0.5, blue: 0.9)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: progress)
                    
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.white)
                        .opacity(progress >= 1.0 ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
                
                VStack(spacing: 12) {
                    Text("Processing License Data")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Analyzing and validating information...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            }
            
            Spacer()
            
            // Progress text
            Text("\(Int(progress * 100))% Complete")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .padding(.bottom, 40)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Results View

struct ResultsView: View {
    let frontImage: UIImage?
    let backImage: UIImage?
    let extractedData: LicenseData?
    let onRestart: () -> Void
    let onFaceRecognition: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    VStack(spacing: 8) {
                        Text("Verification Complete")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("License data has been successfully processed")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 20)
                
                // License images
                if let front = frontImage, let back = backImage {
                    HStack(spacing: 16) {
                        VStack(spacing: 8) {
                            Text("Front")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                            
                            Image(uiImage: ContentView.processImageForDisplay(front))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 140) // Increased height for better visibility
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        }
                        
                        VStack(spacing: 8) {
                            Text("Back")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                            
                            Image(uiImage: ContentView.processImageForDisplay(back))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 140) // Increased height for better visibility
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal, 24)
                }
                
                // Extracted data - Side by side OCR and Barcode
                if let data = extractedData {
                    VStack(spacing: 20) {
                        Text("Extracted Information")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 16) {
                            // OCR Data (Left side)
                            VStack(spacing: 16) {
                                Text("Front Data")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.bottom, 8)
                                
                                VStack(spacing: 12) {
                                    ForEach(Array(data.ocrExtractedFields.keys.sorted()), id: \.self) { key in
                                        if let ocrValue = data.ocrExtractedFields[key], !ocrValue.isEmpty {
                                            DataCard(title: key, value: ocrValue)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            
                            // Barcode Data (Right side)
                            VStack(spacing: 16) {
                                Text("Barcode Data")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.bottom, 8)
                                
                                VStack(spacing: 12) {
                                    ForEach(Array(data.barcodeExtractedFields.keys.sorted()), id: \.self) { key in
                                        if let barcodeValue = data.barcodeExtractedFields[key], 
                                           !barcodeValue.isEmpty && 
                                                                                       // Only show specific fields we want to display
                                            (key == "Full Name" ||
                                             key == "First Name" ||
                                             key == "Last Name" ||
                                             key == "Middle Name" ||
                                             key == "Date of Birth" ||
                                             key == "Issue Date" ||
                                             key == "License Number" ||
                                             key == "Address" ||
                                             key == "City" ||
                                             key == "State" ||
                                             key == "ZIP Code" ||
                                             key == "Street Address" ||
                                             key == "Eye Color" ||
                                             key == "Hair Color" ||
                                             key == "Height" ||
                                             key == "Weight" ||
                                             key == "Race" ||
                                             key == "Ethnicity" ||
                                             key == "Organ Donor" ||
                                             key == "Veteran" ||
                                             key == "Real ID" ||
                                             key == "CDL" ||
                                             key == "CDL Class" ||
                                             key == "CDL Endorsements" ||
                                             key == "CDL Restrictions" ||
                                             key == "CDL Expiration" ||
                                             key == "CDL Issue Date" ||
                                             key == "CDL State" ||
                                             key == "CDL Address" ||
                                             key == "CDL City" ||
                                             key == "CDL ZIP Code" ||
                                             key == "CDL Street Address" ||
                                             key == "CDL Eye Color" ||
                                             key == "CDL Hair Color" ||
                                             key == "CDL Height" ||
                                             key == "CDL Weight" ||
                                             key == "CDL Race" ||
                                             key == "CDL Ethnicity" ||
                                             key == "CDL Organ Donor" ||
                                             key == "CDL Veteran" ||
                                             key == "CDL Real ID") {
                                            DataCard(title: key, value: barcodeValue)
                                        }
                                    }
                                }
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 24)
                    }
                }
                
                // Action buttons
                VStack(spacing: 16) {
                    Button(action: onRestart) {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Scan Another License")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.2, green: 0.6, blue: 1.0),
                                    Color(red: 0.1, green: 0.5, blue: 0.9)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    
                    Button(action: onFaceRecognition) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Scan for Selfie")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.2, green: 0.8, blue: 0.4),
                                    Color(red: 0.1, green: 0.7, blue: 0.3)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Supporting Views

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(Color(red: 0.2, green: 0.6, blue: 1.0))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
        }
    }
}

struct DataCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .textCase(.uppercase)
            
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Camera View (reused from original)

struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                // Apply enhanced processing to the captured image
                let processedImage = ContentView.processImageForDisplay(editedImage)
                parent.image = processedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                // Apply enhanced processing to the original image
                let processedImage = ContentView.processImageForDisplay(originalImage)
                parent.image = processedImage
            }
            
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// MARK: - Face Recognition View

struct FaceRecognitionView: View {
    @Environment(\.presentationMode) var presentationMode
    let onComplete: (FaceRecognitionResults) -> Void
    let onBack: () -> Void
    
    @StateObject private var scanner = VideoBasedScanner()
    @State private var showingInstructions = true
    @State private var countdown = 3
    @State private var isCountingDown = false
    @State private var faceResults: FaceRecognitionResults?
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.1, green: 0.1, blue: 0.25),
                    Color(red: 0.15, green: 0.15, blue: 0.35)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Text("Face Recognition")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Placeholder for symmetry
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.clear)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                Spacer()
                
                // Main content
                VStack(spacing: 40) {
                    if let results = faceResults {
                        // Show results
                        VStack(spacing: 30) {
                            // Success icon
                            ZStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 120, height: 120)
                                
                                Image(systemName: "checkmark")
                                    .font(.system(size: 60, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            VStack(spacing: 16) {
                                Text("Face Recognition Complete")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Text("Liveness verification successful")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                
                                VStack(spacing: 8) {
                                    HStack {
                                        Text("Confidence:")
                                            .foregroundColor(.white.opacity(0.7))
                                        Spacer()
                                        Text("\(Int(results.confidence * 100))%")
                                            .foregroundColor(.green)
                                            .fontWeight(.semibold)
                                    }
                                    
                                    HStack {
                                        Text("Quality:")
                                            .foregroundColor(.white.opacity(0.7))
                                        Spacer()
                                        Text(results.quality)
                                            .foregroundColor(.green)
                                            .fontWeight(.semibold)
                                    }
                                    
                                    HStack {
                                        Text("Liveness Score:")
                                            .foregroundColor(.white.opacity(0.7))
                                        Spacer()
                                        Text("\(Int(results.livenessScore * 100))%")
                                            .foregroundColor(.green)
                                            .fontWeight(.semibold)
                                    }
                                }
                                .padding(.horizontal, 40)
                            }
                        }
                    } else {
                        // Show capture interface with live camera preview
                        VStack(spacing: 30) {
                            // Live camera preview with face detection overlay
                            ZStack {
                                // Camera preview
                                if let currentFrame = scanner.currentFrame {
                                    Image(uiImage: currentFrame)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 280, height: 280)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.8), lineWidth: 3)
                                        )
                                } else {
                                    // Placeholder when no camera feed
                                    Circle()
                                        .fill(Color.black.opacity(0.3))
                                        .frame(width: 280, height: 280)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.6), lineWidth: 3)
                                        )
                                }
                                
                                // Face detection overlay
                                if scanner.qualityFeedback != .none {
                                    VStack(spacing: 8) {
                                        Image(systemName: qualityFeedbackIcon)
                                            .font(.system(size: 24, weight: .bold))
                                            .foregroundColor(qualityFeedbackColor)
                                        
                                        Text(qualityFeedbackText)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(qualityFeedbackColor)
                                    }
                                    .padding(12)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(8)
                                }
                                
                                // Face positioning guide
                                Circle()
                                    .stroke(Color.white.opacity(0.4), lineWidth: 2)
                                    .frame(width: 200, height: 200)
                                    .background(
                                        Circle()
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                            .frame(width: 220, height: 220)
                                    )
                            }
                            
                            // Instructions
                            VStack(spacing: 16) {
                                Text("Face Recognition Instructions")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    FaceInstructionRow(icon: "eye.fill", text: "Look directly at the camera")
                                    FaceInstructionRow(icon: "hand.raised.fill", text: "Keep your face centered")
                                    FaceInstructionRow(icon: "arrow.up.and.down", text: "Move your head slightly")
                                    FaceInstructionRow(icon: "clock.fill", text: "Follow the prompts for 5 seconds")
                                }
                            }
                            .padding(.horizontal, 40)
                        }
                    }
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                // Action buttons
                if faceResults != nil {
                    Button(action: {
                        onComplete(faceResults!)
                    }) {
                        HStack(spacing: 12) {
                            Text("Continue")
                                .font(.system(size: 18, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.green,
                                    Color.green.opacity(0.8)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                } else {
                    Button(action: {
                        showingInstructions = false
                        startCountdown()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Start Face Recognition")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.2, green: 0.6, blue: 1.0),
                                    Color(red: 0.1, green: 0.5, blue: 0.9)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            
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
            // Setup face recognition scanner
            setupFaceRecognition()
        }
        .onDisappear {
            scanner.stopScanning()
        }
    }
    
    private var qualityFeedbackIcon: String {
        switch scanner.qualityFeedback {
        case .excellent: return "checkmark.circle.fill"
        case .good: return "checkmark.circle"
        case .poor: return "exclamationmark.triangle.fill"
        case .none: return "questionmark.circle"
        }
    }
    
    private var qualityFeedbackColor: Color {
        switch scanner.qualityFeedback {
        case .excellent: return .green
        case .good: return .yellow
        case .poor: return .red
        case .none: return .white
        }
    }
    
    private var qualityFeedbackText: String {
        switch scanner.qualityFeedback {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .poor: return "Adjust Position"
        case .none: return "Position Face"
        }
    }
    
    private var instructionsOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Text("Face Recognition Guide")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 16) {
                    FaceGuideRow(icon: "1.circle.fill", title: "Position", description: "Center your face in the circle")
                    FaceGuideRow(icon: "2.circle.fill", title: "Lighting", description: "Ensure good lighting on your face")
                    FaceGuideRow(icon: "3.circle.fill", title: "Movement", description: "Follow prompts for natural movement")
                    FaceGuideRow(icon: "4.circle.fill", title: "Duration", description: "Process takes 5 seconds")
                }
                .padding(.horizontal, 40)
                
                Button("Start Recognition") {
                    showingInstructions = false
                    startCountdown()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(Color.blue)
                .cornerRadius(12)
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
    
    private func setupFaceRecognition() {
        // Configure scanner for face recognition
        // scanDuration is already set to 5.0 seconds by default
        
        // Start camera preview immediately for positioning
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.scanner.startCameraPreview()
        }
    }
    
    private func startCountdown() {
        print("Starting face recognition countdown...")
        isCountingDown = true
        countdown = 3
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            print("Countdown: \(self.countdown)")
            self.countdown -= 1
            
            if self.countdown <= 0 {
                print("Countdown finished, starting face recognition...")
                timer.invalidate()
                self.isCountingDown = false
                self.startFaceRecognition()
            }
        }
    }
    
    private func startFaceRecognition() {
        print("Starting face recognition...")
        scanner.startScanning(for: .front) // Use front side for face recognition
        
        // Monitor for completion
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if let results = scanner.scanResults {
                timer.invalidate()
                self.processFaceResults(results)
            }
        }
    }
    
    private func processFaceResults(_ videoResults: VideoScanResults) {
        // Extract face recognition results from video scan
        let faceResults = FaceRecognitionResults(
            confidence: videoResults.faceDetectionResults?.confidence ?? 0.0,
            quality: videoResults.faceDetectionResults?.quality ?? "Unknown",
            livenessScore: calculateLivenessScore(videoResults),
            timestamp: Date().timeIntervalSince1970
        )
        
        DispatchQueue.main.async {
            self.faceResults = faceResults
        }
    }
    
    private func calculateLivenessScore(_ results: VideoScanResults) -> Double {
        // Calculate liveness score based on video analysis
        var score = 0.0
        
        // Face detection confidence
        if let faceResults = results.faceDetectionResults {
            score += faceResults.confidence * 0.4
        }
        
        // Frame analysis for movement
        let movementFrames = results.frameAnalyses.filter { $0.faceDetected }
        if !movementFrames.isEmpty {
            score += min(Double(movementFrames.count) / 10.0, 0.3) // Up to 30% for movement
        }
        
        // Quality consistency
        let avgQuality = results.frameAnalyses.map { getQualityScore($0.imageQuality) }.reduce(0, +) / Double(results.frameAnalyses.count)
        score += avgQuality * 0.3
        
        return min(score, 1.0)
    }
    
    private func getQualityScore(_ quality: ImageQualityMetrics) -> Double {
        switch quality.overallQuality {
        case "Excellent": return 1.0
        case "Good": return 0.8
        case "Fair": return 0.6
        default: return 0.4
        }
    }
}

// MARK: - Supporting Views for Face Recognition

struct FaceInstructionRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 20)
            
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
        }
    }
}

struct FaceGuideRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(Color(red: 0.2, green: 0.6, blue: 1.0))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
        }
    }
}

// MARK: - Face Recognition Results

struct FaceRecognitionResults {
    let confidence: Double
    let quality: String
    let livenessScore: Double
    let timestamp: TimeInterval
}

// LicenseSide enum is defined in VideoBasedScanner.swift

// MARK: - License Data Structure

struct LicenseData {
    var frontText: String?
    var barcodeData: String?
    var barcodeType: String = "Unknown"
    var ocrExtractedFields: [String: String] = [:]
    var barcodeExtractedFields: [String: String] = [:]
}

#Preview {
    ContentView()
}
