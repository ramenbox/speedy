# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [1.0.1] - 2026-10-07

### Removed

- The one-time import of `~/Documents/Office Speedtest/results.csv`. Speedy no longer reads the Documents folder, so macOS does not ask for access to it.

## [1.0.0] - 2026-10-07

### Added

- Menu bar app that runs `networkQuality` on a schedule and stores each result in `~/Library/Application Support/Speedy/speedy.sqlite`.
- Panel below the menu bar icon with a status label, the last result, and History and Settings tabs.
- Status label: green for active, blue with a spinner and the elapsed time while a test runs, grey for paused, red for stopped.
- Menu bar gauge whose needle moves while a test runs. With "Reduce motion" on, the needle stays full.
- Chart of download and upload, and a list of tests, for today, 7 days, 30 days or all.
- Average, minimum and maximum of download, upload and ping per range.
- Test interval setting: 15, 30 or 60 minutes.
- Pause / Resume, and "Run now" also while tests are paused.
- Notifications for a slow download (10, 25, 50 or 100 Mbps limit) and for a failed test.
- A plain message for a network error from `networkQuality`, for example `No internet connection`.
- CSV export for a selected range, and Quit Speedy (⌘Q), in the ⋯ menu.
- Start at login and delete history.
- One-time import of `~/Documents/Office Speedtest/results.csv`.
- Checks for the core logic (`./checks.sh`).

[1.0.1]: https://github.com/ramenbox/speedy/releases/tag/v1.0.1
[1.0.0]: https://github.com/ramenbox/speedy/releases/tag/v1.0.0
