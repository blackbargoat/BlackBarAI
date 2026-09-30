// Renders the BlackBar app icon (1024px master) and writes an .iconset.
import AppKit
import SwiftUI

struct Icon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(Color.black)
                .overlay(RoundedRectangle(cornerRadius: 185, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 4))
                .frame(width: 824, height: 824)
            BoxText(text: "B.", size: 300, color: .white, tracking: 0.3, stroke: 0.13)
                .offset(y: -40)
            // The bar: a thin line near the bottom edge.
            Rectangle().fill(Color.white.opacity(0.22)).frame(width: 520, height: 10).offset(y: 280)
        }
        .frame(width: 1024, height: 1024)
    }
}

MainActor.assumeIsolated {
    let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for (size, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
                         (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
        let renderer = ImageRenderer(content: Icon())
        renderer.scale = CGFloat(size) / 1024
        let rep = NSBitmapImageRep(cgImage: renderer.cgImage!)
        try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("icon_\(name).png"))
    }
}
