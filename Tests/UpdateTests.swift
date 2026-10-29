import Foundation

@main struct UpdateTests {
    @MainActor static func main() async {
        assert(AppVersion("1.10.0")!>AppVersion("1.6.0")!)
        assert(AppVersion("v1.6")==AppVersion("1.6.0"))
        assert(AppVersion("1.6.0+build.7")==AppVersion("1.6.0"))
        for invalid in ["", "beta", "1.6.0-beta", "1..6", "1.2.3.4", "-1.6.0"] {assert(AppVersion(invalid)==nil)}
        func fixture(status:Int=200,tag:String="v1.6.0",draft:Bool=false,prerelease:Bool=false,broken:Bool=false)->UpdateChecker {
            UpdateChecker(currentVersion:"1.6.0",fetch:{request in
                assert(request.url==UpdateChecker.api)
                assert(request.value(forHTTPHeaderField:"Authorization")==nil)
                assert(request.value(forHTTPHeaderField:"User-Agent")=="InternetPulse/1.6.0")
                let data=broken ? Data("broken".utf8) : try JSONSerialization.data(withJSONObject:["tag_name":tag,"draft":draft,"prerelease":prerelease])
                let response=HTTPURLResponse(url:UpdateChecker.api,statusCode:status,httpVersion:nil,headerFields:nil)!
                return (data,response)
            })
        }
        let newer=fixture(tag:"v1.10.0");await newer.check();assert(newer.state == .available("v1.10.0"))
        let equal=fixture();await equal.check();assert(equal.state == .current("У вас установлена актуальная версия."))
        let older=fixture(tag:"v1.5.0");await older.check();assert(older.state == .current("Ваша версия новее последнего опубликованного релиза."))
        let missing=fixture(status:404);await missing.check();assert(missing.state == .noRelease)
        for status in [403,429,500] {
            let checker=fixture(status:status);await checker.check()
            guard case .failed=checker.state else {fatalError("Expected HTTP error")}
        }
        let draft=fixture(tag:"v1.7.0",draft:true);await draft.check();assert(draft.state == .noRelease)
        let beta=fixture(tag:"v1.7.0",prerelease:true);await beta.check();assert(beta.state == .noRelease)
        for checker in [fixture(tag:"latest"),fixture(broken:true)] {
            await checker.check();guard case .failed=checker.state else {fatalError("Expected invalid release error")}
        }
        let offline=UpdateChecker(currentVersion:"1.6.0",fetch:{_ in throw URLError(.notConnectedToInternet)})
        await offline.check();guard case .failed=offline.state else {fatalError("Expected offline state")}
        print("PASS: numeric versions, newer/current/older releases, 404, rate limits, drafts, invalid JSON and offline errors; no network or token required")
    }
}
