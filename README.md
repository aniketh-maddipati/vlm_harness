# Lumina

Mac app for culling a shoot. Open a folder or an SD card. Keep with P, cut with X.

Apple Silicon. macOS 14+. Xcode 15+ from the App Store.

```bash
open design/hifi-v5.html
```

Stills. Chrome reference. Not the Mac app.

![Open](design/grabs/hifi_open.png)

Open. Work still on the table, and finished shoots. Drop a folder or an SD card.

![Table](design/grabs/hifi_table_cull.png)

Table. Rows of photographs. Keep with P, cut with X. Export sits in the corner once something is kept.

![Crop](design/grabs/hifi_crop.png)

Edit and crop. The photograph slides under a fixed window. Return writes it. Esc leaves it.

![Receipt](design/grabs/hifi_receipt.png)

After Return. A receipt names what just happened. Export stays in the corner.

```bash
open design/play.html
```

Browser mock. Click the sequence, or click the window and use P, X, arrows, Return, 4, Esc, Space, J, ?. Not the Mac app.

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

3. Point the CLI at Xcode. Open Xcode.app once if it asks for a license.

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

4. Install exiftool. The app looks at `/opt/homebrew/bin/exiftool`.

```bash
brew install exiftool
```

5. Build Debug.

```bash
xcodebuild -project Lumina.xcodeproj -scheme Lumina -resolvePackageDependencies
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derivedData \
  build
```

6. Open the app.

```bash
open .derivedData/Build/Products/Debug/Lumina.app
```

Click **Choose a folder**, or drop a folder onto the window. For an SD card, pick `DCIM` on the volume. Files stay on disk. Keep shoots out of this repo.

Hold `?` for keys. Vision is on-device. No extra model.

7. Playground, optional. Hot reload needs InjectionIII in `/Applications`.

```bash
xcodebuild -project Lumina.xcodeproj -scheme LuminaPlayground -resolvePackageDependencies
xcodebuild -project Lumina.xcodeproj -scheme LuminaPlayground -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derivedData \
  build
open .derivedData/Build/Products/Debug/LuminaPlayground.app
```
