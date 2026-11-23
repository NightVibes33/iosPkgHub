# PKG Sender

Native iPhone and iPad app for sending PS4 PKG files through Remote Package Installer (network mode) or the bundled GoldHEN USBMUX payload (USB mode).

[![Build iOS 27 unsigned IPA](https://github.com/NightVibes33/iosPkgHub/actions/workflows/build.yml/badge.svg)](https://github.com/NightVibes33/iosPkgHub/actions/workflows/build.yml)

**iOS 16+ · iOS 27 / Xcode 27 CI · English and Arabic · Network + USB**

- [Actions builds and unsigned IPA artifacts](https://github.com/NightVibes33/iosPkgHub/actions/workflows/build.yml)
- [Releases](https://github.com/NightVibes33/iosPkgHub/releases)
- [Source repository](https://github.com/NightVibes33/iosPkgHub)

---

## Screenshots

| Home — Network | Home — USB |
| --- | --- |
| <img src="assets/home-network.jpg" width="320"> | <img src="assets/home-usb.jpg" width="320"> |

| Library | Game Hub |
| --- | --- |
| <img src="assets/library.jpg" width="320"> | <img src="assets/game-hub.jpg" width="320"> |

| Transfer History |
| --- |
| <img src="assets/history-usb.jpg" width="320"> |

## Features

- Network transfers through PS4 Remote Package Installer (RPI).
- USB transfers through the bundled PS4 payload and the iPhone-side USBMUX bridge.
- GAME, UPDATE, and DLC package metadata support.
- Local PKG library, artwork, and Game Hub.
- Multi-package queue, progress, speed, and ETA.
- Transfer history with file size, transferred bytes, transfer method, and timing.
- GoldHEN FTP tools.
- Arabic and English interface.
- Local-only package transfer. PKG files are not uploaded to a cloud service.

## Transfer modes

### Network mode

Network mode uses PS4 Remote Package Installer.

1. Start Remote Package Installer on the PS4.
2. Put the iPhone/iPad and PS4 on a network where they can reach each other.
3. Enter the PS4 IP address.
4. Set the RPI port in **Settings → PlayStation**. The default is \`12800\`.
5. Tap **Check Connection**, select a PKG, and send.

The iPhone hosts the PKG over HTTP. The app advertises the local HTTP URL to RPI, which retrieves the package using byte-range requests. The iPhone's HTTP listening port is selected by the operating system for normal network mode; it is not the RPI port.

When the iPhone Personal Hotspot path is selected, the app uses its dedicated HTTP server on port \`8080\`.

### USB mode

USB mode uses a custom payload included as \`pkgusb.elf\`. The payload is not a generic USB mass-storage copy operation.

The bundled ELF was inspected as a 64-bit little-endian x86-64 PS4 ELF. Its embedded strings and symbols identify the following components:

- PS4 USB host operations through \`sceUsbd\` (device enumeration, interface configuration, and bulk transfers).
- A USBMUX v2 transport for communicating with the connected iPhone.
- A connection to the iPhone-side TCP bridge on port \`11112\`.
- A PS4-side HTTP proxy for the BGFT install task, normally using port \`11113\` (the payload can select another isolated port if that listener is already occupied).
- Direct BGFT package registration and install-task startup.

The data path is:

1. PKG Sender opens the selected package and starts its iPhone-side bridge on TCP \`11112\`. The loopback-only listener closes when that transfer cycle ends.
2. The app injects \`pkgusb.elf\` into GoldHEN BinLoader over TCP. The default BinLoader port is \`9090\` and can be changed in **Settings → PlayStation**.
3. The PS4 payload enumerates the connected iPhone through its USB host controller and establishes the payload's USBMUX v2 bridge.
4. The payload requests package information and byte ranges from the iPhone bridge using the \`PKGBRIDGE/2\` protocol.
5. The payload exposes the package to the PS4 BGFT installer through its internal HTTP proxy.

**Important:** the initial payload injection still requires the PS4 IP address and a reachable BinLoader TCP port. After the payload starts, the PKG data path uses the physical USB connection. USB mode is therefore not a completely network-free setup.

#### USB ports

| Port | Side | Purpose | User-configurable |
| --- | --- | --- | --- |
| \`9090\` | PS4 | GoldHEN BinLoader payload injection | Yes |
| \`11112\` | iPhone | USBMUX / PKGBRIDGE TCP endpoint | No, fixed by the payload protocol |
| \`11113\` | PS4 | Internal BGFT HTTP proxy | Payload-managed |
| \`12800\` | PS4 | Remote Package Installer for Network mode | Yes |

Do not change the iPhone bridge port independently of the bundled ELF. The iPhone bridge and PS4 payload must use the same protocol and port.

#### USB setup

1. Enable GoldHEN and its BinLoader on the PS4.
2. Confirm the PS4 IP address is reachable from the iPhone for the initial payload injection.
3. Connect the iPhone directly to a PS4 USB data port with a data-capable cable.
4. Open PKG Sender and select **USB**.
5. Choose the PKG and tap **Send to PlayStation**.
6. Keep PKG Sender in the foreground while the payload reads the package.

A charge-only cable will not work. If the bridge does not connect, check the cable, USB connection, BinLoader port, and the PS4 payload diagnostics.

#### What 100% means

USB progress is calculated from unique package byte ranges after the iPhone's Network.framework send callbacks complete. Duplicate and out-of-order range reads are counted only once.

Reaching 100% means all unique PKG byte ranges have been served through the bridge. It does **not** mean the app has received a final BGFT installation-success acknowledgment. Confirm the final installation state on the PS4.

## Port settings

Open **Settings → PlayStation** to edit:

- **RPI port**: network-mode Remote Package Installer, default \`12800\`.
- **BinLoader port**: USB payload injection, default \`9090\`.

The USBMUX bridge port \`11112\` and PS4 internal proxy port \`11113\` are shown as read-only because they are part of the payload protocol.

## Requirements

### General
- iPhone or iPad running iOS 16 or later.
- Compatible PS4 environment.
- A compatible installation method for an unsigned IPA.

### Network mode
- Remote Package Installer running on the PS4.
- iPhone and PS4 can communicate over the local network.

### USB mode
- GoldHEN with BinLoader enabled and reachable for the initial payload injection.
- A direct, data-capable USB cable between the iPhone/iPad and PS4.
- Keep PKG Sender active during the transfer.

## Installation

The GitHub Actions workflow builds an **unsigned** iOS device IPA. Download the artifact from the latest successful [Actions run](https://github.com/NightVibes33/iosPkgHub/actions/workflows/build.yml).

An unsigned IPA has no Apple distribution signature or provisioning profile. It must be installed using a compatible signing/sideloading method or an environment that accepts unsigned app bundles. It is not directly installable on a stock, non-jailbroken iPhone merely by opening the file.

## Build from source

The project uses Swift, SwiftUI, and XcodeGen.

### Requirements
- macOS with Xcode 27 and the iOS 27 SDK.
- XcodeGen.

### Generate and test
~~~sh
brew install xcodegen
xcodegen generate

xcodebuild test \
  -project PKGSender.xcodeproj \
  -scheme PKGSender \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
~~~

### Build an unsigned device app
~~~sh
xcodebuild build \
  -project PKGSender.xcodeproj \
  -scheme PKGSender \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""
~~~

To package the resulting \`PKGSender.app\`, place it inside a folder named \`Payload\` and ZIP that folder with the \`.ipa\` extension. The repository's GitHub Actions workflow performs this packaging, validates the archive, and verifies the bundled payload SHA-256.

### CI verification

The \`xcode-27\` GitHub-hosted runner uses macOS 27 and Xcode 27. The workflow:

- Verifies the macOS and iOS SDK versions.
- Generates the Xcode project.
- Runs the byte-range coverage unit tests on an iOS 27 simulator.
- Builds the Release iOS device app without code signing.
- Verifies the app bundle, Info.plist, and bundled ELF hash.
- Packages and validates the unsigned IPA.
- Uploads the IPA and build metadata as a 30-day workflow artifact.

CI cannot validate the physical iPhone-to-PS4 USB link or complete a real BGFT installation. Those require the actual devices and cable.

## Diagnostics

The app includes a diagnostics screen and writes transfer diagnostics locally. For USB issues, capture the app's USB bridge log and the PS4 payload log at:

- iPhone app: \`Documents/PKGSender-USBBridge.log\`
- PS4 payload: \`/data/pkg-usb-payload.log\` and \`/mnt/usb0/pkg-usb-payload.log\`

Useful failure points include:
- BinLoader connection failure on the configured port.
- USB device enumeration or interface-claim failure.
- USBMUX bridge initialization failure.
- iPhone TCP bridge connection failure on \`11112\`.
- PS4 HTTP proxy bind failure.
- BGFT metadata or install-task failure.

## Privacy

Package data is transferred locally between the iPhone and PS4. The app does not upload PKG files to a cloud service. Library data, metadata, and transfer history are stored on the device.

## Credits

The app credits the original project author, T2oDna. Repository maintenance and this repair work are tracked in [NightVibes33/iosPkgHub](https://github.com/NightVibes33/iosPkgHub).

PKG Sender is an independent project and is not affiliated with Sony Interactive Entertainment.
