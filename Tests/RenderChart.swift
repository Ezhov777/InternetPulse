import AppKit
import SwiftUI

@main struct RenderChart {
    @MainActor static func main() {
        let end=Date(timeIntervalSince1970:1793279262)
        let samples:[Sample]=(0...60).map { i in
            let t=Double(i)
            let down=35.0+20.0*sin(t/8.0)+t/2.0
            let up=5.0+sin(t/7.0)*0.3
            return Sample(date:end.addingTimeInterval(t-60),down:down,up:up,downloaded:0,uploaded:0,latency:50,errors:0)
        }
        let chart=TrafficChart(samples:samples,elapsed:"00:07:13").padding(24).frame(width:860).background(Color(red:0.035,green:0.045,blue:0.065)).preferredColorScheme(.dark)
        let renderer=ImageRenderer(content:chart)
        renderer.scale=2
        guard let image=renderer.nsImage,let tiff=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let png=bitmap.representation(using:NSBitmapImageRep.FileType.png,properties:[:]) else {fatalError("Render failed")}
        let output=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("build/chart-preview.png")
        try! png.write(to:output)
        print("Chart rendered")
    }
}
