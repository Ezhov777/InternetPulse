import AppKit
import Foundation

@main struct IntegrationApp {
    static let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().path
    static var window:NSWindow!
    static var label:NSTextField!
    static func main() {
        let app=NSApplication.shared;app.setActivationPolicy(.regular)
        let menu=NSMenu(),item=NSMenuItem(),submenu=NSMenu()
        submenu.addItem(withTitle:"Quit",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        item.submenu=submenu;menu.addItem(item);app.mainMenu=menu
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:600,height:250),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title="Проверка InternetPulse 1.5"
        label=NSTextField(wrappingLabelWithString:"Проверка четырёх потоков HTTP…")
        label.frame=NSRect(x:25,y:25,width:550,height:190);window.contentView?.addSubview(label)
        window.center();window.makeKeyAndOrderFront(nil)
        DispatchQueue.global().async {
            var report=[String]()
            func check(_ ok:Bool,_ text:String) {report.append("\(ok ? "PASS" : "FAIL"): \(text)")}
            let fixture=Process();fixture.executableURL=URL(fileURLWithPath:"/usr/bin/python3");fixture.arguments=[root+"/Tests/fixture.py"]
            fixture.standardOutput=FileHandle.nullDevice;fixture.standardError=FileHandle.nullDevice
            do {
                try fixture.run();Thread.sleep(forTimeInterval:0.5)
                check(rp_start_parallel("http://127.0.0.1:18762/data","http://127.0.0.1:18762/upload",1,0.5,4,0)==1,"HTTP started with four streams per direction")
                Thread.sleep(forTimeInterval:10)
                var state=rp_snapshot()
                check(state.downloaded>900_000 && state.downloaded<1_600_000,"Aggregate download limit 1 Mbps: \(state.downloaded) bytes / 10s")
                check(state.uploaded>450_000 && state.uploaded<900_000,"Aggregate upload limit 0.5 Mbps: \(state.uploaded) bytes / 10s")
                var message=state.message
                let detail=withUnsafePointer(to:&message) {$0.withMemoryRebound(to:CChar.self,capacity:256) {String(cString:$0)}}
                check(state.errors==0,"No transfer errors (\(state.errors)): \(detail)")
                let start=Date();rp_request_stop();rp_join()
                check(Date().timeIntervalSince(start)<3,"HTTP workers stop within 3 seconds")
                state=rp_snapshot();Thread.sleep(forTimeInterval:1);let after=rp_snapshot()
                check(after.downloaded==state.downloaded && after.uploaded==state.uploaded,"Counters stable after stop")
                check(rp_start_parallel("http://127.0.0.1:18762/data","http://127.0.0.1:18762/upload",1,0,4,1)==1,"Maximum mode starts")
                Thread.sleep(forTimeInterval:1);rp_request_stop();rp_join();state=rp_snapshot()
                check(state.downloaded>2_000_000,"Maximum mode has no 1 Mbps cap")
                if fixture.isRunning {fixture.terminate()};fixture.waitUntilExit()

            } catch {report.append("FAIL: \(error)");rp_request_stop();rp_join();if fixture.isRunning {fixture.terminate()} }
            let text=report.joined(separator:"\n")
            try? text.write(toFile:root+"/build/integration-report.txt",atomically:true,encoding:.utf8)
            DispatchQueue.main.async {label.stringValue=text;window.setContentSize(NSSize(width:750,height:440));label.frame=NSRect(x:25,y:25,width:700,height:390)}
        }
        app.run()
    }
}
