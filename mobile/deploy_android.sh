#!/bin/bash
# ABOUTME: Automated Android deployment script for Google Play Console
# ABOUTME: Builds AAB and deploys to Internal/Closed/Production testing tracks

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
TRACK="internal"
SKIP_BUILD=false
SKIP_UPLOAD=false
VERSION_NAME=""
RELEASE_NOTES=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    internal|closed|production)
      TRACK="$1"
      shift
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --skip-upload)
      SKIP_UPLOAD=true
      shift
      ;;
    --version)
      VERSION_NAME="$2"
      shift 2
      ;;
    --notes)
      RELEASE_NOTES="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: ./deploy_android.sh [track] [options]"
      echo ""
      echo "Tracks:"
      echo "  internal      - Deploy to Internal Testing (default, no review, 100 testers)"
      echo "  closed        - Deploy to Closed Testing (requires review)"
      echo "  production    - Deploy to Production (full review)"
      echo ""
      echo "Options:"
      echo "  --skip-build       Skip the build step (use existing AAB)"
      echo "  --skip-upload      Only build, don't upload"
      echo "  --version NAME     Set version name for release (e.g., 'v0.1.0')"
      echo "  --notes TEXT       Set release notes"
      echo "  -h, --help         Show this help message"
      echo ""
      echo "Example:"
      echo "  ./deploy_android.sh internal --version 'v0.1.0' --notes 'Bug fixes'"
      exit 0
      ;;
    *)
      echo -e "${RED}Error: Unknown argument '$1'${NC}"
      echo "Run './deploy_android.sh --help' for usage information"
      exit 1
      ;;
  esac
done

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}OpenVine Android Deployment${NC}"
echo -e "${BLUE}================================${NC}"
echo ""
echo -e "Track: ${YELLOW}$TRACK${NC}"
echo -e "Skip build: ${YELLOW}$SKIP_BUILD${NC}"
echo -e "Skip upload: ${YELLOW}$SKIP_UPLOAD${NC}"
echo ""

# Change to mobile directory
cd "$(dirname "$0")"

# Check for fastlane setup
if [ ! -d "android/fastlane" ]; then
  echo -e "${YELLOW}Fastlane not configured yet. Setting up...${NC}"
  echo ""

  mkdir -p android/fastlane

  # Create Fastfile
  cat > android/fastlane/Fastfile << 'EOF'
default_platform(:android)

platform :android do
  desc "Deploy to Internal Testing"
  lane :internal do
    upload_to_play_store(
      track: 'internal',
      aab: '../build/app/outputs/bundle/release/app-release.aab',
      skip_upload_apk: true,
      skip_upload_metadata: true,
      skip_upload_images: true,
      skip_upload_screenshots: true
    )
  end

  desc "Deploy to Closed Testing (Alpha/Beta)"
  lane :closed do
    upload_to_play_store(
      track: 'alpha',
      aab: '../build/app/outputs/bundle/release/app-release.aab',
      skip_upload_apk: true,
      skip_upload_metadata: true,
      skip_upload_images: true,
      skip_upload_screenshots: true
    )
  end

  desc "Deploy to Production"
  lane :production do
    upload_to_play_store(
      track: 'production',
      aab: '../build/app/outputs/bundle/release/app-release.aab',
      skip_upload_apk: true,
      skip_upload_metadata: true,
      skip_upload_images: true,
      skip_upload_screenshots: true
    )
  end
end
EOF

  echo -e "${GREEN}✓ Fastfile created${NC}"
  echo ""
fi

# Check for Google Play API credentials
SERVICE_ACCOUNT_JSON="android/play-store-service-account.json"
if [ ! -f "$SERVICE_ACCOUNT_JSON" ]; then
  echo -e "${RED}Error: Google Play API credentials not found!${NC}"
  echo ""
  echo -e "${YELLOW}Setup Instructions:${NC}"
  echo "1. Go to Google Play Console → Setup → API access"
  echo "2. Create a service account or use existing one"
  echo "3. Grant 'Release manager' role to the service account"
  echo "4. Download the JSON key file"
  echo "5. Save it as: ${YELLOW}android/play-store-service-account.json${NC}"
  echo ""
  echo "See: https://docs.fastlane.tools/getting-started/android/setup/"
  exit 1
fi

echo -e "${GREEN}✓ Service account credentials found${NC}"
echo ""

# Build AAB if not skipped
if [ "$SKIP_BUILD" = false ]; then
  echo -e "${YELLOW}Building Android App Bundle...${NC}"
  echo ""

  flutter clean
  flutter pub get
  flutter build appbundle --release

  if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Build successful${NC}"

    AAB_PATH="build/app/outputs/bundle/release/app-release.aab"
    AAB_SIZE=$(du -h "$AAB_PATH" | cut -f1)
    echo -e "AAB location: ${YELLOW}$AAB_PATH${NC}"
    echo -e "AAB size: ${YELLOW}$AAB_SIZE${NC}"
    echo ""
  else
    echo -e "${RED}Build failed!${NC}"
    exit 1
  fi
else
  echo -e "${YELLOW}Skipping build (using existing AAB)${NC}"
  echo ""
fi

# Upload to Play Store if not skipped
if [ "$SKIP_UPLOAD" = false ]; then
  echo -e "${YELLOW}Uploading to Google Play Console ($TRACK track)...${NC}"
  echo ""

  cd android

  # Set environment variable for service account
  export SUPPLY_JSON_KEY="play-store-service-account.json"

  # Run fastlane lane based on track
  case $TRACK in
    internal)
      fastlane internal
      ;;
    closed)
      fastlane closed
      ;;
    production)
      fastlane production
      ;;
  esac

  if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}Deployment Successful!${NC}"
    echo -e "${GREEN}================================${NC}"
    echo ""
    echo -e "Track: ${YELLOW}$TRACK${NC}"
    echo ""

    case $TRACK in
      internal)
        echo -e "${GREEN}Next Steps:${NC}"
        echo "1. Go to Play Console → Testing → Internal testing"
        echo "2. Add testers via email list"
        echo "3. Share opt-in URL with testers"
        echo "4. Testers will receive update within minutes"
        ;;
      closed)
        echo -e "${GREEN}Next Steps:${NC}"
        echo "1. Wait for Google Play review (typically 1-2 days)"
        echo "2. Once approved, testers can download from Play Store"
        ;;
      production)
        echo -e "${GREEN}Next Steps:${NC}"
        echo "1. Wait for Google Play review (typically 3-7 days)"
        echo "2. Once approved, app will be live in Play Store"
        ;;
    esac
    echo ""
  else
    echo ""
    echo -e "${RED}Deployment failed!${NC}"
    exit 1
  fi
else
  echo -e "${YELLOW}Skipping upload (build only)${NC}"
  echo ""
fi

echo -e "${GREEN}Done!${NC}"
