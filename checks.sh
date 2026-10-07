#!/bin/zsh
# Builds and runs the checks for the Speedy core logic.

set -euo pipefail

readonly project_directory="${0:A:h}"
readonly checks_directory="${project_directory}/build/checks"
readonly checks_executable="${checks_directory}/SpeedyChecks"

if ! command -v swiftc >/dev/null; then
  print -r -- "ERROR: swiftc is missing. Install the Xcode Command Line Tools: xcode-select --install" >&2
  exit 1
fi

mkdir -p -- "${checks_directory}"
swiftc -swift-version 5 -parse-as-library \
  -o "${checks_executable}" \
  "${project_directory}"/Sources/Core/*.swift \
  "${project_directory}"/Checks/*.swift
"${checks_executable}"
