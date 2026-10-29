import Foundation
import SwiftUI

final class AppLanguage: ObservableObject {
    static let shared = AppLanguage()
    static let choices = [("ru", "Русский"), ("en", "English"), ("fr", "Français"), ("de", "Deutsch"), ("es", "Español")]
    @Published var code: String { didSet { UserDefaults.standard.set(code, forKey: "appLanguage"); NotificationCenter.default.post(name: Notification.Name("InternetPulse.languageChanged"), object: nil) } }
    var locale: Locale { Locale(identifier: ["ru":"ru_RU", "en":"en_GB", "fr":"fr_FR", "de":"de_DE", "es":"es_ES"][code] ?? "en_GB") }
    private init() {
        let preferred = UserDefaults.standard.string(forKey: "appLanguage") ?? String(Locale.preferredLanguages.first?.prefix(2) ?? "en")
        code = Self.choices.contains(where: {$0.0 == preferred}) ? preferred : "en"
    }
    static let translations: [String:[String:String]] = {
        let url = Bundle.main.url(forResource: "Translations", withExtension: "json") ?? URL(fileURLWithPath: "Resources/Translations.json")
        return (try? JSONDecoder().decode([String:[String:String]].self, from: Data(contentsOf: url))) ?? [:]
    }()
}

func L(_ key: String, _ arguments: String...) -> String {
    var value = AppLanguage.translations[AppLanguage.shared.code]?[key] ?? key
    for (index, argument) in arguments.enumerated() { value = value.replacingOccurrences(of: "{\(index)}", with: argument) }
    return value
}

enum TrafficFormat {
    static func amount(_ bytes: UInt64, unit: String, locale: Locale = AppLanguage.shared.locale) -> String {
        let normalized = ["МБ":"MB", "ГБ":"GB", "ТБ":"TB"][unit] ?? unit
        let divisor = normalized == "TB" ? 1e12 : normalized == "GB" ? 1e9 : 1e6
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return (formatter.string(from: NSNumber(value: Double(bytes)/divisor)) ?? "0") + " " + L(normalized)
    }
    static func speed(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = AppLanguage.shared.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1; formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }
}

// A renderer can read VERSION without pretending that a CLI binary is an app bundle.
enum BuildInfo {
    static var version:String {
        if let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String {return version}
        #if TESTING
        return (try? String(contentsOfFile:"VERSION",encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines)) ?? "Development"
        #else
        return "Development"
        #endif
    }
}
