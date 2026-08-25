# Lumina

Mac app for culling a shoot. Open a folder or an SD card. Keep with P, cut with X.

Apple Silicon. macOS 14+. Xcode 15+ from the App Store, then `brew install exiftool`.

These are pictures of the Mac app.

```bash
open design/hifi-v5.html
```

![Open](design/grabs/hifi_open.png)

Shoots on the table. Drop a folder to land a new one.

![Table](design/grabs/hifi_table_cull.png)

Rows of photos. Keep with P, cut with X.

![Crop](design/grabs/hifi_crop.png)

The frame stays put. You slide the photo under it.

![Receipt](design/grabs/hifi_receipt.png)

After you apply, a small receipt. Click it to undo.

Toy you can click. Not the Mac app.

```bash
open design/play.html
```

- Mac: run the app (Xcode).
- Stills of the Mac app: `open design/hifi-v5.html`
- Click mock: `open design/play.html`
- Linux / Cursor cloud: `python3 Scripts/harness/run.py fast` before a push. The app will not build there.

Work on a branch. `python3 Scripts/harness/run.py fast` is the shared gate. Full `xcodebuild test` is Mac-only.

## Setup

1. Clone.

```bash
git clone https://github.com/aniketh-maddipati/vlm_harness.git
cd vlm_harness
```

2. Homebrew, if `brew` is missing.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

3. Install exiftool. The app looks at `/opt/homebrew/bin/exiftool`.

```bash
brew install exiftool
```

4. Open the project. Scheme `Lumina`. Command-R.

```bash
open Lumina.xcodeproj
```

Click **Choose a folder**, or drop a folder onto the window. A tiny sample is in `fixtures/sample-shoot/`. For an SD card, pick `DCIM` on the volume. Files stay on disk. Keep your own shoots out of this repo.

CLI fallback, Debug into `.derivedData`:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -project Lumina.xcodeproj -scheme Lumina -resolvePackageDependencies
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derivedData \
  build
open .derivedData/Build/Products/Debug/Lumina.app
```

5. Playground, optional. Hot reload needs InjectionIII in `/Applications`.

```bash
xcodebuild -project Lumina.xcodeproj -scheme LuminaPlayground -resolvePackageDependencies
xcodebuild -project Lumina.xcodeproj -scheme LuminaPlayground -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derivedData \
  build
open .derivedData/Build/Products/Debug/LuminaPlayground.app
```
