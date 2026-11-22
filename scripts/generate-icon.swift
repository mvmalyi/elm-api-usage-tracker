#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

// Generates a crisp, macOS-style squircle app icon (AppIcon.icns) featuring a dark
// obsidian glass plate and a bold proportional progress gauge echoing the menu bar icon.

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: generate-icon.swift <output-icns-path> [optional-preview-png-path]\n", stderr)
    exit(1)
}

let outputIcnsURL = URL(fileURLWithPath: args[1])
let previewPngURL = args.count >= 3 ? URL(fileURLWithPath: args[2]) : nil

func drawAppIcon(in ctx: CGContext, size: CGFloat) {
    let s = size / 1024.0

    ctx.saveGState()
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // Standard macOS Big Sur / Sonoma / Tahoe icon safe area (824x824 centered in 1024x1024)
    let inset: CGFloat = 100.0 * s
    let iconRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let cornerRadius: CGFloat = 185.0 * s
    let squircle = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Soft ambient shadow beneath squircle
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -18 * s),
        blur: 32 * s,
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.34)
    )
    ctx.addPath(squircle)
    ctx.setFillColor(CGColor(srgbRed: 0.08, green: 0.09, blue: 0.12, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to squircle for background & specular layers
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Deep obsidian-slate vertical gradient
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let bgColors = [
        CGColor(srgbRed: 0.175, green: 0.195, blue: 0.245, alpha: 1.0), // Top lighter slate
        CGColor(srgbRed: 0.105, green: 0.118, blue: 0.155, alpha: 1.0), // Mid
        CGColor(srgbRed: 0.072, green: 0.080, blue: 0.108, alpha: 1.0)  // Bottom obsidian
    ] as CFArray
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.55, 1.0]) {
        ctx.drawLinearGradient(
            bgGradient,
            start: CGPoint(x: size * 0.5, y: iconRect.maxY),
            end: CGPoint(x: size * 0.5, y: iconRect.minY),
            options: []
        )
    }

    // Subtle top-left radial glass sheen (startRadius = 0 avoids any inner cutout artifact)
    let sheenColors = [
        CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.12),
        CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
    ] as CFArray
    if let sheenGradient = CGGradient(colorsSpace: colorSpace, colors: sheenColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            sheenGradient,
            startCenter: CGPoint(x: size * 0.35, y: iconRect.maxY - 40 * s),
            startRadius: 0,
            endCenter: CGPoint(x: size * 0.45, y: iconRect.maxY - 120 * s),
            endRadius: 560 * s,
            options: []
        )
    }

    // Circular progress ring geometry
    let center = CGPoint(x: size * 0.5, y: size * 0.5)
    let ringRadius: CGFloat = 236.0 * s
    let ringWidth: CGFloat = 86.0 * s

    // Recessed remaining track ring (subtle translucent dark glass)
    ctx.saveGState()
    ctx.setLineWidth(ringWidth)
    ctx.setStrokeColor(CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.13))
    ctx.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // Active progress arc (~76% clockwise from 12 o'clock)
    // In CGContext (bottom-left origin), 12 o'clock is +pi/2 and clockwise sweeps downward.
    let startAngle: CGFloat = .pi / 2.0
    let sweepFraction: CGFloat = 0.76
    let endAngle: CGFloat = startAngle - sweepFraction * .pi * 2.0

    let arcPath = CGMutablePath()
    arcPath.addArc(center: center, radius: ringRadius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
    let strokedArc = arcPath.copy(
        strokingWithWidth: ringWidth,
        lineCap: .round,
        lineJoin: .round,
        miterLimit: 10
    )

    // Soft colored ambient glow behind the progress arc
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -8 * s),
        blur: 36 * s,
        color: CGColor(srgbRed: 0.48, green: 0.74, blue: 0.58, alpha: 0.32)
    )
    ctx.addPath(strokedArc)
    ctx.setFillColor(CGColor(srgbRed: 0.45, green: 0.75, blue: 0.58, alpha: 0.6))
    ctx.fillPath()
    ctx.restoreGState()

    // Gradient fill inside the active progress arc (pure sage at 12 o'clock -> warm amber -> muted crimson)
    ctx.saveGState()
    ctx.addPath(strokedArc)
    ctx.clip()

    let arcColors = [
        CGColor(srgbRed: 0.376, green: 0.761, blue: 0.569, alpha: 1.0), // Muted sage
        CGColor(srgbRed: 0.910, green: 0.675, blue: 0.310, alpha: 1.0), // Warm amber
        CGColor(srgbRed: 0.875, green: 0.388, blue: 0.408, alpha: 1.0)  // Muted crimson
    ] as CFArray
    if let arcGradient = CGGradient(colorsSpace: colorSpace, colors: arcColors, locations: [0.0, 0.54, 1.0]) {
        ctx.drawLinearGradient(
            arcGradient,
            start: CGPoint(x: center.x + ringRadius * 0.55, y: center.y + ringRadius * 1.15),
            end: CGPoint(x: center.x - ringRadius * 1.05, y: center.y - ringRadius * 0.25),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    // Subtle specular sheen across the top of the ring
    let ringHighlight = [
        CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.24),
        CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
    ] as CFArray
    if let highlightGrad = CGGradient(colorsSpace: colorSpace, colors: ringHighlight, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            highlightGrad,
            start: CGPoint(x: center.x, y: center.y + ringRadius + ringWidth * 0.5),
            end: CGPoint(x: center.x, y: center.y),
            options: []
        )
    }
    ctx.restoreGState()

    // Crisp glass inner rim on the squircle
    ctx.saveGState()
    let rimInsetRect = iconRect.insetBy(dx: 2.0 * s, dy: 2.0 * s)
    let rimPath = CGPath(
        roundedRect: rimInsetRect,
        cornerWidth: cornerRadius - 2.0 * s,
        cornerHeight: cornerRadius - 2.0 * s,
        transform: nil
    )
    let strokedRim = rimPath.copy(strokingWithWidth: 4.0 * s, lineCap: .butt, lineJoin: .miter, miterLimit: 4)
    ctx.addPath(strokedRim)
    ctx.clip()
    let rimColors = [
        CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.28),
        CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.05)
    ] as CFArray
    if let rimGrad = CGGradient(colorsSpace: colorSpace, colors: rimColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            rimGrad,
            start: CGPoint(x: size * 0.5, y: iconRect.maxY),
            end: CGPoint(x: size * 0.5, y: iconRect.minY),
            options: []
        )
    }
    ctx.restoreGState()

    ctx.restoreGState() // end squircle clip
    ctx.restoreGState()
}

