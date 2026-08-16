import Foundation

/// Errors surfaced to the Import UI with user-friendly descriptions.
enum HealthExportParseError: LocalizedError, Equatable {
    case notAZipOrXML
    case exportXMLNotFound
    case malformedArchive(String)
    case xmlParsingFailed(String)
    case emptyExport

    var errorDescription: String? {
        switch self {
        case .notAZipOrXML:
            return "Please choose an Apple Health export file (export.zip), or an export.xml you unzipped yourself."
        case .exportXMLNotFound:
            return "No export.xml found inside the archive. Make sure this is the Health app's export."
        case .malformedArchive(let detail):
            return "The archive could not be read: \(detail)"
        case .xmlParsingFailed(let detail):
            return "The export could not be parsed: \(detail)"
        case .emptyExport:
            return "This export contains none of the data myhealth uses (heart rate, sleep, workouts)."
        }
    }
}

/// Parses Apple Health exports (`export.zip` / `export.xml`) into a bounded
/// `ParsedHealthExport` using a streaming `XMLParser` — the full XML is never
/// turned into objects; irrelevant record types are skipped as they stream by.
///
/// Apple Health export XML shape (relevant subset):
/// - `<HealthData><ExportDate value="…"/><Me dateOfBirth="YYYY-MM-DD"/> …`
/// - `<Record type="HKQuantityTypeIdentifierHeartRate" sourceName="…"
///    startDate="2026-08-15 22:10:00 +0530" endDate="…" value="62" unit="count/min"/>`
/// - Sleep records use categorical values, e.g.
///   `value="HKCategoryValueSleepAnalysisAsleepCore"` (modern) or numeric
///   0/1/2 (legacy).
/// - `<Workout workoutActivityType="HKWorkoutActivityTypeRunning" duration="…"
///    durationUnit="min" totalDistance="…" totalDistanceUnit="km"
///    totalEnergyBurned="…" totalEnergyBurnedUnit="kcal" startDate="…"
///    endDate="…"><Statistics type="HKQuantityTypeIdentifierHeartRate"
///    average="148" …/></Workout>`
enum AppleHealthExportParser {
    static func parse(fileData: Data) throws -> (export: ParsedHealthExport, summary: ImportSummary) {
        let xmlData: Data
        if fileData.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            do {
                xmlData = try ZipEntryReader.extractEntry(named: "export.xml", from: fileData)
            } catch let error as ZipEntryReader.ZipError where error == .entryNotFound("export.xml") {
                throw HealthExportParseError.exportXMLNotFound
            } catch let error as ZipEntryReader.ZipError {
                throw HealthExportParseError.malformedArchive(error.errorDescription ?? "unknown")
            }
        } else if fileData.starts(with: Data("<?xml".utf8)) || fileData.first == UInt8(ascii: "<") {
            xmlData = fileData
        } else {
            throw HealthExportParseError.notAZipOrXML
        }

        let delegate = ExportXMLDelegate()
        let parser = XMLParser(data: xmlData)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            throw HealthExportParseError.xmlParsingFailed(
                parser.parserError?.localizedDescription ?? "unknown parser error"
            )
        }

        var export = delegate.buildExport()
        export.exportDate = delegate.exportDate
        export.dateOfBirth = delegate.dateOfBirth

        guard export.isUsable else {
            throw HealthExportParseError.emptyExport
        }

        export.summary.exportDate = delegate.exportDate
        export.summary.dateOfBirthFound = delegate.dateOfBirth != nil
        return (export, export.summary)
    }
}

// MARK: - Streaming delegate

private final class ExportXMLDelegate: NSObject, XMLParserDelegate {
    // Type identifiers myhealth understands.
    private static let heartRate = "HKQuantityTypeIdentifierHeartRate"
    private static let restingHeartRate = "HKQuantityTypeIdentifierRestingHeartRate"
    private static let hrv = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
    private static let sleepAnalysis = "HKCategoryTypeIdentifierSleepAnalysis"
    private static let steps = "HKQuantityTypeIdentifierStepCount"
    private static let activeEnergy = "HKQuantityTypeIdentifierActiveEnergyBurned"
    private static let vo2Max = "HKQuantityTypeIdentifierVO2Max"
    private static let walkingHeartRate = "HKQuantityTypeIdentifierWalkingHeartRateAverage"
    private static let dateOfBirthType = "HKCharacteristicTypeIdentifierDateOfBirth"

    // Bounded-memory retention windows.
    private static let recentHeartRateWindow: TimeInterval = 36 * 3600
    private static let hrvWindow: TimeInterval = 60 * 24 * 3600
    private static let restingDayWindow = 60
    private static let sleepWindow: TimeInterval = 21 * 24 * 3600
    private static let workoutWindow: TimeInterval = 35 * 24 * 3600

    private let calendar = Calendar.current
    private let now = Date()

