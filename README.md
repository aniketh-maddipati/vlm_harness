# Lumina

Mac app for culling a shoot. Open a folder or an SD card. Keep with P, cut with X.

Apple Silicon. macOS 14+. Xcode 15+ from the App Store. Homebrew.

## Setup

```bash
git clone https://github.com/aniketh-maddipati/vlm_harness.git
cd vlm_harness
bash Scripts/bootstrap.sh
```

That script installs exiftool, builds Debug, and opens the app. If something is missing it prints the one command to run next. Then re-run bootstrap.

UI polish (playground + Inject):

```bash
bash Scripts/bootstrap.sh --dev
```

## Run

Bootstrap already opens Lumina. To build and open again:

```bash
bash Scripts/bootstrap.sh
```

Click **Choose a folder**, or drop a folder onto the window. For an SD card, pick `DCIM` on the volume. Files stay on disk. Keep shoots out of this repo.

Vision embeddings are on-device. No extra model to install. A folder of Lightroom-edited JPGs with XMP is optional taste. Hold `?` for keys.

## Design

```bash
open design/play.html
```

Browser mock. Click the sequence, or click the window and use P, X, arrows, Return, 4, Esc, Space, J, ?. Not the Mac app. Chrome stills: `design/hifi.pdf`.
