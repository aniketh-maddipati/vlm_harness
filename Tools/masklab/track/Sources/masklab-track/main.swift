import Foundation
import MaskLabCore

// masklab-track: decode a clip at the proxy size, run one tracker from the start frame, write one
// PNG mask per frame and timing.json (Tools/masklab/README.md). The arguments are checked first on
// every platform; the run itself needs AVFoundation and Vision (Run.swift).

func fail(_ msg: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data(("masklab-track: " + msg + "\n").utf8))
    exit(code)
}

let options: Options
do {
    options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    fail("\(error)", code: 2)
}

#if canImport(Vision) && canImport(AVFoundation)
do {
    try await run(options)
} catch {
    fail("\(error)")
}
#else
fail("needs macOS 14 (AVFoundation, Vision); arguments were fine", code: 2)
#endif
