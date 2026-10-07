#!/bin/zsh
# Renders the app icon, the README screenshots and the hero image from demo data.
# Output: docs/images/*.png and Resources/AppIcon.icns

set -euo pipefail

readonly project_directory="${0:A:h:h}"
readonly tool_directory="${project_directory}/build/assets"
# The tool runs inside an app bundle, because UserNotifications needs a bundle.
readonly tool_bundle="${tool_directory}/RenderAssets.app"
readonly tool_executable="${tool_bundle}/Contents/MacOS/RenderAssets"
readonly iconset_directory="${tool_directory}/AppIcon.iconset"
readonly icon_png="${project_directory}/docs/images/icon.png"

if ! command -v swiftc >/dev/null; then
  print -r -- "ERROR: swiftc is missing. Install the Xcode Command Line Tools: xcode-select --install" >&2
  exit 1
fi

# SpeedyApp.swift holds the @main of the app. The tool has its own.
app_sources=("${project_directory}"/Sources/App/*.swift(N))
app_sources=(${app_sources:#*/SpeedyApp.swift})

rm -rf -- "${tool_bundle}"
mkdir -p -- "${tool_bundle}/Contents/MacOS"
cat >"${tool_bundle}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>RenderAssets</string>
  <key>CFBundleIdentifier</key>
  <string>io.github.ramenbox.speedy.assets</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
</dict>
</plist>
PLIST

print -r -- "Compiling the asset tool"
swiftc -swift-version 5 -parse-as-library -D SPEEDY_SCREENSHOTS \
  -o "${tool_executable}" \
  "${project_directory}"/Sources/Core/*.swift \
  "${app_sources[@]}" \
  "${project_directory}"/Sources/App/Views/*.swift \
  "${project_directory}"/Tools/Assets/*.swift
codesign --force --sign - "${tool_bundle}"

"${tool_executable}" "${project_directory}"

rm -rf -- "${iconset_directory}"
mkdir -p -- "${iconset_directory}"
for point_size in 16 32 128 256 512; do
  sips -z "${point_size}" "${point_size}" "${icon_png}" --out "${iconset_directory}/icon_${point_size}x${point_size}.png" >/dev/null
  double_size=$((point_size * 2))
  sips -z "${double_size}" "${double_size}" "${icon_png}" --out "${iconset_directory}/icon_${point_size}x${point_size}@2x.png" >/dev/null
done
mkdir -p -- "${project_directory}/Resources"
iconutil -c icns -o "${project_directory}/Resources/AppIcon.icns" "${iconset_directory}"
print -r -- "Wrote ${project_directory}/Resources/AppIcon.icns"
