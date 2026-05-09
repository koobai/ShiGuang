[English](README.md) | [简体中文](README.zh-CN.md)

# ShiGuang

<p align="center">
  <img src="logo.webp" width="120" alt="ShiGuang logo">
</p>

ShiGuang is a macOS menu bar utility that lets you adjust the hardware brightness of an external display using the keyboard brightness keys.

<p align="center">
  <img src="app.webp" width="720" alt="ShiGuang screenshot">
</p>

This project is currently developed and tested mainly in the following environment:

- Device: Mac mini M4
- Display: Redmi G27U
- System: macOS 26.4.1

Other Mac models, external displays, and connection methods have not been fully tested yet. If your display does not support DDC/CI, or macOS cannot access display brightness through the current interface, ShiGuang may not work as expected.

## Features

- Adjust external display brightness with the keyboard brightness up and down keys
- Change brightness in 5% steps
- Show the current brightness percentage while adjusting
- Run as a persistent macOS menu bar app without occupying the Dock
- Use a system sun icon in the menu bar
- View the current brightness from the menu bar
- Adjust brightness manually with a slider in the menu
- Quit quickly from the menu
- Remember the last brightness value and try to restore it on the next launch
- Reset the display connection after system or display wake to improve reliability
- Control real hardware brightness through DDC/CI instead of applying a software dimming overlay

## Usage

After launching ShiGuang, it appears in the macOS menu bar.

On first launch, macOS may ask for Accessibility permission. This permission is required to listen for the keyboard brightness keys. Once granted, you can use those keys to control the external display brightness directly.

You can also click the sun icon in the menu bar and adjust brightness manually with the slider.

## Installation

This project is currently distributed without an Apple Developer account for code signing and notarization, so macOS may warn that the app is from an unidentified developer. This is expected.

Recommended installation flow:

- Download the latest `.dmg` package from GitHub Releases
- Open the `.dmg`
- Drag `拾光.app` into the Applications folder
- Open Applications and find `拾光`
- If macOS blocks the first launch, hold `Control`, click the app, and choose `Open`

If macOS still blocks the app:

- Open System Settings
- Go to Privacy & Security
- Find the security notice related to `拾光` near the bottom
- Click `Open Anyway` or the equivalent button

After the app opens successfully, macOS may still request Accessibility permission. The keyboard brightness key monitoring will only work after you allow it.

## Compatibility

ShiGuang is currently aimed at the following setup:

- Apple Silicon Mac
- macOS menu bar workflow
- External display
- A monitor with DDC/CI brightness control support

The known tested setup is Mac mini M4 plus Redmi G27U. Other devices may work in theory, but have not been verified yet.

Common reasons why brightness control may fail:

- DDC/CI is not enabled on the monitor
- The monitor, adapter, dock, or cable does not support DDC communication
- The current macOS version limits access to the underlying display control interface
- You are using an internal display instead of an external monitor

## Maintenance

This tool is updated around personal use and is primarily built for the author's own daily workflow.

## Changelog

See [CHANGELOG.md](CHANGELOG.md). The release notes are currently maintained in Chinese.

## Build

This project is developed with Xcode.

Open it in Xcode with:

```bash
open ShiGuang.xcodeproj
```

Or build it from the command line:

```bash
xcodebuild -project ShiGuang.xcodeproj -scheme ShiGuang -configuration Release build
```

## License

This project is released under the MIT License.