    // Export date format: "2026-08-16 09:12:44 +0530".
    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // Parsed state.
    private(set) var exportDate: Date?
    private(set) var dateOfBirth: Date?
    private var recentHeartRate: [HeartRateSample] = []
    private var restingByDay: [String: (value: Double, date: Date)] = [:]
    private var hrvSamples: [HRVSample] = []
    private var sleepSamples: [SleepSample] = []
    private var stepsByDay: [String: Double] = [:]
    private var energyByDay: [String: Double] = [:]
    private var vo2MaxLatest: (value: Double, date: Date)?
    private var walkingLatest: (value: Double, date: Date)?
    private var workouts: [RawWorkout] = []
    private var recordCount = 0

    // In-flight <Workout> assembly.
    private var currentWorkout: WorkoutAccumulator?
    private struct WorkoutAccumulator {
        var type: String
        var startDate: Date?
        var endDate: Date?
        var durationMinutes: Double?
        var calories: Double?
        var distanceKm: Double?
        var averageHeartRate: Double?
    }

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "ExportDate":
            exportDate = Self.exportDateFormatter.date(from: attributeDict["value"] ?? "")
        case "Me":
            if let dob = attributeDict["dateOfBirth"] {
                dateOfBirth = Self.dayFormatter.date(from: dob)
            }
        case "Record":
            handleRecord(attributeDict)
        case "Workout":
            currentWorkout = WorkoutAccumulator(
                type: attributeDict["workoutActivityType"] ?? "",
                startDate: Self.exportDateFormatter.date(from: attributeDict["startDate"] ?? ""),
                endDate: Self.exportDateFormatter.date(from: attributeDict["endDate"] ?? ""),
                durationMinutes: Self.minutes(from: attributeDict["duration"], unit: attributeDict["durationUnit"]),
                calories: Self.kilocalories(from: attributeDict["totalEnergyBurned"], unit: attributeDict["totalEnergyBurnedUnit"]),
                distanceKm: Self.kilometers(from: attributeDict["totalDistance"], unit: attributeDict["totalDistanceUnit"]),
                averageHeartRate: nil
            )
        case "Statistics":
            // Average HR inside a <Workout>.
            if currentWorkout != nil,
               (attributeDict["type"] ?? "").contains("HeartRate"),
               let average = Double(attributeDict["average"] ?? "") {
                currentWorkout?.averageHeartRate = average
            }
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "Workout", let workout = currentWorkout {
            currentWorkout = nil
            appendWorkout(workout)
        }
    }

    // MARK: Record handling

    private func handleRecord(_ attributes: [String: String]) {
        let type = attributes["type"] ?? ""

        if type == heartRate {
            guard let value = Double(attributes["value"] ?? ""),
                  let endDate = Self.exportDateFormatter.date(from: attributes["endDate"] ?? ""),
                  now.timeIntervalSince(endDate) <= Self.recentHeartRateWindow,
                  now.timeIntervalSince(endDate) >= -3600 else { return }
            recentHeartRate.append(HeartRateSample(beatsPerMinute: value, date: endDate))
            recordCount += 1
            return
        }

        if type == restingHeartRate {
            guard let value = Double(attributes["value"] ?? ""),
                  let startDate = Self.exportDateFormatter.date(from: attributes["startDate"] ?? "") else { return }
            let day = Self.dayFormatter.string(from: startDate)
            if let existing = restingByDay[day], existing.date > startDate { return }
            restingByDay[day] = (value, startDate)
            recordCount += 1
            return
        }

        if type == hrv {
            guard let value = Double(attributes["value"] ?? ""),
                  let startDate = Self.exportDateFormatter.date(from: attributes["startDate"] ?? "") else { return }
            guard now.timeIntervalSince(startDate) <= Self.hrvWindow else { return }
            hrvSamples.append(HRVSample(milliseconds: value, date: startDate))
            recordCount += 1
            return
        }

        if type == sleepAnalysis {
            guard let stage = Self.sleepStage(fromValue: attributes["value"] ?? ""),
                  let startDate = Self.exportDateFormatter.date(from: attributes["startDate"] ?? ""),
                  let endDate = Self.exportDateFormatter.date(from: attributes["endDate"] ?? "") else { return }
            guard now.timeIntervalSince(endDate) <= Self.sleepWindow else { return }
            sleepSamples.append(SleepSample(stage: stage, start: startDate, end: endDate))
            recordCount += 1
            return
        }

        if type == steps || type == activeEnergy {
            guard let value = Double(attributes["value"] ?? ""),
                  let startDate = Self.exportDateFormatter.date(from: attributes["startDate"] ?? "") else { return }
            let day = Self.dayFormatter.string(from: startDate)
            if type == steps {
                stepsByDay[day, default: 0] += value
            } else {
                energyByDay[day, default: 0] += value
            }
            recordCount += 1
            return
        }

        if type == vo2Max {
            guard let value = Double(attributes["value"] ?? ""),
                  let endDate = Self.exportDateFormatter.date(from: attributes["endDate"] ?? "") else { return }
            if vo2MaxLatest == nil || vo2MaxLatest!.date < endDate {
                vo2MaxLatest = (value, endDate)
            }
            recordCount += 1
            return
        }

        if type == walkingHeartRate {
            guard let value = Double(attributes["value"] ?? ""),
                  let endDate = Self.exportDateFormatter.date(from: attributes["endDate"] ?? "") else { return }
            if walkingLatest == nil || walkingLatest!.date < endDate {
                walkingLatest = (value, endDate)
            }
            recordCount += 1
            return
        }

        if type == dateOfBirthType, dateOfBirth == nil {
            dateOfBirth = Self.dayFormatter.date(from: attributes["value"] ?? "")
        }
    }

    // MARK: Workout finalization

    private func appendWorkout(_ workout: WorkoutAccumulator) {
        guard let start = workout.startDate, let end = workout.endDate else { return }
        guard now.timeIntervalSince(start) <= Self.workoutWindow else { return }

        let typeString = workout.type
        let kind: WorkoutKind
        if typeString.contains("Running") {
            kind = .running
        } else if typeString.contains("Walking") {
            kind = .walking
        } else if typeString.contains("Cycling") {
            kind = .cycling
        } else if typeString.contains("StrengthTraining") {
            kind = .strengthTraining
        } else {
            kind = .other
        }

        // Duration is derived from start/end by LoadEngine; the export's
        // duration attribute is only a fallback we don't need to keep.
        workouts.append(RawWorkout(
            kind: kind,
            start: start,
            end: end,
            averageHeartRate: workout.averageHeartRate,
            activeCalories: workout.calories,
            distanceKilometers: workout.distanceKm,
            recordedByMyHealth: false
        ))
    }

    // MARK: Output

    func buildExport() -> ParsedHealthExport {
        var export = ParsedHealthExport()

        export.recentHeartRate = recentHeartRate.sorted { $0.date < $1.date }
        export.hrvSamples = hrvSamples.sorted { $0.date < $1.date }
        export.sleepSamples = sleepSamples.sorted { $0.start < $1.start }
        export.restingHeartRateByDay = restingByDay
            .map { DailyScalar(day: $0.key, value: $0.value.value) }
            .sorted { $0.day < $1.day }
        export.dailySteps = stepsByDay
            .map { DailyScalar(day: $0.key, value: $0.value) }
            .sorted { $0.day < $1.day }
        export.dailyActiveEnergy = energyByDay
            .map { DailyScalar(day: $0.key, value: $0.value) }
            .sorted { $0.day < $1.day }
        export.latestVO2Max = vo2MaxLatest?.value
        export.latestWalkingHeartRateAverage = walkingLatest?.value
        export.workouts = workouts.sorted { $0.start > $1.start }

        // Trim per-day series to the retention bound.
        export.restingHeartRateByDay = Array(export.restingHeartRateByDay.suffix(Self.restingDayWindow))

        var summary = ImportSummary()
        summary.recordCount = recordCount
        summary.hrvSampleCount = export.hrvSamples.count
        summary.restingHeartRateDayCount = export.restingHeartRateByDay.count
        summary.sleepIntervalCount = export.sleepSamples.count
        summary.workoutCount = export.workouts.count
        summary.sleepNightCount = SleepNightAssembler.nights(from: export.sleepSamples).count
        export.summary = summary

        return export
    }

    // MARK: Unit helpers

    private static func minutes(from value: String?, unit: String?) -> Double? {
        guard let value, let number = Double(value) else { return nil }
        let unit = unit ?? "min"
        if unit.contains("hr") { return number * 60 }
        if unit.contains("s") && !unit.contains("min") { return number / 60 }
        return number
    }

    private static func kilocalories(from value: String?, unit: String?) -> Double? {
        guard let value, let number = Double(value) else { return nil }
        if (unit ?? "kcal").contains("kJ") { return number * 0.239 }
        return number
    }

    private static func kilometers(from value: String?, unit: String?) -> Double? {
        guard let value, let number = Double(value) else { return nil }
        let unit = unit ?? "km"
        if unit.contains("mi") { return number * 1.60934 }
        if unit.contains("m") && !unit.contains("km") && !unit.contains("mi") {
            return number / 1000 // meters
        }
        return number
    }

    /// Modern exports use categorical strings; very old ones used numbers.
    private static func sleepStage(fromValue value: String) -> SleepStageKind? {
        switch value {
        case _ where value.contains("InBed"): return .inBed
        case _ where value.contains("AsleepUnspecified"): return .unspecifiedAsleep
        case _ where value.contains("AsleepCore"): return .core
        case _ where value.contains("AsleepDeep"): return .deep
        case _ where value.contains("AsleepREM"): return .rem
        case _ where value.contains("Awake"): return .awake
        case _ where value.contains("Asleep"): return .unspecifiedAsleep
        case "0": return .inBed
        case "1": return .unspecifiedAsleep
        case "2": return .awake
        case "3": return .deep
        case "4": return .rem
        default: return nil
        }
    }
}
