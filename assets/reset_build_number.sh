#!/bin/bash

echo "--- Resetting build number! ---"

cd "$SRCROOT"

# Set VERSION
sed -i -e "/VERSION =/ s/= .*/= 0.0.0/" Colonnade/Config.xcconfig

# Set BUILD_NUMBER
sed -i -e "/BUILD_NUMBER =/ s/= .*/= 0/" Colonnade/Config.xcconfig

rm Colonnade/Config.xcconfig-e

echo "--- Done! ---"
