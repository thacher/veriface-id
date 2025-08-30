#!/bin/bash

echo "🚀 Building check-id iOS app..."
echo ""

# Clean previous builds
echo "🧹 Cleaning previous builds..."
xcodebuild clean -project check-id.xcodeproj -scheme check-id

# Build the project
echo "🔨 Building project..."
xcodebuild build -project check-id.xcodeproj -scheme check-id -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.1'

echo ""
echo "✅ Build completed successfully!"
echo ""
echo "📱 To run the app:"
echo "   1. Open check-id.xcodeproj in Xcode"
echo "   2. Select your target device or simulator"
echo "   3. Press Cmd+R to build and run"
echo ""
echo "🔧 Or use: open check-id.xcodeproj"
echo ""
echo "🎯 App Features:"
echo "   • Modern camera integration"
echo "   • Photo library access"
echo "   • Real-time validation"
echo "   • Beautiful gradient UI"
echo "   • Privacy-focused design"
