import Foundation
import SwiftUI

struct AppVersion:Comparable {
    let parts:[Int]
    init?(_ raw:String) {
        var value=raw.trimmingCharacters(in:.whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") {value.removeFirst()}
        value=String(value.split(separator:"+",maxSplits:1,omittingEmptySubsequences:false)[0])
        let pieces=value.split(separator:".",omittingEmptySubsequences:false)
        guard (1...3).contains(pieces.count) else {return nil}
        var numbers=[Int]()
        for piece in pieces {
            guard !piece.isEmpty,piece.utf8.allSatisfy({48...57 ~= $0}),let number=Int(piece) else {return nil}
            numbers.append(number)
        }
        parts=numbers+Array(repeating:0,count:3-numbers.count)
    }
    static func <(lhs:Self,rhs:Self)->Bool {lhs.parts.lexicographicallyPrecedes(rhs.parts)}
}

enum UpdateState:Equatable {
    case idle,checking,noRelease
    case current(String),available(String),failed(String)
}

private final class GitHubRedirects:NSObject,URLSessionTaskDelegate {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void) {
        completionHandler(request.url?.scheme=="https" && request.url?.host=="api.github.com" ? request : nil)
    }
}

final class UpdateChecker:ObservableObject {
    static let api=URL(string:"https://api.github.com/repos/Ezhov777/InternetPulse/releases/latest")!
    static let releasePage=URL(string:"https://github.com/Ezhov777/InternetPulse/releases/latest")!
    static let show=Notification.Name("InternetPulse.checkForUpdates")
    @Published private(set) var state=UpdateState.idle
    @Published private(set) var lastChecked:Date?
    let currentVersion:String
    private let fetch:(URLRequest) async throws -> (Data,URLResponse)
    init(currentVersion:String=BuildInfo.version,fetch:((URLRequest) async throws -> (Data,URLResponse))?=nil) {
        self.currentVersion=currentVersion;self.fetch=fetch ?? Self.fetchPublicRelease
    }
    private static func fetchPublicRelease(_ request:URLRequest) async throws -> (Data,URLResponse) {
        let configuration=URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies=false
        configuration.urlCache=nil
        configuration.timeoutIntervalForRequest=15
        configuration.timeoutIntervalForResource=20
        let session=URLSession(configuration:configuration,delegate:GitHubRedirects(),delegateQueue:nil)
        defer {session.finishTasksAndInvalidate()}
        return try await session.data(for:request)
    }
    @MainActor func check() async {
        guard state != .checking else {return}
        guard let current=AppVersion(currentVersion) else {state = .failed(L("Не удалось определить версию приложения."));return}
        state = .checking
        var request=URLRequest(url:Self.api,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:15)
        request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
        request.setValue("2026-03-10",forHTTPHeaderField:"X-GitHub-Api-Version")
        request.setValue("InternetPulse/\(currentVersion)",forHTTPHeaderField:"User-Agent")
        do {
            let (data,response)=try await fetch(request)
            lastChecked=Date()
            guard let http=response as? HTTPURLResponse else {state = .failed(L("GitHub вернул непонятный ответ."));return}
            switch http.statusCode {
            case 404:state = .noRelease;return
            case 403,429:state = .failed(L("GitHub временно ограничил запросы. Повторите проверку позже."));return
            case 200:break
            default:state = .failed(L("Сервис обновлений недоступен (HTTP {0}). Попробуйте позже.",String(http.statusCode)));return
            }
            struct Release:Decodable {let tag_name:String;let draft:Bool;let prerelease:Bool}
            let release=try JSONDecoder().decode(Release.self,from:data)
            guard !release.draft && !release.prerelease else {state = .noRelease;return}
            guard let latest=AppVersion(release.tag_name) else {state = .failed(L("В опубликованном релизе указан непонятный номер версии."));return}
            if latest>current {state = .available(release.tag_name)}
            else if latest==current {state = .current(L("У вас установлена актуальная версия."))}
            else {state = .current(L("Ваша версия новее последнего опубликованного релиза."))}
        } catch {
            if let error=error as? URLError,error.code == .notConnectedToInternet || error.code == .timedOut || error.code == .cannotFindHost || error.code == .cannotConnectToHost {
                state = .failed(L("Не удалось связаться с GitHub. Проверьте интернет и повторите попытку."))
            } else {state = .failed(L("Не удалось проверить обновления. Попробуйте позже."))}
        }
    }
}

struct UpdatesView:View {
    @ObservedObject var checker:UpdateChecker
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    var title:String {
        switch checker.state {
        case .idle,.checking:return L("Проверяем обновления")
        case .available(let version):return L("Доступна версия {0}",version)
        case .current:return L("Всё актуально")
        case .noRelease:return L("Релизов пока нет")
        case .failed:return L("Проверка не удалась")
        }
    }
    var detail:String {
        switch checker.state {
        case .idle,.checking:return L("Проверяем последний опубликованный выпуск в GitHub.")
        case .available:return L("Новая версия доступна на GitHub. Откройте страницу релиза, чтобы посмотреть изменения и скачать приложение.")
        case .current(let message):return message
        case .noRelease:return L("Публичный репозиторий или опубликованный релиз пока недоступен. После первого выпуска проверка начнёт находить обновления.")
        case .failed(let message):return message
        }
    }
    var body:some View {
        VStack(spacing:24) {
            HStack {
                Text("INTERNET PULSE").font(.system(size:10,weight:.bold,design:.monospaced)).tracking(2).foregroundStyle(mint)
                Spacer()
                Button {dismiss()} label: {Image(systemName:"xmark").frame(width:28,height:28)}.buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }
            if checker.state == .checking {ProgressView().controlSize(.large).frame(height:62)}
            else {Image(systemName:icon).font(.system(size:48,weight:.light)).foregroundStyle(mint).frame(height:62)}
            VStack(spacing:12) {
                Text(title).font(.system(size:25,weight:.semibold)).tracking(-0.5).multilineTextAlignment(.center)
                Text(detail).font(.system(size:13)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                Text(L("Установлена версия {0}",checker.currentVersion)).font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary).padding(.top,4)
            }
            HStack(spacing:12) {
                if case .available=checker.state {
                    Button(L("Открыть релиз на GitHub")) {openURL(UpdateChecker.releasePage)}.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black)
                } else {
                    Button(L("Проверить ещё раз")) {Task {await checker.check()}}.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black).disabled(checker.state == .checking)
                }
                Button(L("Закрыть")) {dismiss()}.buttonStyle(.bordered)
            }
            Text(L("Проверка запускается только по вашей команде. Установка обновлений — вручную.")).font(.system(size:10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(32).frame(width:500).background {
            ZStack {
                Color(red:0.045,green:0.04,blue:0.085)
                RadialGradient(colors:[blue.opacity(0.17),.clear],center:.topTrailing,startRadius:0,endRadius:600)
            }
        }.preferredColorScheme(.dark).task {await checker.check()}
    }
    var icon:String {
        switch checker.state {
        case .available:return "arrow.down.circle"
        case .current:return "checkmark.circle"
        case .noRelease:return "shippingbox"
        case .failed:return "wifi.exclamationmark"
        default:return "arrow.triangle.2.circlepath"
        }
    }
}
