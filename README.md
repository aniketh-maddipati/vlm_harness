# Lumina

Mac app for culling a shoot. Open a folder or an SD card. Keep with P, cut with X.

Needs an Apple Silicon Mac, macOS 14+, Xcode 15+ from the App Store, and Homebrew.

## Setup

```bash
git clone https://github.com/aniketh-maddipati/vlm_harness.git
cd vlm_harness
bash Scripts/bootstrap.sh
```

If Homebrew is not installed yet, do this first, then re-run bootstrap:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
bash Scripts/bootstrap.sh
```

If Xcode is installed but `xcodebuild` fails:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

Open Xcode once after installing it so extra components can finish.

## Run

```bash
open Lumina.xcodeproj
```

Scheme `Lumina`. Press ⌘R.

## Photographs

Click **Choose a folder**, or drop a folder onto the window.

For an SD card: plug it in, then pick the card in that dialog. Camera cards are usually the `DCIM` folder on the volume.

RAW, JPG, HEIC, DNG, and the usual camera files all work. Files stay on disk. Nothing leaves the Mac.

Keep shoots out of this repo. Leave them on the card or in Pictures.

## Keys

Hold `?` in the app for the rest.

| Key | Action |
|-----|--------|
| arrows | move |
| `P` | keep |
| `X` | cut |
| same key again | clear the mark |
| `Return` | edit |
| `Space` | hold for loupe |
| `Esc` | back |
| `⌘O` | open another folder |
| `⌘E` | export |

## Stuck

```bash
bash Scripts/bootstrap.sh
```

exiftool has to exist at `/opt/homebrew/bin/exiftool` or `/usr/local/bin/exiftool`. The app looks there on purpose. Xcode does not load the PATH from your shell.
