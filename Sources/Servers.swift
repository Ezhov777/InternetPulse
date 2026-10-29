import Foundation

struct TestServer: Identifiable, Decodable {
    let id: String
    let name: String
    let location: String
    let country: String
    let download: String
    var upload: String? = nil
    let source: String
    var label: String { "\(country) · \(name) · \(L(location)) · \(L(upload == nil ? "↓ скачивание" : "↓↑ оба направления"))" }
    static let countries = [("RU","Россия"),("GB","Великобритания"),("US","США"),("FR","Франция"),("DE","Германия"),("ES","Испания")]
    static let all: [TestServer] = {
        let url = Bundle.main.url(forResource:"Servers",withExtension:"json") ?? URL(fileURLWithPath:"Resources/Servers.json")
        return (try? JSONDecoder().decode([TestServer].self,from:Data(contentsOf:url))) ?? []
    }()
}
