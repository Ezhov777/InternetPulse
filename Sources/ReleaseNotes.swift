import SwiftUI

struct ReleaseEntry:Decodable,Identifiable {
    let version:String
    let date:String
    let title:String
    let changes:[String]
    var id:String {version}
}

enum ReleaseHistory {
    static func load(from url:URL? = Bundle.main.url(forResource:"ReleaseHistory",withExtension:"json"))->[ReleaseEntry] {
        guard let url=url,let data=try? Data(contentsOf:url),let entries=try? JSONDecoder().decode([ReleaseEntry].self,from:data) else {return []}
        return entries
    }
    static let show=Notification.Name("InternetPulse.showReleaseNotes")
}

struct ReleaseNotesView:View {
    @Environment(\.dismiss) private var dismiss
    let releases=ReleaseHistory.load()
    var currentVersion:String {Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "Development"}
    var body:some View {
        VStack(alignment:.leading,spacing:22) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:9) {
                    Text("INTERNET PULSE").font(.system(size:10,weight:.bold,design:.monospaced)).tracking(2).foregroundStyle(mint)
                    Text("Что нового").font(.system(size:32,weight:.semibold)).tracking(-0.7)
                }
                Spacer()
                Button {dismiss()} label: {Image(systemName:"xmark").font(.system(size:12,weight:.semibold)).frame(width:30,height:30)}
                    .buttonStyle(.plain).background(.white.opacity(0.06),in:Circle()).keyboardShortcut(.cancelAction).help("Закрыть историю изменений")
            }
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    if releases.isEmpty {Text("История изменений недоступна в этой сборке.").foregroundStyle(.secondary)}
                    ForEach(releases) { release in
                        VStack(alignment:.leading,spacing:16) {
                            HStack {
                                Text(release.version).font(.system(size:24,weight:.light,design:.rounded)).foregroundStyle(mint)
                                if release.version==currentVersion {
                                    Text("Текущая версия").font(.system(size:9,weight:.medium)).padding(.horizontal,9).padding(.vertical,5).background(mint.opacity(0.08),in:Capsule()).foregroundStyle(mint)
                                }
                                Spacer()
                                Text(release.date).font(.system(size:10)).foregroundStyle(.secondary)
                            }
                            Text(release.title).font(.system(size:17,weight:.medium))
                            VStack(alignment:.leading,spacing:11) {
                                ForEach(Array(release.changes.enumerated()),id:\.offset) { _,change in
                                    HStack(alignment:.top,spacing:10) {
                                        Circle().fill(blue.opacity(0.8)).frame(width:4,height:4).padding(.top,6)
                                        Text(change).font(.system(size:12)).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal:false,vertical:true)
                                    }
                                }
                            }
                        }.padding(22).frame(maxWidth:.infinity,alignment:.leading).modifier(GlassPanel())
                    }
                }.padding(2)
            }
            HStack {
                Text("Версия \(currentVersion)").font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)
                Spacer()
                Button("Готово") {dismiss()}.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width:590,height:610).background {
            ZStack {
                Color(red:0.045,green:0.04,blue:0.085)
                RadialGradient(colors:[blue.opacity(0.16),.clear],center:.topTrailing,startRadius:0,endRadius:600)
            }
        }.preferredColorScheme(.dark)
    }
}
