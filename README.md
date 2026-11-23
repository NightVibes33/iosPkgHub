# PKG Sender

Native iOS app for managing and sending PlayStation 4 PKG files through Remote Package Installer (network mode) or the included payload bridge (USB mode).

**iOS 16+ · Xcode 27 / macOS 27 CI · English and Arabic · Network + USB**

- [Builds and unsigned IPA artifacts](https://github.com/NightVibes33/iosPkgHub/actions/workflows/build.yml)
- [Repository](https://github.com/NightVibes33/iosPkgHub)
- [Releases](https://github.com/NightVibes33/iosPkgHub/releases)

## Features

- Network package transfer through PS4 Remote Package Installer (RPI).
- USB bridge mode using the bundled `pkgusb.elf` payload.
- GAME, UPDATE, and DLC package metadata.
- Local PKG library, artwork, and Game Hub.
- Multi-package queue, transfer progress, speed, and ETA.
- Transfer history and diagnostics.
- GoldHEN FTP tools.
- English and Arabic interface.
- PKG files are transferred locally, not uploaded to a cloud service.

## Transfer modes

### Network mode

Network mode uses PS4 Remote Package Installer.

1. Start Remote Package Installer on the PS4.
2. Connect the iPhone and PS4 to a network where they can reach one another.
3. Enter the PS4 IP address.
4. Set the RPI port in **Settings → PlayStation**. The default is `12800`.
5. Select a PKG and send it.

The iPhone hosts the selected PKG over HTTP. The app submits the package URL to RPI using `POST /api/install`. The local HTTP listener uses an operating-system-selected port, except the iPhone Personal Hotspot path, which uses port `8080`.

Progress is calculated from unique byte ranges sent by the iPhone. Repeated, overlapping, and out-of-order range requests are not counted twice.

### USB mode

USB mode is not ordinary USB mass-storage copying. The app includes a prebuilt PS4 ELF payload named `pkgusb.elf` and implements the iPhone-side TCP protocol endpoint.

The iPhone app starts its TCP bridge on port `11112` for an active transfer and closes the listener when that transfer cycle ends. Its bridge understands these newline-delimited commands:

- `HELLO` → `PKGBRIDGE/2 READY`
- `INFO` → package size and filename, once a transfer is armed
- `READ <offset> <length>` → `DATA <offset> <length>` followed by that byte range

The bundled ELF is a binary-only dependency in this repository. Its source code is not included, so its USB enumeration, USBMUX implementation, and end-to-end compatibility cannot be audited from the Swift source alone. For USB mode to work, the payload must establish the matching connection to the iPhone bridge and speak the protocol above.

#### USB ports

| Port | Side | Purpose | Setting |
| --- | --- | --- | --- |
| `9090` | PS4 | GoldHEN BinLoader payload injection | Configurable |
| `11112` | iPhone | PKGBRIDGE/2 TCP listener | Fixed by app/payload protocol |
| `12800` | PS4 | Remote Package Installer | Configurable |

The app does not let you change port `11112` independently because the bundled payload must use the same endpoint.

#### USB setup

1. Enable GoldHEN and its BinLoader on the PS4.
2. Confirm the PS4 IP address is reachable from the iPhone for the initial payload injection.
3. Connect the iPhone directly to a PS4 USB data port using a data-capable cable.
4. Open PKG Sender, select **USB**, choose a PKG, and tap **Send to PlayStation**.
5. Keep PKG Sender open while the payload requests the package.

The initial ELF injection is sent over TCP to the configured BinLoader port. The package-data path is expected to use the payload's USB bridge. USB mode is therefore not completely network-free.

#### USB progress and completion

The iPhone counts unique PKG byte ranges only after the corresponding Network.framework send callbacks complete. Repeated, overlapping, and out-of-order reads do not inflate progress.

A 100% byte counter means all unique PKG ranges have been processed by the iPhone-side bridge. It is **not** a BGFT installation-success acknowledgment. Confirm the final install result on the PS4 itself.

If no package data arrives for three minutes after payload injection, the app stops the transfer and reports a stalled bridge instead of leaving the UI spinning forever.

## Port settings

Open **Settings → PlayStation**:

- **RPI port** controls network-mode Remote Package Installer. Default: `12800`.
- **BinLoader port** controls the TCP connection used to inject `pkgusb.elf`. Default: `9090`.
- **iPhone bridge port** is fixed at `11112` to match the bridge protocol.

Changing the RPI port does not change the BinLoader or iPhone bridge ports.

## Requirements

### General
- iPhone or iPad running iOS 16 or later.
- A compatible PS4 environment.
- A compatible installation method for an unsigned IPA.

### Network
- Remote Package Installer running on the PS4.
- iPhone and PS4 can communicate over the local network.

### USB
- GoldHEN with BinLoader enabled and reachable for initial payload injection.
- A direct, data-capable USB connection.
- A payload build compatible with the app's `PKGBRIDGE/2` protocol.

## Install

Download the latest successful **PKGSender iOS 27 unsigned IPA** from the [GitHub Actions workflow](https://github.com/NightVibes33/iosPkgHub/actions/workflows/build.yml), open the successful run, then download its artifact.

The IPA is deliberately unsigned and has no Apple distribution signature or provisioning profile. It must be installed through a compatible signing/sideloading method or an environment that accepts unsigned app bundles. It will not install on a stock iPhone simply by opening the IPA.

## Build from source

### Requirements
- macOS 27 with Xcode 27 and the iOS 27 SDK.
- XcodeGen.

### Generate and test
```sh
brew install xcodegen
xcodegen generate

xcodebuild test \
  -project PKGSender.xcodeproj \
  -scheme PKGSender \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
```

### Build the unsigned device app
```sh
xcodebuild build \
  -project PKGSender.xcodeproj \
  -scheme PKGSender \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""
```

The GitHub Actions workflow uses the `xcode-27` hosted runner, which provides macOS 27 and Xcode 27 on Apple Silicon. It verifies the iOS SDK, runs byte-range unit tests on an iOS 27 simulator, builds the Release device app without code signing, checks the bundled payload hash and app bundle, and uploads a validated IPA plus build metadata.

CI can validate compilation, unit tests, bundle packaging, and payload integrity. It cannot prove a physical iPhone-to-PS4 USB transfer or BGFT installation. Those still require the actual console, phone, cable, and compatible payload.

## Diagnostics

The app writes USB bridge diagnostics to:

- iPhone: `Documents/PKGSender-USBBridge.log`

The PS4 payload is a prebuilt binary, so its own diagnostic paths and messages depend on that payload build. Do not assume a particular PS4 log path unless the payload documents or emits it.

For a USB failure, separate the stages:
1. BinLoader TCP connection and ELF injection.
2. USB payload startup and iPhone device/bridge connection.
3. `HELLO` protocol handshake on port `11112`.
4. `INFO` response for the selected package.
5. `READ` responses and byte-range progress.

## Privacy

Package files are served locally between the iPhone and PS4. The app does not upload PKG files to a cloud service. Library data and transfer history are stored on the device.

## Credits

This repository preserves the existing app and source structure. PKG Sender is an independent project and is not affiliated with Sony Interactive Entertainment.
