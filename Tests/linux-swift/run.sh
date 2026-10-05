#!/usr/bin/env bash
# Linux sandbox for the app's Foundation-only Swift: compiles Lumina/Sets/Core/{SetsFileOps,
# SetsShootStore,SetsExport,SetsIngest,SetsWorkingFiles,SetsDownloadsWatcher,SetsExternalLinks,
# SetsPageStore,SetsSources}.swift and Lumina/Sets/Look/{LookString,LookRules,LookMath,
# LookCanvasSchedule,LookWarmPlan,LookByteCache,LookRawPolicy,LookLensShading}.swift unchanged with Swift 6.1 (Docker image
# swift:6.1-noble) and runs the logic tests that don't need Core Image / ImageIO / AppKit:
#   SetsSidecarTests, SetsTrustTests, SetsFileOpsTests,
#   LookStringTests, LookMathTests (the look grammar and the stage maths on synthetic ramps),
#   LookCanvasTests (the canvas schedule, the warm-up plan, the byte cache, the RAW tiers and the pin rule),
#   SetsShootStoreTests (a shoot id from the page stays inside the store),
#   SetsShootImportTests (sessions from before the sandbox are brought over, R1e),
#   SetsPicksCopyTests (picks land verified one folder down, sources untouched),
#   SetsIngestDNGTests (DNGs listed like ARWs; only SetsIngest.list, no ImageIO),
#   SetsWorkingFilesTests, SetsDownloadsWatcherTests, SetsExternalLinksTests, SetsPageStoreTests,
#   SetsSourcesTests (against fake bookmark calls; its real-bookmark test skips itself here, see LinuxStubs).
# SetsSources is compiled without SetsAccess.swift: SetsAccess is the @MainActor owner of
# security-scoped access (start/stop, security-scoped bookmarks: no Linux counterpart), so
# LinuxStubs supplies only its `Calls` value type, the one thing SetsSources uses.
# Not covered here (Mac only): SetsBridge, SetsSchemeHandler, SetsCardWatcher (AppKit/WebKit),
# SetsAccess (security-scoped resources and bookmarks), SetsNear (Vision, ImageIO),
# SetsLookExport, LookPipeline/LookKernels/LookRenderer (Core Image, Metal),
# SetsIngestTests, SetsPageBytesTests, SetsNearTests and LookPipelineTests (ImageIO, Vision, bundle, Core Image),
# SetsAccessTests (SetsAccess), SetsBridgeOpsTests, SetsCardAccessTests, SetsIngestBoundsTests (SetsBridge,
# WebKit), SetsCardDNGTests (SetsCardWatcher), SetsSchemeHandlerURLTests (WebKit),
# SetsPageRecoveryTests (SetsWindowController, in SetsRootView: WebKit/AppKit).
# Not tried here yet: SetsExportJournalSandboxTests, SetsIngestLinksTests.
#
#   bash Tests/linux-swift/run.sh            # needs docker; pulls swift:6.1-noble once
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
B="$HERE/Build"; rm -rf "$B"; mkdir -p "$B/Lumina" "$B/Tests"
for f in SetsFileOps SetsShootStore SetsExport SetsIngest SetsWorkingFiles SetsDownloadsWatcher SetsExternalLinks SetsPageStore SetsSources; do cp "$ROOT/Lumina/Sets/Core/$f.swift" "$B/Lumina/"; done
for f in LookString LookRules LookMath LookCanvasSchedule LookWarmPlan LookByteCache LookRawPolicy LookLensShading; do cp "$ROOT/Lumina/Sets/Look/$f.swift" "$B/Lumina/"; done
cp "$ROOT/Lumina/Sets/Look/rules-v1.json" "$B/rules-v1.json"     # LookMathTests read it via LUMINA_RULES (only this folder is mounted)
# swift-corelibs-foundation's FileManager.replaceItemAt fails on Linux and deletes the original
# (checked with swift 6.1). Darwin's is correct. In this copy only, the replace is the POSIX rename
# it stands for (atomic, same folder), so the rest of the write path runs as written.
python3 - "$B/Lumina" <<'PY'
import glob, sys
for f in glob.glob(sys.argv[1] + '/*.swift'):
    s = open(f).read()
    t = s.replace('_ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)', 'guard rename(tmp.path, url.path) == 0 else { throw Failure("rename failed: \\(String(cString: strerror(errno)))") }')
    if t != s: open(f, 'w').write(t); print('linux: replaceItemAt → rename(2) in', f.split('/')[-1])
