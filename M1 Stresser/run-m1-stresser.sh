#!/bin/bash

# This script finds and runs the M1 Stresser app binary with sudo
# It works from the project root, as long as the app has been built in Debug configuration.

set -e

APP_NAME="M1 Stresser"
EXEC_RELATIVE_PATH="Build/Products/Debug/$APP_NAME.app/Contents/MacOS/$APP_NAME"

# Attempt to auto-detect DerivedData directory
DERIVED_DATA_BASE="$(dirname "$0")/../xcode/deriveddata"
if [ ! -d "$DERIVED_DATA_BASE" ]; then
    DERIVED_DATA_BASE="$(dirname "$0")/../DerivedData"
fi

# Find the most recent build dir for the app
APP_EXECUTABLE=$(find "$DERIVED_DATA_BASE" -type f -path "*/$EXEC_RELATIVE_PATH" 2>/dev/null | sort | tail -n 1)

if [ ! -x "$APP_EXECUTABLE" ]; then
    echo "Could not find a built M1 Stresser app binary."
    echo "Please build the app in Xcode (Debug configuration), or provide the path manually."
    echo ""
    echo "Usage:"
    echo "  sudo ./run-m1-stresser.sh [path/to/M1 Stresser.app/Contents/MacOS/M1 Stresser]"
    exit 1
fi

# Run the app binary with sudo
sudo "$APP_EXECUTABLE"
