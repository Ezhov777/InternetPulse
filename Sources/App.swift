import AppKit
import SwiftUI

struct Sample {
    let date: Date
    let down: Double
    let up: Double
    let downloaded: UInt64
    let uploaded: UInt64
    let latency: Double
    let errors: Int32
}

struct DailyTraffic: Codable, Identifiable {
    var date: Date
    var downloaded: UInt64 = 0
    var uploaded: UInt64 = 0
    var id: Date { date }
}

final class Monitor: ObservableObject {
    @Published var downLimit = "10"
    @Published var upLimit = "5"
    @Published var duration = 15
    @Published var downloadURL = "http://speedtest.rastrnet.ru/1GB.zip"
    @Published var uploadURL = "http://speedtest.rastrnet.ru/speedtest/upload.php"
    @Published var running = false
    @Published var stopping = false
    @Published var down = 0.0
    @Published var up = 0.0
    @Published var downloaded: UInt64 = 0
    @Published var uploaded: UInt64 = 0
    @Published var latency = -1.0
    @Published var errors: Int32 = 0
    @Published var elapsed = 0
    @Published var samples: [Sample] = []
    @Published var events: [String] = []
    @Published var validation = ""
    @Published var dailyHistory: [DailyTraffic] = []
    @Published var historyUnit = "MB"
    @Published var streams=4
    @Published var maximum=false
    @Published var downloadEnabled=true
    @Published var uploadEnabled=true
    @Published var peakDown=0.0
    @Published var peakUp=0.0
    private var lastHistorySave=Date.distantPast
    @Published var stalled=false
    private var noTrafficSeconds=0
    private var timer: Timer?
    private var started = Date()
    private var lastTime = Date()
    private var lastDown: UInt64 = 0
    private var lastUp: UInt64 = 0
    private var eventID: UInt64 = 0
    private var activity: NSObjectProtocol?
    private let preferences: UserDefaults

    init(defaults:UserDefaults = .standard) {
        preferences=defaults
        let prefs=defaults
        downLimit=prefs.string(forKey:"downloadLimit") ?? "10"
        upLimit=prefs.string(forKey:"uploadLimit") ?? "5"
        downloadURL=prefs.string(forKey:"downloadURL") ?? downloadURL
        uploadURL=prefs.string(forKey:"uploadURL") ?? uploadURL
        if prefs.object(forKey:"duration") != nil { duration=prefs.integer(forKey:"duration") }
        if let data=prefs.data(forKey:"dailyHistory"), let history=try? JSONDecoder().decode([DailyTraffic].self,from:data) {
            dailyHistory=history.sorted{$0.date>$1.date}
        }
        let storedUnit=prefs.string(forKey:"historyUnit") ?? "MB"
        historyUnit=["\u{041C}\u{0411}":"MB","\u{0413}\u{0411}":"GB","\u{0422}\u{0411}":"TB"][storedUnit] ?? storedUnit
        if !["MB","GB","TB"].contains(historyUnit) {historyUnit="MB"}
        streams=prefs.object(forKey:"streams") == nil ? 4 : prefs.integer(forKey:"streams")
        if ![1,4,8,16].contains(streams) {streams=4}
        maximum=prefs.bool(forKey:"maximum")
        downloadEnabled=Self.number(downLimit) != 0;uploadEnabled=Self.number(upLimit) != 0
        downloadEnabled=prefs.object(forKey:"downloadEnabled") == nil ? downloadEnabled : prefs.bool(forKey:"downloadEnabled")
        uploadEnabled=prefs.object(forKey:"uploadEnabled") == nil ? uploadEnabled : prefs.bool(forKey:"uploadEnabled")
    }

    func recordTraffic(downloaded:UInt64,uploaded:UInt64,at date:Date) {
        guard downloaded>0 || uploaded>0 else {return}
        let day=Calendar.current.startOfDay(for:date)
        var history=dailyHistory
        if let index=history.firstIndex(where:{$0.date==day}) {
            history[index].downloaded += downloaded
            history[index].uploaded += uploaded
        } else {
            history.append(DailyTraffic(date:day,downloaded:downloaded,uploaded:uploaded))
            history.sort{$0.date>$1.date}
        }
        dailyHistory=history
        if date.timeIntervalSince(lastHistorySave)>=10 {saveHistory();lastHistorySave=date}
    }
    func saveHistory() {
        if let data=try? JSONEncoder().encode(dailyHistory) { preferences.set(data,forKey:"dailyHistory") }
        preferences.set(historyUnit,forKey:"historyUnit")
    }
    func resetHistory() {
        // Capture pending bytes before resetting, so they cannot reappear next tick.
        if running { tick() }
        dailyHistory=[]
        saveHistory()
        log(L("История трафика по дням сброшена"))
    }
    func historyAmount(_ bytes:UInt64)->String {
        return TrafficFormat.amount(bytes, unit:historyUnit)
    }
    func shutdown() {
        timer?.invalidate(); timer=nil
        rp_request_stop();rp_join()
        if running { duration=0; tick() }
        saveHistory()
    }

