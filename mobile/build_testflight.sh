#!/bin/bash

# Build script for iOS TestFlight deployment with crash reporting
# ABOUTME: Builds iOS release for TestFlight with proper configuration

set -e

echo "🚀 Building OpenVine for TestFlight deployment..."

# Clean previous builds
echo "🧹 Cleaning previous builds..."
flutter clean

# Get dependencies
echo "📦 Getting dependencies..."
flutter pub get

# Run code generation if needed
echo "⚙️ Running code generation..."
flutter pub run build_runner build --delete-conflicting-outputs || true

# Build iOS release
echo "🏗️ Building iOS release..."
flutter build ipa --release \
  --dart-define=ENVIRONMENT=testflight \
  --dart-define=ENABLE_CRASHLYTICS=true

echo "✅ Build complete!"
echo ""
echo "📱 Next steps:"
echo "1. Open Xcode and select Product > Archive"
echo "2. Upload to App Store Connect"
echo "3. Submit for TestFlight review"
echo ""
echo "🔍 Crash reports will appear in Firebase Console:"
echo "   https://console.firebase.google.com/project/openvine-placeholder/crashlytics"
echo ""
echo "⚠️ IMPORTANT: Replace placeholder Firebase config with real project before production!"