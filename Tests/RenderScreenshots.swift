import AppKit
import SwiftUI

@main struct RenderScreenshots {
    @MainActor static func main() {
        let app=NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let prior=AppLanguage.shared.code
        defer {AppLanguage.shared.code=prior}
        let output=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs/screenshots")
        try! FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        for code in ["ru","en","fr","de","es"] {
            AppLanguage.shared.code=code
            let suite="InternetPulse.screenshots.\(UUID().uuidString)"
            let defaults=UserDefaults(suiteName:suite)!
            let model=Monitor(defaults:defaults)
            model.maximum=true;model.streams=4
            model.duration=15;model.running=true;model.elapsed=286
            model.down=182.4;model.up=48.7
            model.downloaded=6_170_000_000;model.uploaded=1_380_000_000
            model.historyUnit="MB"
            model.dailyHistory=[DailyTraffic(date:Date(timeIntervalSince1970:1793232000),downloaded:42_819_560_000,uploaded:8_427_130_000),DailyTraffic(date:Date(timeIntervalSince1970:1793145600),downloaded:12_640_000_000,uploaded:2_150_000_000)]
            model.peakDown=243.5;model.peakUp=71.2;model.latency=24
            let end=ISO8601DateFormatter().date(from:"2026-10-29T18:12:00+03:00")!
            model.samples=(0...120).map { i in let t=Double(i);return Sample(date:end.addingTimeInterval(t-120),down:155+35*sin(t/13)+15*cos(t/5),up:40+8*sin(t/11),downloaded:0,uploaded:0,latency:24,errors:0) }
            model.down=model.samples.last!.down;model.up=model.samples.last!.up
            model.events=["18:07:14  "+L("Интернет HTTP · {0} потоков · {1}","4",L("На максимум")),"18:06:00  "+L("Тест успешно завершён")]
            let view=ContentView(model:model).environment(\.locale,AppLanguage.shared.locale).frame(width:1100,height:1950)
            let host=NSHostingView(rootView:view)
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:1950),styleMask:[.borderless],backing:.buffered,defer:false)
            window.contentView=host
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until:Date().addingTimeInterval(0.4))
            host.displayIfNeeded()
            guard let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds) else {fatalError("No bitmap")}
            host.cacheDisplay(in:host.bounds,to:bitmap)
            try! bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("macos-\(code).png"))
            window.contentView=nil
            model.running=false
            defaults.removePersistentDomain(forName:suite)
        }
        print("Rendered five language screenshots from native SwiftUI views with synthetic data")
    }
}
