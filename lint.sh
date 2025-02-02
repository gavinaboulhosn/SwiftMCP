#!/bin/bash

set -e

# configure xcode settings to not conflict with swiftlint
# this file is in the same directory as this script with name ./xcode-settings.sh
echo "Configuring Xcode settings..."
./xcode-settings.sh


# lint and format, passing all extra command line args to swiftformat
echo "Linting and formatting..."
# NOTE: add --log if you want to see what swiftlint commands were ran
swift package --allow-writing-to-package-directory format --exclude Tests "$@"