    static func number(_ text: String) -> Double? {
        guard let n = Double(text.replacingOccurrences(of: ",", with: ".")), n.isFinite, n >= 0, n <= 20000 else { return nil }
        return n
    }
    func log(_ text: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        events.insert("\(time)  \(text)", at: 0)
        if events.count > 100 { events.removeLast() }
    }
    func start() {
        guard !running, !stopping else { return }
        let inputD=Self.number(downLimit) ?? -1,inputU=Self.number(upLimit) ?? -1
        let d=downloadEnabled ? (maximum ? 1 : inputD) : 0
        let u=uploadEnabled ? (maximum ? 1 : inputU) : 0
        guard d+u > 0 &&
              (d == 0 || d >= 0.1) && (u == 0 || u >= 0.1) else {
            validation = L("Укажите от 0,1 до 20000 Мбит/с и включите направление."); return
        }
        for (value, enabled) in [(downloadURL, d>0), (uploadURL, u>0)] where enabled {
            guard value.utf8.count < 2000, let url = URL(string: value),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
                  url.user == nil, url.password == nil else {
                validation = L("Проверьте адрес сервера: нужен HTTP или HTTPS URL без логина и пароля."); return
            }
        }
        validation = ""
        noTrafficSeconds=0;stalled=false
        samples=[]; events=[]; elapsed=0; down=0; up=0; downloaded=0; uploaded=0; errors=0; latency = -1;peakDown=0;peakUp=0
        lastDown=0; lastUp=0; eventID=0; started=Date(); lastTime=started
        let ok=downloadURL.withCString { dURL in uploadURL.withCString { uURL in rp_start_parallel(dURL,uURL,d,u,Int32(streams),maximum ? 1 : 0) } }
        if ok == 0 {
            rp_request_stop()
            rp_join()
            validation = L("Не удалось запустить тест.");log(validation); return
        }
        let prefs=preferences
        prefs.set(downLimit,forKey:"downloadLimit"); prefs.set(upLimit,forKey:"uploadLimit")
        prefs.set(downloadURL,forKey:"downloadURL"); prefs.set(uploadURL,forKey:"uploadURL")
        prefs.set(duration,forKey:"duration")
        prefs.set(streams,forKey:"streams");prefs.set(maximum,forKey:"maximum")
        prefs.set(downloadEnabled,forKey:"downloadEnabled");prefs.set(uploadEnabled,forKey:"uploadEnabled")
        activity=ProcessInfo.processInfo.beginActivity(options:[.userInitiated,.idleSystemSleepDisabled],reason:L("Идёт непрерывный тест интернета"))
        running=true
        log(L("Интернет HTTP · {0} потоков · {1}",String(streams),L(maximum ? L("На максимум") : L("С лимитом"))))
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }
    func tick() {
        let now=Date()
        let s=rp_snapshot()
        let interval=max(0.01,now.timeIntervalSince(lastTime))
        recordTraffic(downloaded:s.downloaded-lastDown,uploaded:s.uploaded-lastUp,at:now)
        down=Double(s.downloaded-lastDown)*8/1_000_000/interval
        up=Double(s.uploaded-lastUp)*8/1_000_000/interval
        // Ignore a final short fragment: session records describe full second intervals.
        if interval>=0.75 {peakDown=max(peakDown,down);peakUp=max(peakUp,up)}
        if s.downloaded==lastDown && s.uploaded==lastUp {noTrafficSeconds+=1} else {noTrafficSeconds=0}
        stalled=running && noTrafficSeconds>=5
        lastDown=s.downloaded; lastUp=s.uploaded; lastTime=now
        downloaded=s.downloaded; uploaded=s.uploaded; latency=s.latency_ms; errors=s.errors
        elapsed=Int(now.timeIntervalSince(started))
        samples.append(Sample(date:now,down:down,up:up,downloaded:downloaded,uploaded:uploaded,latency:latency,errors:errors))
        if samples.count > 86400 { samples.removeFirst(samples.count-86400) }
        if s.event_id != eventID {
            eventID=s.event_id
            var text=s.message
            let str=withUnsafePointer(to: &text) { $0.withMemoryRebound(to: CChar.self, capacity:256) { String(cString:$0) } }
            log(str)
        }
        if duration>0 && elapsed>=duration*60 { stop(completed:true) }
    }
    func stop(completed:Bool=false) {
        guard running && !stopping else { return }
        stopping=true
        rp_request_stop()
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            rp_join()
            DispatchQueue.main.async {
                guard let self=self else {return}
                self.tick()
                self.timer?.invalidate(); self.timer=nil
                self.saveHistory()
                self.running=false; self.stopping=false;self.stalled=false
                if let activity=self.activity { ProcessInfo.processInfo.endActivity(activity); self.activity=nil }
                self.down=0; self.up=0
                self.log(completed ? (self.errors==0 ? L("Тест успешно завершён") : L("Тест завершён с ошибками: {0}",String(self.errors))) : L("Тест остановлен пользователем") + (self.errors>0 ? " · "+L("Ошибок соединения")+": \(self.errors)" : ""))
            }
        }
    }
    func export() {
        let panel=NSSavePanel()
        panel.nameFieldStringValue="InternetPulse-\(ISO8601DateFormatter().string(from:Date()).replacingOccurrences(of: ":", with: "-" )).csv"
        guard panel.runModal() == .OK, let url=panel.url else {return}
        var csv="time,download_mbps,upload_mbps,download_bytes,upload_bytes,http_ttfb_ms,errors\n"
        let format=ISO8601DateFormatter()
        for s in samples {
            csv += "\(format.string(from:s.date)),\(String(format:"%.4f",locale:Locale(identifier:"en_US_POSIX"),s.down)),\(String(format:"%.4f",locale:Locale(identifier:"en_US_POSIX"),s.up)),\(s.downloaded),\(s.uploaded),\(s.latency),\(s.errors)\n"
        }
        do { try csv.write(to:url,atomically:true,encoding:.utf8); log(L("CSV сохранён")) }
        catch { validation=L("Не удалось сохранить CSV: {0}",error.localizedDescription) }
    }
    var time: String { String(format:"%02d:%02d:%02d",elapsed/3600,(elapsed%3600)/60,elapsed%60) }
    var clockCaption:String {
        if !running && elapsed==0 {return L("ДЛИТЕЛЬНОСТЬ")}
        return running && duration>0 ? L("ОСТАЛОСЬ") : L("ВРЕМЯ ТЕСТА")
    }
    var clockText:String {
        if !running && elapsed==0 && duration==0 {return "∞"}
        if duration>0 && (running || elapsed==0) {
            let left=max(0,duration*60-elapsed)
            return left>=3600 ? String(format:"%02d:%02d:%02d",left/3600,left%3600/60,left%60) : String(format:"%02d:%02d",left/60,left%60)
        }
        return time
    }
    static func bytes(_ n:UInt64) -> String {
        return TrafficFormat.amount(n,unit:n>=1_000_000_000_000 ? "TB" : n>=1_000_000_000 ? "GB" : "MB")
    }
}

