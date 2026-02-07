#!/usr/bin/env bash

# Package rubister for distribution
set -e

VERSION=${1:-"0.0.q"}
PACKAGE_NAME="rubister-${VERSION}"
PLATFORM=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
FULL_PACKAGE_NAME="${PACKAGE_NAME}-${PLATFORM}-${ARCH}"

echo "Packaging rubister version ${VERSION} for ${PLATFORM}-${ARCH}..."

# Create a clean package directory
rm -rf "${FULL_PACKAGE_NAME}"
rm -f "${FULL_PACKAGE_NAME}.tar.gz"
mkdir -p "${FULL_PACKAGE_NAME}"

echo "Copying application files..."
# Copy all Ruby files and tools
cp -r *.rb tools "${FULL_PACKAGE_NAME}/"

# Copy the standalone bundle
echo "Copying standalone bundle..."
cp -r bundle "${FULL_PACKAGE_NAME}/"

# Copy the wrapper script
cp rubister "${FULL_PACKAGE_NAME}/"
chmod +x "${FULL_PACKAGE_NAME}/rubister"

# Copy format_output if it exists
if [ -f format_output.rb ]; then
    cp format_output.rb "${FULL_PACKAGE_NAME}/"
    chmod +x "${FULL_PACKAGE_NAME}/format_output.rb"
fi

# Create a README for the package
cat > "${FULL_PACKAGE_NAME}/README.txt" << 'EOF'
Rubister - AI Agent for File Operations

## Requirements
- Ruby 2.7 or higher (check with: ruby --version)

## Installation
1. Extract this archive
2. Add the directory to your PATH, or create a symlink:
   ln -s /path/to/rubister /usr/local/bin/rubister

## Usage
Basic usage:
  ./rubister -m "your message here"

Interactive mode:
  ./rubister

With formatting:
  ./rubister -m "your message" | ./format_output.rb

For more options:
  ./rubister --help

## Configuration
Rubister looks for authentication in ~/.local/share/opencode/auth.json
or you can provide auth via --auth flag.

For more information, visit: https://github.com/Hyper-Unearthing/rubister
EOF

echo "Creating archive..."
tar -czf "${FULL_PACKAGE_NAME}.tar.gz" "${FULL_PACKAGE_NAME}"

echo "Cleaning up..."
rm -rf "${FULL_PACKAGE_NAME}"

echo ""
echo "✓ Package created: ${FULL_PACKAGE_NAME}.tar.gz"
echo ""
echo "To test the package:"
echo "  tar -xzf ${FULL_PACKAGE_NAME}.tar.gz"
echo "  cd ${FULL_PACKAGE_NAME}"
echo "  ./rubister --help"
echo ""
echo "Users can extract and run it with Ruby installed!"
