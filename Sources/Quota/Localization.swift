import Foundation

enum L {
    static let language = Bundle.preferredLocalizations(from: QuotaResources.bundle.localizations, forPreferences: Locale.preferredLanguages).first ?? "en"
    static let bundle = languageBundle(preferences: Locale.preferredLanguages)
    static func languageBundle(preferences: [String]) -> Bundle {
        let resources = QuotaResources.bundle
        let language = Bundle.preferredLocalizations(from: resources.localizations, forPreferences: preferences).first ?? "en"
        return resources.url(forResource: language, withExtension: "lproj").flatMap(Bundle.init(url:)) ?? resources
    }
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
    static func window(_ label: String) -> String {
        let parts = label.components(separatedBy: " · ")
        return parts.map { bundle.localizedString(forKey: $0, value: $0, table: nil) }.joined(separator: " · ")
    }
    static func days(_ days: Int) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current; calendar.locale = Locale(identifier: language)
        formatter.calendar = calendar
        formatter.allowedUnits = [.day]; formatter.unitsStyle = .abbreviated
        return formatter.string(from: DateComponents(day: days)) ?? String(days)
    }
    static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current; calendar.locale = Locale(identifier: language)
        formatter.calendar = calendar
        formatter.allowedUnits = seconds >= 86400 ? [.day, .hour] : seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? ""
    }
}