PY
cat > "$B/Lumina/LinuxStubs.swift" <<'SWIFT'
import Foundation
// SetsExport's render path uses Core Image (SetsLookExport: the Edit step's look string through
// LookPipeline), Mac only.
enum SetsLookExport {
    struct Outcome: Equatable { var decoder: Int?; var fellBackFrom: Int?; var reason: String?; var ms: Double = 0; var label: String { "" } }
    static func render(raw url: URL, look: String, px: Int?, format: String, decoder: Int?) throws -> (Data, Outcome) { throw SetsFileOps.Failure("no Core Image on Linux") }
}
// Darwin-only: F_NOCACHE (bypass the buffer cache) becomes F_GETFD, a no-op; the "important usage"
// capacity falls back to the plain available capacity, as the app's code already does when it's 0.
let F_NOCACHE = F_GETFD
extension URLResourceKey { static let volumeAvailableCapacityForImportantUsageKey = URLResourceKey(rawValue: "NSURLVolumeAvailableCapacityForImportantUsageKey") }
extension URLResourceValues { var volumeAvailableCapacityForImportantUsage: Int64? { nil } }
// SetsSources takes SetsAccess.Calls; SetsAccess itself (Lumina/Sets/Core/SetsAccess.swift) is not
// compiled here. Same fields as the app's Calls. `.system` has no security-scoped bookmarks on
// Linux, so it refuses: SetsSourcesTests' real-bookmark test then skips itself (its XCTSkip).
enum SetsAccess {
    struct Calls {
        var start: (URL) -> Bool
        var stop: (URL) -> Void
        var resolve: (Data) throws -> (url: URL, stale: Bool)
        var bookmark: (URL) throws -> Data
        var exists: (URL) -> Bool
        static let system = Calls(
            start: { _ in false },
            stop: { _ in },
            resolve: { _ in throw SetsFileOps.Failure("no security-scoped bookmarks on Linux") },
            bookmark: { _ in throw SetsFileOps.Failure("no security-scoped bookmarks on Linux") },
            exists: { url in
                var dir: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
            })
    }
}
SWIFT
cp "$ROOT/LuminaLogicTests/SetsTrustTests.swift" "$ROOT/LuminaLogicTests/LookStringTests.swift" "$ROOT/LuminaLogicTests/LookMathTests.swift" \
   "$ROOT/LuminaLogicTests/LookCanvasTests.swift" "$ROOT/LuminaLogicTests/LookLensShadingTests.swift" \
   "$ROOT/LuminaLogicTests/SetsShootStoreTests.swift" "$ROOT/LuminaLogicTests/SetsShootImportTests.swift" \
   "$ROOT/LuminaLogicTests/SetsPicksCopyTests.swift" "$ROOT/LuminaLogicTests/SetsIngestDNGTests.swift" \
   "$ROOT/LuminaLogicTests/SetsWorkingFilesTests.swift" "$ROOT/LuminaLogicTests/SetsDownloadsWatcherTests.swift" \
   "$ROOT/LuminaLogicTests/SetsExternalLinksTests.swift" "$ROOT/LuminaLogicTests/SetsPageStoreTests.swift" \
   "$ROOT/LuminaLogicTests/SetsSourcesTests.swift" "$B/Tests/"
# SetsFileOpsTests and SetsSidecarTests without any test that needs Core Image, or the locked-file
# test (Linux has no user-immutable flag for FileManager to set).
for t in SetsFileOpsTests SetsSidecarTests; do
python3 - "$ROOT/LuminaLogicTests/$t.swift" "$B/Tests/$t.swift" <<'PY'
import re, sys
src = open(sys.argv[1]).read().replace('import CoreImage\n', '')
out, i = [], 0
for m in re.finditer(r'\n    func test\w+\(\)[^{]*\{', src):
    pass
lines, keep, depth, buf, drop = src.split('\n'), [], 0, [], False
for ln in lines:
    if depth == 0 and re.match(r'    func test\w+\(', ln):
        buf, drop = [ln], False
        depth = ln.count('{') - ln.count('}')
        if depth == 0: keep.extend(buf); buf = []
        continue
    if buf:
        buf.append(ln); depth += ln.count('{') - ln.count('}')
        if depth == 0:
            body = '\n'.join(buf)
            if not re.search(r'CIImage|CIContext|CGColorSpace|\.immutable: true', body): keep.extend(buf)
            else: print('linux: skipped', re.search(r'func (test\w+)', buf[0]).group(1))
            buf = []
        continue
    keep.append(ln)
open(sys.argv[2], 'w').write('\n'.join(keep))
PY
done
docker run --rm -v "$HERE:/work" -w /work -e LUMINA_RULES=/work/Build/rules-v1.json swift:6.1-noble bash -c '
  swift build --build-tests > build.log 2>&1 || { grep -E "error" build.log | sort -u; exit 1; }
  swift test > test.log 2>&1; s=$?
  grep -E "error:|failed \(|Executed .* tests" test.log | sort -u | tail -40
  exit $s'