let mint = Color(red:0.29,green:0.94,blue:0.85)
let blue = Color(red:0.65,green:0.55,blue:1)

struct GlassPanel:ViewModifier {
    func body(content:Content)->some View {
        content.background {
            RoundedRectangle(cornerRadius:24).fill(.white.opacity(0.035))
                .overlay(RoundedRectangle(cornerRadius:24).stroke(LinearGradient(colors:[.white.opacity(0.14),.white.opacity(0.02)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1))
        }
    }
}

struct AnimatedSpeed:View,Animatable {
    var value:Double
    var animatableData:Double { get {value} set {value=newValue} }
    var body:some View {
        Text(TrafficFormat.speed(value))
            .font(.system(size:58,weight:.light,design:.rounded)).tracking(-2).monospacedDigit()
    }
}

struct BandwidthInput:View {
    let title:String
    let symbol:String
    let color:Color
    @Binding var value:String
    var disabled:Bool
    @FocusState private var focused:Bool
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Label(L(title),systemImage:symbol).font(.system(size:14,weight:.medium)).foregroundStyle(color)
            HStack(alignment:.firstTextBaseline,spacing:12) {
                Group {
                    if disabled {
                        Text(value).frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(.white.opacity(0.75))
                    } else {
                        TextField("0",text:$value).textFieldStyle(.plain)
                            .focused($focused).accessibilityLabel(L("Лимит: ")+title)
                    }
                }.font(.system(size:36,weight:.light,design:.rounded)).monospacedDigit()
                Text(L("Мбит/с")).font(.system(size:13,weight:.medium)).foregroundStyle(.secondary).fixedSize()
            }
        }.padding(22).frame(maxWidth:.infinity,alignment:.leading)
            .background(.black.opacity(0.12),in:RoundedRectangle(cornerRadius:20))
            .overlay(RoundedRectangle(cornerRadius:20).stroke(focused ? color.opacity(0.65) : .white.opacity(0.09),lineWidth:1))
            .animation(.easeInOut(duration:0.2),value:focused)
    }
}

