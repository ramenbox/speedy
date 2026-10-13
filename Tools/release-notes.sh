#!/bin/zsh
# Prints the CHANGELOG.md section of one version, without its "## [version]" heading.
# Usage: Tools/release-notes.sh 1.0.1
# Fails when CHANGELOG.md has no section for the version, or when the section is empty.

set -euo pipefail

readonly project_directory="${0:A:h:h}"
readonly changelog_file="${project_directory}/CHANGELOG.md"

if (( $# != 1 )); then
  print -r -- "Usage: Tools/release-notes.sh <version>" >&2
  exit 2
fi
readonly version=$1

# The section starts at "## [version]" and ends at the next "## [" heading
# or at the link references ("[1.0.0]: https://...") at the end of the file.
section=$(awk -v heading="## [${version}]" '
  index($0, "## [") == 1 {
    if (in_section) { exit }
    if (index($0, heading) == 1) { in_section = 1; next }
  }
  /^\[[^]]+\]: / { if (in_section) { exit } }
  in_section { print }
' "${changelog_file}")

if [[ -z "${section//[[:space:]]/}" ]]; then
  print -r -- "ERROR: CHANGELOG.md has no notes for version ${version}" >&2
  exit 1
fi

# Remove the blank lines before the first line and after the last line of the section.
print -r -- "${section}" | awk 'NF { started = 1 } started' | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}'
