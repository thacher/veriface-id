# Check ID - Professional License Validation

A modern iOS application for professional driver's license validation using OCR (Optical Character Recognition) and barcode scanning technology.

## 🚀 Features

### Front License OCR Processing
- **Advanced OCR Parsing**: Extracts personal information from driver's license front images
- **Field Label Recognition**: Handles complex OCR formats where field labels appear before their corresponding values
- **OCR Artifact Handling**: Robust parsing that accounts for common OCR scanning artifacts and errors
- **Comprehensive Data Extraction**: Captures all major license fields including:
  - Name (First, Middle, Last)
  - Date of Birth
  - Driver License Number
  - State
  - Sex/Gender
  - Height (with OCR artifact correction)
  - Weight
  - Eye Color
  - Address
  - Expiration Date
  - Issue Date
  - Class
  - Endorsements/Restrictions

### Back License Barcode Processing
- **PDF417 Barcode Scanning**: Extracts encoded data from license barcodes
- **AAMVA Standard Compliance**: Parses standard driver's license barcode formats
- **Separate Processing**: Front OCR and back barcode processing remain independent for maximum accuracy

### User Interface
- **Modern Design**: Clean, professional interface inspired by industry-leading validation tools
- **Real-time Feedback**: Immediate validation results with confidence scoring
- **Quality Analysis**: Built-in image quality assessment for optimal scanning
- **Comprehensive Reporting**: Detailed field-by-field validation results

## 🔧 Technical Implementation

### OCR Parsing Engine

The app features a sophisticated OCR parsing system that handles various license formats:

#### Field Label → Value Mapping
The parsing engine recognizes the specific format where field labels appear first, followed by their corresponding values later in the text:

```
Field Labels → Values:
• HGT 17 → 5'. -09" (height)
• SEX 16 → M (sex)
• EYES → BLU (eye color)
• WIGT → 185lb (weight)
```

#### OCR Artifact Handling
Special attention has been given to common OCR scanning artifacts:

- **Height Format**: Handles "5'. -09\"" format with period and leading zeros
- **Eye Color**: Uses word boundaries to avoid partial matches (e.g., "BLU" vs "CHR")
- **Sex Extraction**: Supports "M8" format where sex value appears before a number
- **Weight Format**: Recognizes "185lb" standalone format

#### Parsing Patterns

```swift
// Sex extraction with multiple patterns
if let sexMatch = text.range(of: #"([MF])\d"#, options: .regularExpression) {
    // Pattern for "M8" format where sex value comes before a number
    let sexRange = text[sexMatch].range(of: #"[MF]"#, options: .regularExpression)!
    data.append(("Sex", text[sexRange] == "M" ? "Male" : "Female"))
}

// Height extraction with OCR artifact handling
if let heightMatch = text.range(of: #"(\d{1,2})['\"]\s*[.]\s*[-]?\s*(\d{1,2})[\"]"#, options: .regularExpression) {
    // Pattern for height like "5'. -09"" - handle OCR artifacts with period
    let heightText = String(text[heightMatch])
    data.append(("Height", formatHeight(heightText)))
}

// Eye color extraction with word boundaries
if let eyeMatch = text.range(of: #"\b(BLU|BLUE|BRN|BROWN|GRN|GREEN|GRY|GRAY|HAZ|HAZEL|BLK|BLACK|AMB|AMBER|MUL|MULTI|PINK|PUR|PURPLE|YEL|YELLOW|WHI|WHITE|MAR|MARBLE|CHR|CHROME|GOL|GOLD|SIL|SILVER|COPPER|BURGUNDY|VIOLET|INDIGO|TEAL|TURQUOISE|AQUA|CYAN|LIME|OLIVE|NAVY|ROYAL|SKY|LIGHT|DARK|MED|MEDIUM)\b"#, options: .regularExpression) {
    // Pattern for standalone eye colors with word boundaries
    let eyeColor = String(text[eyeMatch])
    data.append(("Eye Color", convertAllCapsToProperCase(eyeColor)))
}
```

### Data Processing Architecture

#### Front OCR Processing
- **Image Quality Analysis**: Analyzes brightness, contrast, and sharpness
- **Text Extraction**: Uses Vision framework for accurate OCR
- **Field Parsing**: Custom regex patterns for each field type
- **Data Validation**: Cross-references extracted data for consistency

