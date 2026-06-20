#!/bin/bash
# Builds PDFPresenter and assembles a double-clickable .app bundle.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="PDFPresenter.app"

echo "Building (${CONFIG})..."
swift build -c "${CONFIG}"
BIN="$(swift build -c "${CONFIG}" --show-bin-path)/PDFPresenter"

echo "Assembling ${APP}..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/PDFPresenter"
cp Resources/Info.plist "${APP}/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"

echo "Done -> ${APP}"
echo "Run with:  open ${APP} --args /path/to/slides.pdf"
echo "Or:        open ${APP}   (then Cmd-O)"
