import Testing
import Foundation
@testable import MyHealthWatch

/// End-to-end tests of the Apple Health export pipeline: synthetic export
/// XML → parser → ImportedHealthDataProvider → engines produce real insights.
struct HealthExportParserTests {
    // MARK: XML builder

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private func xml(daysOfHistory: Int = 21) -> String {
        let formatter = Self.exportDateFormatter
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        func d(_ offsetDays: Double, _ hour: Double) -> Date {
            startOfToday.addingTimeInterval(-offsetDays * 86400 + hour * 3600)
        }
        func s(_ date: Date) -> String {
            "'" + formatter.string(from: date) + "'"
        }

        var lines: [String] = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<!DOCTYPE HealthData>",
            "<HealthData locale=\"en_US\">",
            "<ExportDate value=\(s(Date()))/>",
            "<Me dateOfBirth=\"1992-05-17\" type=\"HKCharacteristicTypeIdentifierDateOfBirth\" value=\"1992-05-17\"/>",
        ]

        // HRV + resting HR: one value per day.
        for day in 0..<daysOfHistory {
            let value = 45 + Double((day * 7) % 9) - 4
            lines.append("<Record type=\"HKQuantityTypeIdentifierHeartRateVariabilitySDNN\" sourceName=\"Apple Watch\" unit=\"ms\" creationDate=\(s(d(Double(day), 7))) startDate=\(s(d(Double(day), 7))) endDate=\(s(d(Double(day), 7.1))) value=\"\(Int(value))\"/>")
            lines.append("<Record type=\"HKQuantityTypeIdentifierRestingHeartRate\" sourceName=\"Apple Watch\" unit=\"count/min\" creationDate=\(s(d(Double(day), 20))) startDate=\(s(d(Double(day), 20))) endDate=\(s(d(Double(day), 20.1))) value=\"\(54 + Double((day * 3) % 5) - 2)\"/>")
        }

        // Sleep: one realistic night per day (asleep ~460 min).
        for night in 1...min(daysOfHistory, 14) {
            let bedtime = d(Double(night), 23) // 23:00, `night` days ago
            var cursor = bedtime
            let cycle: [(String, Double)] = [
                ("HKCategoryValueSleepAnalysisInBed", 470),
                ("HKCategoryValueSleepAnalysisAsleepCore", 200),
                ("HKCategoryValueSleepAnalysisAsleepDeep", 80),
                ("HKCategoryValueSleepAnalysisAsleepREM", 90),
                ("HKCategoryValueSleepAnalysisAwake", 20),
                ("HKCategoryValueSleepAnalysisAsleepCore", 70),
            ]
            for (stage, minutes) in cycle {
                let start = cursor
                let end = cursor.addingTimeInterval(minutes * 60)
                lines.append("<Record type=\"HKCategoryTypeIdentifierSleepAnalysis\" sourceName=\"Apple Watch\" creationDate=\(s(end)) startDate=\(s(start)) endDate=\(s(end)) value=\"\(stage)\"/>")
                cursor = end
            }
        }

        // Recent heart-rate stream (last 3 hours, every 10 min).
        for sample in stride(from: 0.0, through: 170.0, by: 10.0) {
            let date = Date().addingTimeInterval(-(170.0 - sample) * 60)
            lines.append("<Record type=\"HKQuantityTypeIdentifierHeartRate\" sourceName=\"Apple Watch\" unit=\"count/min\" creationDate=\(s(date)) startDate=\(s(date)) endDate=\(s(date)) value=\"\(Int(62 + (sample.truncatingRemainder(dividingBy: 30)) / 3))\"/>")
        }

        // Activity + fitness.
        lines.append("<Record type=\"HKQuantityTypeIdentifierStepCount\" sourceName=\"iPhone\" unit=\"count\" startDate=\(s(startOfToday)) endDate=\(s(startOfToday.addingTimeInterval(3600))) value=\"8200\"/>")
        lines.append("<Record type=\"HKQuantityTypeIdentifierActiveEnergyBurned\" sourceName=\"Apple Watch\" unit=\"kcal\" startDate=\(s(startOfToday)) endDate=\(s(startOfToday.addingTimeInterval(3600))) value=\"640\"/>")
        lines.append("<Record type=\"HKQuantityTypeIdentifierVO2Max\" sourceName=\"Apple Watch\" unit=\"ml/kg*min\" startDate=\(s(d(1, 9))) endDate=\(s(d(1, 9))) value=\"42.5\"/>")
        lines.append("<Record type=\"HKQuantityTypeIdentifierWalkingHeartRateAverage\" sourceName=\"Apple Watch\" unit=\"count/min\" startDate=\(s(d(1, 9))) endDate=\(s(d(1, 9))) value=\"67\"/>")

