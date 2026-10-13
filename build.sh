#!/bin/zsh
# Builds "Speedy.app" (Apple silicon and Intel) and a zip file to share it.
# Output: build/Speedy.app and build/Speedy.zip

set -euo pipefail

readonly project_directory="${0:A:h}"
readonly build_directory="${project_directory}/build"
readonly app_bundle="${build_directory}/Speedy.app"
readonly app_zip="${build_directory}/Speedy.zip"
readonly executable_name="Speedy"
readonly bundle_identifier="io.github.ramenbox.speedy"
readonly minimum_macos_version="13.0"
readonly app_version="1.1.0"

print_error() {
  local -r message=$1
  print -r -- "ERROR: ${message}" >&2
}

if ! command -v swiftc >/dev/null; then
  print_error "swiftc is missing. Install the Xcode Command Line Tools: xcode-select --install"
  exit 1
fi

source_files=("${project_directory}"/Sources/Core/*.swift "${project_directory}"/Sources/App/*.swift "${project_directory}"/Sources/App/Views/*.swift)

mkdir -p -- "${build_directory}"
rm -rf -- "${app_bundle}" "${app_zip}"
mkdir -p -- "${app_bundle}/Contents/MacOS" "${app_bundle}/Contents/Resources"

architecture_executables=()
for architecture in arm64 x86_64; do
  architecture_executable="${build_directory}/${executable_name}-${architecture}"
  print -r -- "Compiling for ${architecture}"
  swiftc -O -swift-version 5 -parse-as-library \
    -target "${architecture}-apple-macos${minimum_macos_version}" \
    -o "${architecture_executable}" \
    "${source_files[@]}"
  architecture_executables+=("${architecture_executable}")
done

cp -- "${project_directory}/Resources/AppIcon.icns" "${app_bundle}/Contents/Resources/AppIcon.icns"
lipo -create -output "${app_bundle}/Contents/MacOS/${executable_name}" "${architecture_executables[@]}"
rm -f -- "${architecture_executables[@]}"

cat >"${app_bundle}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${executable_name}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>${bundle_identifier}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Speedy</string>
  <key>CFBundleDisplayName</key>
  <string>Speedy</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${app_version}</string>
  <key>CFBundleVersion</key>
  <string>${app_version}</string>
  <key>LSMinimumSystemVersion</key>
  <string>${minimum_macos_version}</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

plutil -lint "${app_bundle}/Contents/Info.plist" >/dev/null
codesign --force --sign - "${app_bundle}"
ditto -c -k --keepParent "${app_bundle}" "${app_zip}"

print -r -- "Built: ${app_bundle}"
print -r -- "Zip to share: ${app_zip}"