enum PulseSheet:String,Identifiable {
    case releaseNotes,updates
    var id:String {rawValue}
}

struct ContentView: View {
    @ObservedObject var model: Monitor
    @ObservedObject private var language=AppLanguage.shared
    @State private var country="all"
    @State private var serverSearch=""
    @State private var settings=false
    @State private var resetHistory=false
    @State private var activeSheet:PulseSheet?
    @StateObject private var updateChecker=UpdateChecker()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var durationSelection
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                HStack(alignment:.center,spacing:18) {
                    Image(systemName:"waveform.path").font(.system(size:25,weight:.semibold)).foregroundStyle(mint)
                        .frame(width:50,height:50).background(LinearGradient(colors:[mint.opacity(0.16),blue.opacity(0.14)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:16))
                        .overlay(RoundedRectangle(cornerRadius:16).stroke(mint.opacity(0.22),lineWidth:1))
                    VStack(alignment:.leading,spacing:8) {
                        Text("INTERNET PULSE · \(BuildInfo.version)").font(.system(size:10,weight:.bold,design:.monospaced)).tracking(2).foregroundStyle(mint.opacity(0.8)).fixedSize()
                        Text(L("Бесконечный Speedtest")).font(.system(size:26,weight:.semibold)).tracking(-0.8).foregroundStyle(.white).lineLimit(2).fixedSize(horizontal:false,vertical:true)
                    }
                    Spacer()
                    VStack(alignment:.trailing,spacing:10) {
                        Menu {
                            ForEach(AppLanguage.choices,id:\.0) { code,name in
                                Button {language.code=code} label: {
                                    if language.code==code {Label(name,systemImage:"checkmark")} else {Text(name)}
                                }
                            }
                        } label: {
                            HStack(spacing:7) {
                                Image(systemName:"globe")
                                Text(AppLanguage.choices.first{$0.0==language.code}?.1 ?? "English")
                                Image(systemName:"chevron.down").font(.system(size:8,weight:.semibold))
                            }.font(.system(size:12,weight:.medium)).foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal,12).padding(.vertical,7).background(.white.opacity(0.055),in:Capsule())
                        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel(L("Язык")).disabled(model.stopping)
                    HStack(spacing:16) {
                        HStack(spacing:7) {
                            Circle().fill(model.stalled ? .orange : model.running ? mint : Color.secondary).frame(width:6,height:6)
                                .shadow(color:mint.opacity(model.running ? 0.7 : 0),radius:5)
                            Text(model.stopping ? L("Остановка") : model.running ? (model.stalled ? L("Нет передачи данных") : L("Тест идёт")) : L("Готов к тесту")).font(.system(size:11,weight:.medium)).fixedSize()
                        }
                        Rectangle().fill(.white.opacity(0.12)).frame(width:1,height:28)
                        VStack(alignment:.trailing,spacing:3) {
                            Text(model.clockCaption).font(.system(size:8,weight:.medium,design:.monospaced)).tracking(1.5).foregroundStyle(.secondary)
                            Text(model.clockText).font(.system(size:22,weight:.medium,design:.monospaced)).monospacedDigit().foregroundStyle(model.running ? mint : .white)
                        }.frame(minWidth:86,alignment:.trailing)
                    }.padding(.horizontal,16).padding(.vertical,12).modifier(GlassPanel())
                    }
                }.padding(.top,4).padding(.bottom,10)
                HStack(spacing:14) {
                    speed(L("Скачивание"),symbol:"arrow.down",value:model.down,total:model.downloaded,color:mint)
                    speed(L("Отдача"),symbol:"arrow.up",value:model.up,total:model.uploaded,color:blue)
                }
                if model.stalled {Label(L("Сервер не передаёт данные. Проверьте журнал или выберите другой сервер."),systemImage:"wifi.exclamationmark").font(.callout).foregroundStyle(.orange).padding(16).modifier(GlassPanel())}
                loadControls
                TrafficChart(samples:model.samples,elapsed:model.time,peakDown:model.peakDown,peakUp:model.peakUp).id(language.code)
                HStack(spacing:26) {
                    stat(L("HTTP-задержка"),value:model.latency>=0 ? String(format:"%.0f",model.latency)+" "+L("мс") : "—")
                    stat(L("Ошибок соединения"),value:"\(model.errors)")
                    Spacer()
                    Button { model.export() } label: { Label(L("Сохранить CSV"),systemImage:"square.and.arrow.up") }.disabled(model.samples.isEmpty)
                }.padding(.horizontal,6).padding(.vertical,5)
                VStack(alignment:.leading,spacing:14) {
                    HStack {
                        Text(L("Интернет-трафик по дням")).font(.headline)
                        Spacer()
                        Picker(L("Единицы"),selection:$model.historyUnit) {
                            Text(L("MB")).tag("MB");Text(L("GB")).tag("GB");Text(L("TB")).tag("TB")
                        }.labelsHidden().pickerStyle(.segmented).frame(width:155).onChange(of:model.historyUnit) { model.saveHistory() }
                        Button(L("Сбросить историю")) { resetHistory=true }.fixedSize().disabled(model.dailyHistory.isEmpty)
                    }
                    HStack {
                        Text(L("День")).frame(maxWidth:.infinity,alignment:.leading)
                        Text(L("Скачано")).frame(width:150,alignment:.trailing).foregroundStyle(mint)
                        Text(L("Отдано")).frame(width:150,alignment:.trailing).foregroundStyle(blue)
                    }.font(.caption).foregroundStyle(.secondary)
                    if model.dailyHistory.isEmpty {
                        Text(L("Запустите тест — здесь появится расход трафика за каждый день.")).font(.caption).foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            VStack(spacing:10) {
                                ForEach(model.dailyHistory) { day in
                                    HStack {
                                        Text(day.date.formatted(.dateTime.day().month(.wide).year().locale(language.locale))).frame(maxWidth:.infinity,alignment:.leading)
                                        Text(model.historyAmount(day.downloaded)).frame(width:150,alignment:.trailing)
                                        Text(model.historyAmount(day.uploaded)).frame(width:150,alignment:.trailing)
                                    }.font(.system(size:13)).monospacedDigit()
                                }
                            }
                        }.frame(height:CGFloat(min(model.dailyHistory.count,5))*27)
                    }
                    Text(L("Учитывается трафик тестов InternetPulse. История сохраняется между запусками. 1 ТБ = 1000 ГБ; 1 ГБ = 1000 МБ."))
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(22).modifier(GlassPanel())
                .alert(L("Сбросить историю трафика?"),isPresented:$resetHistory) {
                    Button(L("Отмена"),role:.cancel) {}
                    Button(L("Сбросить"),role:.destructive) { model.resetHistory() }
                } message: { Text(L("Суммы за все дни будут удалены. Текущий тест продолжится, новый трафик начнёт учитываться с нуля.")) }
                DisclosureGroup(isExpanded:$settings) {
                    VStack(alignment:.leading,spacing:10) {
                        HStack {
                            Picker(L("Страна"),selection:$country) {
                                Text(L("Все страны")).tag("all")
                                ForEach(TestServer.countries,id:\.0) {code,name in Text(L(name)).tag(code)}
                            }.frame(width:250)
                            TextField(L("Поиск серверов"),text:$serverSearch).textFieldStyle(.roundedBorder)
                        }
                        Picker(L("Сервер"),selection:Binding(get:{ selectedServer?.id ?? "custom" },set:{ id in
                            if let server=TestServer.all.first(where:{$0.id==id}) {
                                model.downloadURL=server.download
                                model.uploadURL=server.upload ?? ""
                                model.uploadEnabled=server.upload != nil
                                if server.upload != nil && Monitor.number(model.upLimit)==0 {model.upLimit="5"}
                            } else {
                                model.downloadURL="";model.uploadURL=""
                            }
                        })) {
                            ForEach(filteredServers) { server in Text(server.label).tag(server.id) }
                            Text(L("Свой сервер")).tag("custom")
                        }.labelsHidden().frame(maxWidth:.infinity)
                        HStack {
                            Text(selectedServer?.upload == nil && selectedServer != nil ? L("↓ Только скачивание в InternetPulse") : L("↓↑ Скачивание и отдача"))
                                .font(.caption).foregroundStyle(mint).fixedSize()
                            Spacer()
                            if let server=selectedServer, let url=URL(string:server.source) { Link(L("О сервере ↗"),destination:url).font(.caption) }
                        }
                        Text(L("Скачивание · HTTP GET")).font(.caption)
                        TextField("URL",text:$model.downloadURL).textFieldStyle(.roundedBorder)
                        Text(L("Отдача · HTTP PUT")).font(.caption)
                        TextField("URL",text:$model.uploadURL).textFieldStyle(.roundedBorder)
                        Text(L("Для серверов «только скачивание» отдача отключается. Доступность и скорость зависят от сервера и сети. Для отдачи нужен HTTP PUT. Задержка — время до первого ответа с установкой соединения.")).font(.caption).foregroundStyle(.secondary)
                    }.padding(.top,12).disabled(model.running)
                } label: { Text(L("Тестовый сервер")).font(.system(size:13,weight:.medium)) }
                .padding(20).modifier(GlassPanel())
                VStack(alignment:.leading,spacing:8) {
                    Text(L("Журнал")).font(.system(size:13,weight:.medium))
                    if model.events.isEmpty {
                        Text(L("Здесь появятся запуск, остановка и ошибки соединения.")).foregroundStyle(.secondary).font(.caption)
                    } else {
                        ScrollView {
                            VStack(alignment:.leading,spacing:6) {
                                ForEach(Array(model.events.enumerated()),id:\.offset) { _,event in Text(event).font(.system(size:11,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
                            }
                        }.frame(height:75)
                    }
                }
                Text(L("Тест создаёт реальный интернет-трафик. Скачанные файлы не сохраняются; для отдачи используются случайные байты. График и CSV — за последние 24 часа текущего запуска. Суммы по дням сохраняются между запусками."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                HStack {
                    Text("Internet Pulse · "+L("Версия {0}",BuildInfo.version))
                        .font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)
                    Spacer()

                    Button {activeSheet = .releaseNotes} label: {Label(L("Что нового"),systemImage:"sparkles").font(.system(size:11,weight:.medium))}.buttonStyle(.plain).foregroundStyle(mint)
                    Button {activeSheet = .updates} label: {Label(L("Проверить обновления"),systemImage:"arrow.triangle.2.circlepath").font(.system(size:11,weight:.medium))}.buttonStyle(.plain).foregroundStyle(mint).padding(.leading,12)
                }
            }.padding(28)
        }.frame(minWidth:840,minHeight:790).background {
            ZStack {
                Color(red:0.045,green:0.04,blue:0.085)
                RadialGradient(colors:[Color(red:0.48,green:0.24,blue:0.95).opacity(0.20),.clear],center:UnitPoint(x:0.9,y:0),startRadius:0,endRadius:720)
                RadialGradient(colors:[Color(red:0.94,green:0.3,blue:0.62).opacity(0.09),.clear],center:UnitPoint(x:0,y:0.4),startRadius:0,endRadius:650)
                RadialGradient(colors:[mint.opacity(0.065),.clear],center:.bottomLeading,startRadius:0,endRadius:550)
            }
        }.preferredColorScheme(.dark).environment(\.locale,language.locale)
            .onReceive(NotificationCenter.default.publisher(for:ReleaseHistory.show)) {_ in activeSheet = .releaseNotes}
            .onReceive(NotificationCenter.default.publisher(for:UpdateChecker.show)) {_ in activeSheet = .updates}
            .sheet(item:$activeSheet) { selection in
                switch selection {
                case .releaseNotes:ReleaseNotesView().environment(\.locale,language.locale)
                case .updates:UpdatesView(checker:updateChecker)
                }
            }
    }
    var loadControls:some View {
        VStack(alignment:.leading,spacing:22) {
            HStack(alignment:.firstTextBaseline) {
                Text(L("Нагрузка на канал")).font(.system(size:22,weight:.semibold)).tracking(-0.5)
                Spacer()
                Text(L("Интернет-тест")).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing:20) {
                Toggle(L("На максимум"),isOn:$model.maximum).toggleStyle(.switch).disabled(model.running)
                Spacer()
                Text(L("Потоков на направление")).font(.caption).foregroundStyle(.secondary)
                Picker(L("Потоки"),selection:$model.streams) {
                    ForEach([1,4,8,16],id:\.self) {Text("\($0)").tag($0)}
                }.labelsHidden().pickerStyle(.segmented).frame(width:170).disabled(model.running)
            }
                HStack(spacing:20) {
                    Toggle(L("Скачивание"),isOn:$model.downloadEnabled).tint(mint)
                    Toggle(L("Отдача"),isOn:$model.uploadEnabled).tint(blue)
                    Spacer()
                    Text(model.maximum ? L("Без ограничения скорости") : L("Общий лимит всех потоков")).font(.caption).foregroundStyle(.secondary)
                }.disabled(model.running)
                if !model.maximum {
                    HStack(spacing:14) {
                        BandwidthInput(title:L("Скачивание"),symbol:"arrow.down",color:mint,value:$model.downLimit,disabled:model.running || !model.downloadEnabled)
                        BandwidthInput(title:L("Отдача"),symbol:"arrow.up",color:blue,value:$model.upLimit,disabled:model.running || !model.uploadEnabled)
                    }
                }
            HStack(alignment:.bottom,spacing:24) {
                VStack(alignment:.leading,spacing:12) {
                    Text(L("Длительность теста")).font(.system(size:12,weight:.medium)).foregroundStyle(.secondary)
                    HStack(spacing:4) {
                        ForEach([5,15,60,0],id:\.self) { duration in
                            Button {
                                withAnimation(reduceMotion ? nil : .spring(response:0.4,dampingFraction:0.85)) { model.duration=duration }
                            } label: {
                                Text(duration==0 ? L("∞ Без лимита") : duration==60 ? L("1 час") : L("{0} мин",String(duration)))
                                    .font(.system(size:13,weight:model.duration==duration ? .semibold : .medium))
                                    .foregroundStyle(model.duration==duration ? .white : .secondary)
                                    .padding(.horizontal,15).frame(height:40)
                                    .background {
                                        if model.duration==duration {
                                            RoundedRectangle(cornerRadius:12).fill(.white.opacity(0.12))
                                                .overlay(RoundedRectangle(cornerRadius:12).stroke(.white.opacity(0.12),lineWidth:1))
                                                .matchedGeometryEffect(id:"duration",in:durationSelection)
                                        }
                                    }
                            }.buttonStyle(.plain).disabled(model.running)
                        }
                    }.padding(4).background(.black.opacity(0.16),in:RoundedRectangle(cornerRadius:16))
                }
                Spacer(minLength:0)
                Button(action:{model.running ? model.stop() : model.start()}) {
                    Label(model.stopping ? L("Остановка…") : model.running ? L("Остановить") : L("Начать тест"),systemImage:model.running ? "stop.fill" : "play.fill")
                        .font(.system(size:15,weight:.semibold)).frame(width:190,height:50)
                        .background(model.running ? Color.white.opacity(0.09) : mint,in:Capsule())
                        .foregroundStyle(model.running ? Color.white : Color(red:0.03,green:0.10,blue:0.13))
                        .overlay(Capsule().stroke(.white.opacity(0.12),lineWidth:1))
                }.buttonStyle(.plain).disabled(model.stopping)
                    .animation(reduceMotion ? nil : .easeInOut(duration:0.45),value:model.running)
            }
            if !model.validation.isEmpty { Text(model.validation).font(.caption).foregroundStyle(.orange) }
            Text(model.maximum ? L("Тест стремится занять доступную полосу. 4–8 потоков могут дать большую скорость, чем одно соединение.") : L("Лимит общий для всех потоков направления. На коротких интервалах возможны всплески.")).font(.system(size:11)).foregroundStyle(.secondary)
        }.padding(26).modifier(GlassPanel())
    }
    var filteredServers:[TestServer] {
        TestServer.all.filter { server in
            // Always retain the selected server so filtering never silently changes the endpoint.
            server.id==selectedServer?.id || ((country=="all" || server.country==country) && (serverSearch.isEmpty || server.label.localizedCaseInsensitiveContains(serverSearch)))
        }
    }
    var selectedServer:TestServer? { TestServer.all.first{$0.download==model.downloadURL} }
    func speed(_ title:String,symbol:String,value:Double,total:UInt64,color:Color) -> some View {
        VStack(alignment:.leading,spacing:15) {
            HStack {
                Text(L(title).uppercased()).font(.system(size:10,weight:.semibold,design:.monospaced)).tracking(2).foregroundStyle(color)
                Spacer()
                Image(systemName:symbol+".right").font(.system(size:15,weight:.medium)).foregroundStyle(color)
                    .frame(width:30,height:30).background(color.opacity(0.1),in:Circle())
            }
            HStack(alignment:.firstTextBaseline,spacing:7) {
                AnimatedSpeed(value:value).animation(reduceMotion ? nil : .easeInOut(duration:0.8),value:value)
                Text(L("Мбит/с")).font(.system(size:12)).foregroundStyle(.secondary)
            }
            HStack { Text(L("За этот тест")).foregroundStyle(.secondary); Spacer();Text(Monitor.bytes(total)).foregroundStyle(color.opacity(0.85)).monospacedDigit() }.font(.system(size:11))
        }.frame(maxWidth:.infinity,alignment:.leading).padding(24)
            .background(LinearGradient(colors:[color.opacity(0.13),blue.opacity(0.045),Color(red:0.85,green:0.3,blue:0.65).opacity(0.035)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:24))
            .modifier(GlassPanel())
            .overlay(RoundedRectangle(cornerRadius:24).stroke(color.opacity(model.running ? 0.2 : 0),lineWidth:1))
            .animation(reduceMotion ? nil : .easeInOut(duration:0.85),value:model.running)
    }
    func stat(_ title:String,value:String) -> some View {
        VStack(alignment:.leading,spacing:6) {
            Text(L(title)).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size:19,weight:.medium)).monospacedDigit()
        }
    }
}

final class AppDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
    let model=Monitor()
    private var languageObserver:NSObjectProtocol?
    var window:NSWindow!
    func applicationDidFinishLaunching(_ notification:Notification) {
        rebuildMenus()
        languageObserver=NotificationCenter.default.addObserver(forName:Notification.Name("InternetPulse.languageChanged"),object:nil,queue:.main) {[weak self] _ in self?.rebuildMenus()}
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:880),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="Internet Pulse · "+(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "1.7.0");window.delegate=self
        window.contentView=NSHostingView(rootView:ContentView(model:model))
        window.center();window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
    }
    func rebuildMenus() {
        let main=NSMenu()
        let item=NSMenuItem(); main.addItem(item)
        let appMenu=NSMenu(); item.submenu=appMenu
        appMenu.addItem(withTitle:L("Об Internet Pulse"),action:#selector(NSApplication.orderFrontStandardAboutPanel(_:)),keyEquivalent:"")
        let releaseItem=NSMenuItem(title:L("Что нового в Internet Pulse…"),action:#selector(showWhatsNew),keyEquivalent:"")
        releaseItem.target=self;appMenu.addItem(releaseItem)
        let updateItem=NSMenuItem(title:L("Проверить обновления…"),action:#selector(checkUpdates),keyEquivalent:"")
        updateItem.target=self;appMenu.addItem(updateItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle:L("Завершить InternetPulse"),action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let editItem=NSMenuItem();main.addItem(editItem)
        let edit=NSMenu(title:L("Правка"));editItem.submenu=edit
        edit.addItem(withTitle:L("Копировать"),action:#selector(NSText.copy(_:)),keyEquivalent:"c")
        edit.addItem(withTitle:L("Вставить"),action:#selector(NSText.paste(_:)),keyEquivalent:"v")
        edit.addItem(withTitle:L("Выбрать всё"),action:#selector(NSText.selectAll(_:)),keyEquivalent:"a")
        NSApp.mainMenu=main
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { true }
    @objc func showWhatsNew() {NotificationCenter.default.post(name:ReleaseHistory.show,object:nil)}
    @objc func checkUpdates() {NotificationCenter.default.post(name:UpdateChecker.show,object:nil)}
    func applicationWillTerminate(_ notification:Notification) { model.shutdown() }
}

#if !TESTING
@main struct Entry {
    static func main() {
        let app=NSApplication.shared
        let delegate=AppDelegate()
        app.delegate=delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
#endif
