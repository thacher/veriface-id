#!/bin/bash

echo "🚀 Building veriface-id iOS app..."
echo ""

# Clean previous builds
echo "🧹 Cleaning previous builds..."
xcodebuild clean -project veriface-id.xcodeproj -scheme veriface-id

# Build the project
echo "🔨 Building project..."
xcodebuild build -project veriface-id.xcodeproj -scheme veriface-id -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.1'

echo ""
echo "✅ Build completed successfully!"
echo ""
echo "📱 To run the app:"
echo "   1. Open veriface-id.xcodeproj in Xcode"
echo "   2. Select your target device or simulator"
echo "   3. Press Cmd+R to build and run"
echo ""
echo "🔧 Or use: open veriface-id.xcodeproj"
echo ""
echo "🎯 App Features:"
echo "   • Modern camera integration"
echo "   • Photo library access"
echo "   • Real-time validation"
echo "   • Beautiful gradient UI"
echo "   • Privacy-focused design"
