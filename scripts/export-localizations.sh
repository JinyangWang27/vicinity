#!/usr/bin/env bash
# export-localizations.sh
#
# Exports an .xcloc package for each supported language into Localizations/.
# Contributors can open a .xcloc file in Xcode to translate strings visually,
# then submit the updated vicinity/Localizable.xcstrings via Pull Request.
#
# Usage:
#   bash scripts/export-localizations.sh
#
# Requirements: Xcode command-line tools (xcodebuild must be on PATH).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO_ROOT/vicinity.xcodeproj"
OUTPUT="$REPO_ROOT/Localizations"

mkdir -p "$OUTPUT"

echo "Exporting localizations from $PROJECT …"

xcodebuild -exportLocalizations \
  -project "$PROJECT" \
  -localizationPath "$OUTPUT" \
  -exportLanguage zh-Hans \
  -exportLanguage zh-Hant

echo ""
echo "Done. Exported packages:"
ls "$OUTPUT"/*.xcloc 2>/dev/null || echo "  (none found — check xcodebuild output above)"
echo ""
echo "Open a .xcloc file in Finder to edit it in Xcode's translation editor."
echo "After editing, copy the updated Localizable.xcstrings back into vicinity/ and open a PR."
