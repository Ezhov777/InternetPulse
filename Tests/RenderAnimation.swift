import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@main struct RenderAnimation {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        AppLanguage.shared.code="en"
        let output=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs/screenshots/chart-demo.gif")
        let frames=24
        let destination=CGImageDestinationCreateWithURL(output as CFURL,UTType.gif.identifier as CFString,frames,nil)!
        CGImageDestinationSetProperties(destination,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
        for frame in 0..<frames {
            let end=Date(timeIntervalSince1970:1793297520+Double(frame))
            let samples:[Sample]=(0...80).map { i in let t=Double(i+frame);return Sample(date:end.addingTimeInterval(Double(i-80)),down:150+40*sin(t/8)+18*cos(t/4),up:40+8*sin(t/7),downloaded:0,uploaded:0,latency:24,errors:0) }
            let view=VStack(alignment:.leading,spacing:12) {
                Text("INTERNET PULSE · 1.7.0 · DEMO").font(.system(size:11,weight:.semibold,design:.monospaced)).foregroundStyle(mint)
                TrafficChart(samples:samples,elapsed:String(format:"00:04:%02d",frame),peakDown:243.5,peakUp:71.2)
            }.padding(22).frame(width:940).background(Color(red:0.045,green:0.04,blue:0.085)).preferredColorScheme(.dark)
            let host=NSHostingView(rootView:view.foregroundStyle(.white))
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:940,height:540),styleMask:[.borderless],backing:.buffered,defer:false)
            window.contentView=host;host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until:Date().addingTimeInterval(0.08));host.displayIfNeeded()
            guard let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) else {fatalError("Animation frame failed")}
            host.cacheDisplay(in:host.bounds,to:bitmap)
            guard let image=bitmap.cgImage else {fatalError("Animation frame has no image")}
            window.contentView=nil
            CGImageDestinationAddImage(destination,image,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.125]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {fatalError("GIF export failed")}
        print("Created a 3-second native chart demonstration GIF")
    }
}
