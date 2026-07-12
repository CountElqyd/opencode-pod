#!/bin/bash

set -e

echo "🏗️  Building Fabric MCP Bundle..."
echo ""

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -f fabric-mcp.mcpb
rm -rf dist/

# Build TypeScript
echo "📦 Building TypeScript..."
npm run build

# Make entry point executable
echo "🔧 Making entry point executable..."
chmod +x dist/index.js

# Create bundle
echo "📦 Creating .mcpb bundle..."
if [ -f "icon.png" ]; then
    zip -r fabric-mcp.mcpb manifest.json package.json package-lock.json dist/ node_modules/ README.md icon.png
else
    echo "⚠️  Warning: icon.png not found, building without icon"
    zip -r fabric-mcp.mcpb manifest.json package.json package-lock.json dist/ node_modules/ README.md
fi

# Verify bundle
echo ""
echo "✅ Bundle created successfully!"
echo ""

# Show bundle info
echo "📊 Bundle information:"
ls -lh fabric-mcp.mcpb
echo ""

echo "📋 Bundle contents:"
unzip -l fabric-mcp.mcpb
echo ""

# Verify manifest
echo "🔍 Verifying manifest..."
unzip -p fabric-mcp.mcpb manifest.json | jq . > /dev/null 2>&1 && echo "✅ Manifest is valid JSON" || echo "⚠️  Manifest may have issues"

# Verify shebang
echo ""
echo "🔍 Verifying entry point shebang..."
SHEBANG=$(unzip -p fabric-mcp.mcpb dist/index.js | head -1)
if [[ "$SHEBANG" == "#!/usr/bin/env node" ]]; then
    echo "✅ Shebang is correct"
else
    echo "⚠️  Warning: Shebang is '$SHEBANG'"
fi

echo ""
echo "✨ Build complete! You can now:"
echo "   1. Double-click fabric-mcp.mcpb to install"
echo "   2. Share fabric-mcp.mcpb with others"
echo "   3. See INSTALL.md for installation instructions"
echo ""
