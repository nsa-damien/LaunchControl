import Foundation

struct CalendarInterval: Equatable {
    var month: Int?
    var day: Int?
    var weekday: Int?
    var hour: Int?
    var minute: Int?

    init(from dict: [String: Any]) {
        month = dict["Month"] as? Int
        day = dict["Day"] as? Int
        weekday = dict["Weekday"] as? Int
        hour = dict["Hour"] as? Int
        minute = dict["Minute"] as? Int
    }

    init(month: Int? = nil, day: Int? = nil, weekday: Int? = nil, hour: Int? = nil, minute: Int? = nil) {
        self.month = month
        self.day = day
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
    }

    func toDictionary() -> [String: Int] {
        var dict: [String: Int] = [:]
        if let month { dict["Month"] = month }
        if let day { dict["Day"] = day }
        if let weekday { dict["Weekday"] = weekday }
        if let hour { dict["Hour"] = hour }
        if let minute { dict["Minute"] = minute }
        return dict
    }
}

struct PlistDocument {
    enum ParseError: LocalizedError {
        case invalidData
        case missingLabel

        var errorDescription: String? {
            switch self {
            case .invalidData: return "File is not a valid property list"
            case .missingLabel: return "Property list has no Label key"
            }
        }
    }

    let label: String
    var program: String?
    var programArguments: [String]
    var runAtLoad: Bool
    var keepAlive: Bool
    var startInterval: Int?
    var startCalendarInterval: [CalendarInterval]
    var watchPaths: [String]
    var environmentVariables: [String: String]
    var workingDirectory: String?
    var standardOutPath: String?
    var standardErrorPath: String?
    var throttleInterval: Int?
    var nice: Int?
    var processType: String?
    var otherKeys: [String: Any]
    let rawXML: String

    private static let structuredKeys: Set<String> = [
        "Label", "Program", "ProgramArguments", "RunAtLoad", "KeepAlive",
        "StartInterval", "StartCalendarInterval", "WatchPaths",
        "EnvironmentVariables", "WorkingDirectory", "StandardOutPath",
        "StandardErrorPath", "ThrottleInterval", "Nice", "ProcessType"
    ]

    init(data: Data) throws {
        guard let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ParseError.invalidData
        }
        guard let label = dict["Label"] as? String else {
            throw ParseError.missingLabel
        }

        self.label = label
        self.program = dict["Program"] as? String
        self.programArguments = dict["ProgramArguments"] as? [String] ?? []
        self.runAtLoad = dict["RunAtLoad"] as? Bool ?? false
        self.keepAlive = dict["KeepAlive"] as? Bool ?? false
        self.startInterval = dict["StartInterval"] as? Int
        self.watchPaths = dict["WatchPaths"] as? [String] ?? []
        self.environmentVariables = dict["EnvironmentVariables"] as? [String: String] ?? [:]
        self.workingDirectory = dict["WorkingDirectory"] as? String
        self.standardOutPath = dict["StandardOutPath"] as? String
        self.standardErrorPath = dict["StandardErrorPath"] as? String
        self.throttleInterval = dict["ThrottleInterval"] as? Int
        self.nice = dict["Nice"] as? Int
        self.processType = dict["ProcessType"] as? String

        if let intervals = dict["StartCalendarInterval"] as? [[String: Any]] {
            self.startCalendarInterval = intervals.map { CalendarInterval(from: $0) }
        } else if let single = dict["StartCalendarInterval"] as? [String: Any] {
            self.startCalendarInterval = [CalendarInterval(from: single)]
        } else {
            self.startCalendarInterval = []
        }

        self.otherKeys = dict.filter { !Self.structuredKeys.contains($0.key) }

        if let xmlData = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0),
           let xml = String(data: xmlData, encoding: .utf8) {
            self.rawXML = xml
        } else {
            self.rawXML = ""
        }
    }

    func toDictionary() -> [String: Any] {
        var dict = otherKeys
        dict["Label"] = label
        if let program { dict["Program"] = program }
        if !programArguments.isEmpty { dict["ProgramArguments"] = programArguments }
        if runAtLoad { dict["RunAtLoad"] = true }
        if keepAlive { dict["KeepAlive"] = true }
        if let startInterval { dict["StartInterval"] = startInterval }
        if !startCalendarInterval.isEmpty {
            dict["StartCalendarInterval"] = startCalendarInterval.map { $0.toDictionary() }
        }
        if !watchPaths.isEmpty { dict["WatchPaths"] = watchPaths }
        if !environmentVariables.isEmpty { dict["EnvironmentVariables"] = environmentVariables }
        if let workingDirectory { dict["WorkingDirectory"] = workingDirectory }
        if let standardOutPath { dict["StandardOutPath"] = standardOutPath }
        if let standardErrorPath { dict["StandardErrorPath"] = standardErrorPath }
        if let throttleInterval { dict["ThrottleInterval"] = throttleInterval }
        if let nice { dict["Nice"] = nice }
        if let processType { dict["ProcessType"] = processType }
        return dict
    }
}
