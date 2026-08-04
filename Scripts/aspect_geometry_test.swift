#!/usr/bin/env swift
/**
 Deterministic aspect-fit geometry checks for Lumina Phase 1B.
 Mirrors `AspectFitGeometry` — run on macOS: swift Scripts/aspect_geometry_test.swift
 */
import CoreGraphics
import Foundation

struct FittedRect {
    let origin: CGPoint
    let size: CGSize
    let drawableSize: CGSize

    var normalizedInDrawable: CGRect {
        guard drawableSize.width > 0, drawableSize.height > 0 else { return .zero }
        return CGRect(
            x: origin.x / drawableSize.width,
            y: origin.y / drawableSize.height,
            width: size.width / drawableSize.width,
            height: size.height / drawableSize.height
        )
    }
}

func fit(imageSize: CGSize, drawableSize: CGSize) -> FittedRect {
    guard imageSize.width > 0, imageSize.height > 0,
          drawableSize.width > 0, drawableSize.height > 0 else {
        return FittedRect(origin: .zero, size: .zero, drawableSize: drawableSize)
    }
    let scale = min(drawableSize.width / imageSize.width, drawableSize.height / imageSize.height)
    let fittedW = imageSize.width * scale
    let fittedH = imageSize.height * scale
    return FittedRect(
        origin: CGPoint(x: (drawableSize.width - fittedW) * 0.5, y: (drawableSize.height - fittedH) * 0.5),
        size: CGSize(width: fittedW, height: fittedH),
        drawableSize: drawableSize
    )
}

func aspectPreserved(imageSize: CGSize, drawableSize: CGSize, fitted: FittedRect, tolerance: CGFloat = 1e-3) -> Bool {
    guard imageSize.width > 0, imageSize.height > 0, fitted.size.width > 0 else { return false }
    let imageAspect = imageSize.width / imageSize.height
    let fittedAspect = fitted.size.width / fitted.size.height
    guard abs(imageAspect - fittedAspect) <= tolerance else { return false }
    let expectedW = imageSize.width * min(drawableSize.width / imageSize.width, drawableSize.height / imageSize.height)
    return abs(fitted.size.width - expectedW) <= tolerance
}

struct Case {
    let name: String
    let image: CGSize
    let drawable: CGSize
    let check: (FittedRect) -> Bool
}

let cases: [Case] = [
    Case(name: "3:2 landscape", image: CGSize(width: 3000, height: 2000), drawable: CGSize(width: 1200, height: 800)) { f in
        aspectPreserved(imageSize: CGSize(width: 3000, height: 2000), drawableSize: CGSize(width: 1200, height: 800), fitted: f)
    },
    Case(name: "2:3 portrait", image: CGSize(width: 2000, height: 3000), drawable: CGSize(width: 400, height: 900)) { f in
        aspectPreserved(imageSize: CGSize(width: 2000, height: 3000), drawableSize: CGSize(width: 400, height: 900), fitted: f)
    },
    Case(name: "square", image: CGSize(width: 1000, height: 1000), drawable: CGSize(width: 800, height: 600)) { f in
        abs(f.size.width - f.size.height) < 1e-3
    },
    Case(name: "panorama", image: CGSize(width: 6000, height: 1500), drawable: CGSize(width: 1400, height: 700)) { f in
        abs(f.size.width - 1400) < 1
    },
    Case(name: "narrow window", image: CGSize(width: 1600, height: 900), drawable: CGSize(width: 320, height: 900)) { f in
        abs(f.size.width - 320) < 1
    },
    Case(name: "wide window", image: CGSize(width: 1600, height: 900), drawable: CGSize(width: 1600, height: 400)) { f in
        abs(f.size.height - 400) < 1
    },
]

var failed = 0
for test in cases {
    let fitted = fit(imageSize: test.image, drawableSize: test.drawable)
    if test.check(fitted) {
        print("PASS  \(test.name)")
    } else {
        print("FAIL  \(test.name)  fitted=\(fitted.size)")
        failed += 1
    }
}

if failed > 0 {
    fputs("\(failed) aspect-fit test(s) failed\n", stderr)
    exit(1)
}
print("All aspect-fit geometry tests passed.")