        // Workouts (every 2nd day, 50 min @ ~148 bpm).
        for day in stride(from: 1, through: min(daysOfHistory, 27), by: 2) {
            let start = d(Double(day), 18)
            let end = start.addingTimeInterval(50 * 60)
            lines.append("""
            <Workout workoutActivityType="HKWorkoutActivityTypeRunning" duration="50.0" durationUnit="min" totalDistance="7.5" totalDistanceUnit="km" totalEnergyBurned="430" totalEnergyBurnedUnit="kcal" sourceName="Apple Watch" creationDate=\(s(end)) startDate=\(s(start)) endDate=\(s(end))>
              <Statistics type="HKQuantityTypeIdentifierHeartRate" average="148" minimum="98" maximum="172" unit="count/min"/>
            </Workout>
            """)
        }

        // Irrelevant record types must be skipped silently.
        lines.append("<Record type=\"HKQuantityTypeIdentifierBodyMass\" sourceName=\"iPhone\" startDate=\(s(d(3, 10))) endDate=\(s(d(3, 10))) value=\"72\" unit=\"kg\"/>")

        lines.append("</HealthData>")
        return lines.joined(separator: "\n")
    }

    // MARK: Parser

    @Test func parsesXMLIntoAggregates() throws {
        let data = Data(xml().utf8)
        let (export, summary) = try AppleHealthExportParser.parse(fileData: data)

        #expect(export.hrvSamples.count >= 14)
        #expect(export.restingHeartRateByDay.count >= 14)
        #expect(export.sleepSamples.count >= 14 * 6)
        #expect(export.recentHeartRate.count >= 15)
        #expect(export.workouts.count >= 10)
        #expect(export.latestVO2Max == 42.5)
        #expect(export.latestWalkingHeartRateAverage == 67)
        #expect(export.dateOfBirth != nil)
        #expect(export.dailySteps.first?.value == 8200)
        #expect(export.dailyActiveEnergy.first?.value == 640)

        #expect(summary.workoutCount == export.workouts.count)
        #expect(summary.sleepNightCount >= 14)
        #expect(summary.dateOfBirthFound)
    }

    @Test func rejectsGarbageInput() {
        #expect(throws: HealthExportParseError.self) {
            _ = try AppleHealthExportParser.parse(fileData: Data("not a health export".utf8))
        }
    }

    @Test func rejectsEmptyUsefulExport() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="en_US">
        <Record type="HKQuantityTypeIdentifierBodyMass" sourceName="iPhone" startDate="2026-08-15 10:00:00 +0000" endDate="2026-08-15 10:00:00 +0000" value="72" unit="kg"/>
        </HealthData>
        """
        #expect(throws: HealthExportParseError.self) {
            _ = try AppleHealthExportParser.parse(fileData: Data(xml.utf8))
        }
    }

    // MARK: Provider + engines end-to-end

    @Test func importedDataFeedsEngines() async throws {
        let data = Data(xml(daysOfHistory: 21).utf8)
        let (export, _) = try AppleHealthExportParser.parse(fileData: data)
        let provider = ImportedHealthDataProvider(export: export)

        // Sleep → analyzer → scored night.
        let sleepSamples = try await provider.sleepSamples(nights: 21)
        let nights = SleepNightAssembler.nights(from: sleepSamples)
        #expect(nights.count >= 14)
        guard let lastNight = SleepNightAssembler.lastNight(from: nights, within: 30 * 24) else {
            Issue.record("Expected a recent night")
            return
        }
        let sleepResult = SleepAnalyzer.analyze(night: lastNight, personalNeedMinutes: 460, timingBaselineMinutes: nil)
        #expect(sleepResult.hasScore)
        #expect(sleepResult.night.breakdown.asleepMinutes > 400)

        // Workouts → load.
        let rawWorkouts = try await provider.workouts(days: 35)
        #expect(!rawWorkouts.isEmpty)
        #expect(rawWorkouts[0].averageHeartRate == 148)

        // Recovery with real parsed baselines.
        let hrv = try await provider.hrvSamples(days: 35)
        let hrvBaseline = BaselineCalculator.baseline(
            values: hrv.map(\.milliseconds),
            dates: hrv.map(\.date),
            window: .fourteenDays
        )
        let resting = try await provider.restingHeartRateSamples(days: 35)
        let restingBaseline = BaselineCalculator.baseline(
            values: resting.map(\.beatsPerMinute),
            dates: resting.map(\.date),
            window: .fourteenDays
        )
        #expect(hrvBaseline?.isSufficient == true)
        #expect(restingBaseline?.isSufficient == true)

        let recovery = RecoveryEngine.compute(RecoveryInput(
            date: Date(),
            latestHRV: hrv.last,
            hrvBaseline: hrvBaseline,
            latestRestingHeartRate: resting.last?.beatsPerMinute,
            restingHeartRateBaseline: restingBaseline,
            lastNightAsleepMinutes: lastNight.breakdown.asleepMinutes,
            personalSleepNeedMinutes: 460,
            sleepTimingDeviationMinutes: SleepAnalyzer.timingDeviation(night: lastNight, timingBaselineMinutes: nil),
            acuteToChronicRatio: 1.0
        ))
        #expect(recovery.hasScore)
        #expect(recovery.confidence == .high)

        // Stress from the imported HR stream.
        let heartRate = try await provider.heartRateSamples(
            from: Date().addingTimeInterval(-6 * 3600),
            to: Date()
        )
        #expect(!heartRate.isEmpty)
        let windows = StressEngine.WindowBuilder.windows(from: heartRate, windowMinutes: 10) { _ in false }
        let stress = StressEngine.compute(
            windows: windows,
            restingBaseline: restingBaseline?.median,
            latestHRV: hrv.last,
            hrvBaseline: hrvBaseline
        )
        #expect(stress != nil)

        // Energy composes recovery + sleep.
        let energy = EnergyEngine.compute(recovery: recovery, sleep: sleepResult, load: nil)
        #expect(energy != nil)
    }

    @Test func roundTripPersistsThroughStore() throws {
        // Codable round-trip must preserve everything the engines need.
        let data = Data(xml(daysOfHistory: 10).utf8)
        let (export, _) = try AppleHealthExportParser.parse(fileData: data)

        let encoded = try JSONEncoder().encode(export)
        let decoded = try JSONDecoder().decode(ParsedHealthExport.self, from: encoded)

        #expect(decoded == export)
    }

    @Test func emptyProviderYieldsHonestNoData() async throws {
        let provider = ImportedHealthDataProvider(export: nil)
        let hrv = try await provider.hrvSamples(days: 30)
        let sleep = try await provider.sleepSamples(nights: 14)
        let workouts = try await provider.workouts(days: 30)
        #expect(hrv.isEmpty && sleep.isEmpty && workouts.isEmpty)
    }
}

/// Zip extraction correctness (the CI/sideload import path starts with a zip).
struct ZipEntryReaderTests {
    /// Build a stored (uncompressed) zip containing one file. CRC is not
    /// validated by the reader, so a placeholder is written.
    private func storedZip(entryName: String, contents: Data) -> Data {
        var out = Data()
        let nameBytes = Array(entryName.utf8)
        let crc: UInt32 = 0

        // Local file header
        out.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])
        out.append(contentsOf: [0x14, 0x00]) // version
        out.append(contentsOf: [0x00, 0x00]) // flags
        out.append(contentsOf: [0x00, 0x00]) // method: stored
        out.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // time/date
        append(UInt32(truncatingIfNeeded: crc), to: &out)
        append(UInt32(contents.count), to: &out) // compressed
        append(UInt32(contents.count), to: &out) // uncompressed
        append(UInt16(nameBytes.count), to: &out)
        append(UInt16(0), to: &out) // extra len
        out.append(contentsOf: nameBytes)
        out.append(contents)

        let cdOffset = out.count
        // Central directory entry
        out.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])
        out.append(contentsOf: [0x14, 0x00]) // version made by
        out.append(contentsOf: [0x14, 0x00]) // version needed
        out.append(contentsOf: [0x00, 0x00]) // flags
        out.append(contentsOf: [0x00, 0x00]) // method
        out.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // time/date
        append(UInt32(truncatingIfNeeded: crc), to: &out)
        append(UInt32(contents.count), to: &out)
        append(UInt32(contents.count), to: &out)
        append(UInt16(nameBytes.count), to: &out)
        append(UInt16(0), to: &out) // extra
        append(UInt16(0), to: &out) // comment
        append(UInt16(0), to: &out) // disk
        append(UInt16(0), to: &out) // internal attrs
        append(UInt32(0), to: &out) // external attrs
        append(UInt32(0), to: &out) // local header offset
        out.append(contentsOf: nameBytes)

        // End of central directory
        let cdSize = out.count - cdOffset
        out.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
        append(UInt16(0), to: &out) // disk
        append(UInt16(0), to: &out) // cd disk
        append(UInt16(1), to: &out) // entries on disk
        append(UInt16(1), to: &out) // total entries
        append(UInt32(cdSize), to: &out)
        append(UInt32(cdOffset), to: &out)
        append(UInt16(0), to: &out) // comment len
        return out
    }

    private func append(_ value: UInt16, to data: inout Data) {
        data.append(contentsOf: [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
        ])
    }

    private func append(_ value: UInt32, to data: inout Data) {
        data.append(contentsOf: [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ])
    }

    @Test func extractsStoredEntryByName() throws {
        let payload = Data("<HealthData></HealthData>".utf8)
        let zip = storedZip(entryName: "export.xml", contents: payload)
        let extracted = try ZipEntryReader.extractEntry(named: "export.xml", from: zip)
        #expect(extracted == payload)
    }

    @Test func missingEntryThrows() {
        let zip = storedZip(entryName: "other.txt", contents: Data("x".utf8))
        #expect(throws: ZipEntryReader.ZipError.self) {
            _ = try ZipEntryReader.extractEntry(named: "export.xml", from: zip)
        }
    }

    @Test func xmlThroughZipParses() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="en_US">
        <Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" sourceName="Apple Watch" unit="ms" startDate="2026-08-16 07:00:00 +0000" endDate="2026-08-16 07:00:00 +0000" value="45"/>
        </HealthData>
        """
        let zip = storedZip(entryName: "export.xml", contents: Data(xml.utf8))
        let (export, _) = try AppleHealthExportParser.parse(fileData: zip)
        #expect(export.hrvSamples.count == 1)
        #expect(export.hrvSamples[0].milliseconds == 45)
    }
}
