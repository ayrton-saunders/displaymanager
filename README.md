# Display Manager

A macOS menu bar app for quickly switching between mirrored and extended display modes.

## Features

- Menu bar icon for quick access
- Switch between mirrored and extended display modes
- Built with SwiftUI
- Uses `displayplacer` for display configuration

## Requirements

- macOS 12.0 or later
- `displayplacer` CLI tool

## Installation

1. Install `displayplacer`:
   ```bash
   brew install displayplacer
   ```

2. Build and run the app using Xcode

## Usage

1. Click the menu bar icon (two rectangles symbol)
2. Select either "Mirrored Mode" or "Extended Mode"
3. The display configuration will be applied automatically

## Hardware

Tested on:
- 2024 MacBook Pro 16 inch
- Dell S2725QC display

## Notes

- The app runs as a menu bar utility (no dock icon)
- Requires `displayplacer` to be installed via Homebrew
- First time setup may require granting display permissions
