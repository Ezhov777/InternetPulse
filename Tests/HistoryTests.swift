import Foundation

@main struct HistoryTests {
    static func main() {
        AppLanguage.shared.code="ru"
        let suite="local.routerpulse.test.\(UUID().uuidString)"
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let calendar=Calendar.current
        let today=calendar.startOfDay(for:Date())
        let yesterday=calendar.date(byAdding:.day,value:-1,to:today)!
        let m=Monitor(defaults:defaults)
        m.recordTraffic(downloaded:1_500_000,uploaded:500_000,at:yesterday)
        m.recordTraffic(downloaded:1_000_000_000,uploaded:2_000_000_000,at:today)
        m.recordTraffic(downloaded:2_500_000,uploaded:250_000,at:yesterday.addingTimeInterval(600))
        assert(m.dailyHistory.count==2)
        assert(m.dailyHistory[0].date==today)
        assert(m.dailyHistory[1].downloaded==4_000_000)
        assert(m.dailyHistory[1].uploaded==750_000)
        m.historyUnit="GB";m.saveHistory()
        let restored=Monitor(defaults:defaults)
        assert(restored.dailyHistory.count==2)
        assert(restored.historyUnit=="GB")
        assert(restored.historyAmount(restored.dailyHistory[0].downloaded)=="1,00 ГБ")
        restored.historyUnit="MB"
        assert(restored.historyAmount(4_000_000)=="4,00 МБ")
        restored.resetHistory()
        assert(Monitor(defaults:defaults).dailyHistory.isEmpty)
        restored.recordTraffic(downloaded:123,uploaded:456,at:today)
        assert(restored.dailyHistory.count==1)
        assert(restored.dailyHistory[0].downloaded==123)
        assert(restored.dailyHistory[0].uploaded==456)
        restored.running=true;restored.duration=15;restored.elapsed=61
        assert(restored.clockText=="13:59")
        assert(restored.clockCaption=="ОСТАЛОСЬ")
        restored.duration=0
        assert(restored.clockText=="00:01:01")
        assert(restored.clockCaption=="ВРЕМЯ ТЕСТА")
        restored.running=false
        assert(TestServer.all.count>=59)
        for country in ["GB","US","FR","DE","ES"] {assert((10...15).contains(TestServer.all.filter{$0.country==country}.count))}
        for locale in ["ru_RU","en_GB","fr_FR","de_DE","es_ES"] {
            let formatted=TrafficFormat.amount(30_232_170_000,unit:"MB",locale:Locale(identifier:locale))
            assert(formatted.contains("30") && formatted.contains("232"))
            assert(!formatted.contains("30232"))
        }
        assert(TrafficFormat.amount(1_000_000_000_000,unit:"TB",locale:Locale(identifier:"ru_RU"))=="1,00 ТБ")
        defaults.set("ГБ",forKey:"historyUnit");assert(Monitor(defaults:defaults).historyUnit=="GB")

        assert(TestServer.all.filter{$0.upload != nil}.count==1)
        assert(ChartScale.ceiling(for:85)==100)
        assert(ChartScale.ceiling(for:65)==80)
        assert(ChartScale.ceiling(for:0)==1)
        for peak in [0.1,1,7,87,300,1000,2400] { assert(ChartScale.ceiling(for:peak)>=peak) }
        // Preferences from the discontinued router mode must not hide Internet history.
        defaults.set("lan",forKey:"mode")
        defaults.set("192.168.1.1",forKey:"lanHost")
        let migrated=Monitor(defaults:defaults)
        assert(migrated.dailyHistory.count==1 && migrated.dailyHistory[0].downloaded==123)
        let project=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
        let releases=ReleaseHistory.load(from:project.appendingPathComponent("Resources/ReleaseHistory.json"))
        let version=try! String(contentsOf:project.appendingPathComponent("VERSION"),encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines)
        assert(releases.first?.version==version)
        assert(releases.allSatisfy{!$0.changes.isEmpty})
        assert(Set(releases.map{$0.version}).count==releases.count)
        print("PASS: daily grouping, persistence, MB/GB, reset, countdown, unlimited timer and server catalog")
    }
}