func renderPNG(pixelSize: Int, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "GenerateIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate bitmap"])
    }

    rep.size = NSSize(width: pixelSize, height: pixelSize)
    guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "GenerateIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create graphics context"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    drawAppIcon(in: nsCtx.cgContext, size: CGFloat(pixelSize))
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "GenerateIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    try pngData.write(to: url)
}

let fileManager = FileManager.default
let tempDir = fileManager.temporaryDirectory.appendingPathComponent("ELMAppIcon-\(UUID().uuidString)")
let iconsetDir = tempDir.appendingPathComponent("AppIcon.iconset")

do {
    try fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: tempDir) }

    let sizes: [(name: String, pixels: Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024)
    ]

    for entry in sizes {
        try renderPNG(pixelSize: entry.pixels, to: iconsetDir.appendingPathComponent(entry.name))
    }

    if let previewPngURL {
        try fileManager.createDirectory(at: previewPngURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try renderPNG(pixelSize: 512, to: previewPngURL)
    }

    try fileManager.createDirectory(at: outputIcnsURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconsetDir.path, "-o", outputIcnsURL.path]
    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        fputs("iconutil failed with status \(process.terminationStatus)\n", stderr)
        exit(process.terminationStatus)
    }
} catch {
    fputs("Error generating icon: \(error)\n", stderr)
    exit(1)
}