#### Back Barcode Processing
- **Barcode Detection**: Identifies PDF417 format barcodes
- **Data Decoding**: Parses AAMVA standard encoded data
- **Field Mapping**: Maps barcode fields to human-readable labels

#### Validation System
- **Confidence Scoring**: Calculates matching scores between front and back data
- **Field Comparison**: Compares corresponding fields for validation
- **Error Reporting**: Identifies and reports mismatches or missing data

## 📱 User Experience

### Scanning Process
1. **Front License Capture**: User captures front of driver's license
2. **Back License Capture**: User captures back of driver's license
3. **Processing**: App processes both images simultaneously
4. **Results Display**: Comprehensive validation results shown to user

### Quality Guidelines
The app includes built-in quality assessment to ensure optimal scanning:
- **Brightness**: Optimal range 50-200 (0-255 scale)
- **Contrast**: Minimum 30 for clear text recognition
- **Sharpness**: Minimum edge strength of 20

### Results Display
Results are presented in a clean, organized format:
```
📄 Front License Data:
Name: John Doe
Date of Birth: 01/15/1985
Driver License Number: A1234567
State: California
Sex: Male
Height: 5'10" (70")
Weight: 175 lb
Eye Color: Blue

📊 Barcode Scan Results:
[Corresponding barcode data fields]
```

## 🛠 Development

### Requirements
- iOS 15.0+
- Xcode 13.0+
- Swift 5.5+

### Dependencies
- **Vision Framework**: For OCR text recognition
- **AVFoundation**: For camera access and barcode scanning
- **Core Image**: For image processing and quality analysis

### Project Structure
```
check-id/
├── check-id/
│   ├── CheckIDApp.swift          # Main app entry point
│   ├── ContentView.swift          # Main UI and OCR processing logic
│   ├── Assets.xcassets/          # App icons and assets
│   └── Info.plist               # App configuration
├── check-id.xcodeproj/          # Xcode project files
├── build.sh                     # Build script
└── project.yml                  # Project configuration
```

### Key Functions

#### OCR Processing
- `extractTextFromImage()`: Main OCR text extraction
- `extractCleanPersonalData()`: Field-specific data parsing
- `analyzeImageQuality()`: Image quality assessment
- `formatHeight()`: Height formatting and OCR artifact correction

#### Barcode Processing
- `extractBarcodeFromImage()`: Barcode detection and extraction
- `parseBarcodeData()`: Barcode data parsing and field mapping

#### Validation
- `calculateMatchingScore()`: Confidence scoring between front and back data
- `showValidationResults()`: Results display and user feedback

## 🎯 Recent Improvements

### OCR Parsing Enhancements
- **Fixed Eye Color Extraction**: Added word boundaries to prevent partial matches
- **Enhanced Height Parsing**: Improved handling of OCR artifacts in height format
- **Robust Sex Extraction**: Added support for "M8" format pattern
- **Weight Recognition**: Enhanced standalone weight format detection

### Field Label Recognition
- Implemented sophisticated parsing for field label → value mapping
- Added support for OCR formats where labels appear before values
- Enhanced error handling for malformed OCR text

### Quality Assurance
- Comprehensive testing with real OCR text samples
- Validation of all parsing patterns
- Debug logging for troubleshooting

## 🔍 Troubleshooting

### Common Issues

#### Missing Fields in Results
If certain fields (like Sex or Weight) don't appear in results:
1. Check Xcode console for debug output starting with `🚨🚨🚨 VALIDATION RESULTS CALLED 🚨🚨🚨`
2. Verify the actual OCR text being processed
3. Ensure image quality meets minimum requirements

#### OCR Artifacts
The app handles common OCR artifacts:
- Periods after feet symbols in height
- Leading zeros in inches
- Extra spaces and characters
- Partial word matches

### Debug Information
The app includes comprehensive debug logging:
- Raw OCR text processing
- Field extraction results
- Image quality metrics
- Parsing pattern matches

## 📄 License

This project is proprietary software. All rights reserved.

## 🤝 Contributing

For development inquiries or bug reports, please contact the development team.

---

**Check ID** - Professional-grade license validation for iOS
