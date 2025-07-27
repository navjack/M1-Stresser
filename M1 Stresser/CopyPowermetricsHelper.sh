# This script copies the prebuilt PowermetricsHelper into the app bundle's Resources directory during the Xcode build process.
# Place this file in your project (e.g., in the root or Scripts directory), then add a Run Script Build Phase in Xcode that runs this script.

# Path to the prebuilt helper
HELPER_SRC="/Volumes/4terrybi/coding/M1 Stresser/M1 Stresser/PowermetricsHelper"

# Destination determined by Xcode's environment variable
APP_RESOURCES_DIR="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Contents/Resources"

# Exit if the source helper doesn't exist
if [ ! -f "$HELPER_SRC" ]; then
  echo "PowermetricsHelper not found at $HELPER_SRC"
  exit 1
fi

mkdir -p "$APP_RESOURCES_DIR"
cp -f "$HELPER_SRC" "$APP_RESOURCES_DIR/"
chmod +x "$APP_RESOURCES_DIR/PowermetricsHelper"
echo "[Build Phase] PowermetricsHelper copied to $APP_RESOURCES_DIR and made executable."
