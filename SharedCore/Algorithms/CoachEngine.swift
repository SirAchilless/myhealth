import Foundation

/// The deterministic, local coach. It answers the five quick questions from
/// `CoachContext` using the same engine results the app displays — never
/// inventing data, never giving medical advice. Optional AI features would be
/// additive (see docs/PRIVACY.md) and are not part of v1.
enum CoachEngine {
    // MARK: Daily recommendation

    static func recommendation(for context: CoachContext) -> CoachRecommendation {
        let recovery = context.recovery
        let sleep = context.sleep
        let load = context.load

        // Insufficient data beats everything else.
        guard let recovery, recovery.hasScore else {
            if sleep?.hasScore != true {
                return CoachRecommendation(
                    title: "Building your baseline",
                    detail: "Keep wearing your Apple Watch to bed and during workouts. Insights start once a few days of data build up.",
                    tone: .buildData
                )
            }
            return CoachRecommendation(
                title: "Go by feel today",
                detail: "Recovery data is still building, but your sleep looks \(ratingWord(sleep)). A normal day of activity is fine.",
                tone: .moderate
            )
        }

        let highLoad = load?.band == .high

        if recovery.score >= 70 {
            if highLoad {
                return CoachRecommendation(
                    title: "Train, but keep it mixed",
                    detail: "Recovery is \(recovery.category.rawValue.lowercased()), though your recent load is already high. A moderate session fits better than a hard one.",
                    tone: .moderate
                )
            }
            return CoachRecommendation(
                title: "Good day to train",
                detail: "Recovery is \(recovery.category.rawValue.lowercased()) and your body seems ready. A harder session fits today.",
                tone: .train
            )
        }

        if recovery.score >= 50 {
            return CoachRecommendation(
                title: "Moderate day",
                detail: "Recovery is moderate. Steady, comfortable training or an active recovery day both fit.",
                tone: .moderate
            )
        }

        return CoachRecommendation(
            title: "Prioritize recovery",
            detail: "Recovery is low today. Favor sleep, easy movement like a walk, and save hard training for another day.",
            tone: .recover
        )
    }

    // MARK: Quick questions

    static func answer(_ question: CoachQuestion, context: CoachContext) -> CoachAnswer {
        switch question {
        case .howAmIDoing:
            return howAmIDoing(context)
        case .shouldITrain:
            return shouldITrain(context)
        case .whyRecoveryLow:
            return whyRecoveryLow(context)
        case .howDidISleep:
            return howDidISleep(context)
        case .whatToday:
            return whatToday(context)
        }
    }

    // MARK: - Answers

    private static func howAmIDoing(_ context: CoachContext) -> CoachAnswer {
        var gaps: [String] = []
        var lines: [String] = []

        if let recovery, recovery.hasScore {
            lines.append("Recovery \(recovery.score) — \(recovery.category.rawValue.lowercased()).")
        } else {
            gaps.append("recovery data is still building")
        }

        if let sleep, sleep.hasScore, let score = sleep.score {
            lines.append("Sleep \(score) — slept \(Formatting.hoursMinutes(fromMinutes: sleep.night.breakdown.asleepMinutes)).")
        } else {
            gaps.append("no sleep analysis yet")
        }

        if let energy = context.energy {
            lines.append("Energy \(energy.score) — \(energy.band.rawValue.lowercased()) capacity.")
        }

        if lines.isEmpty {
            lines.append("Not enough data to summarize yet — keep wearing your watch.")
        }

        let headline = context.recovery?.hasScore == true
            ? "Recovery \(context.recovery!.score) (\(context.recovery!.category.rawValue))"
            : "Still building your picture"

        return CoachAnswer(
            question: .howAmIDoing,
            headline: headline,
            body: lines.joined(separator: " "),
            dataGaps: gaps
        )
    }

    private static func shouldITrain(_ context: CoachContext) -> CoachAnswer {
        guard let recovery = context.recovery, recovery.hasScore else {
            return CoachAnswer(
                question: .shouldITrain,
                headline: "Go by feel",
                body: "I don't have enough recovery data yet to guide training. An easy session is a safe default while your baseline builds.",
                dataGaps: ["recovery data is still building"]
            )
        }

        let acwrNote: String
        if let load = context.load, load.band == .high {
            acwrNote = " One note: your recent training load is already high for the month, so keep today comfortable."
        } else {
            acwrNote = ""
        }

        switch recovery.score {
        case 70...:
            return CoachAnswer(
                question: .shouldITrain,
                headline: "Yes — a harder session fits",
                body: "Recovery is \(recovery.score), which supports higher intensity today.\(acwrNote)",
                dataGaps: []
            )
        case 50...69:
            return CoachAnswer(
                question: .shouldITrain,
                headline: "Yes — moderate intensity",
                body: "Recovery is \(recovery.score). Steady training fits; maybe not a personal-best day.\(acwrNote)",
                dataGaps: []
            )
        default:
            return CoachAnswer(
                question: .shouldITrain,
                headline: "Take it easy",
                body: "Recovery is only \(recovery.score). Favor rest, a walk, or gentle movement and let your body catch up.\(acwrNote)",
                dataGaps: []
            )
        }
    }

    private static func whyRecoveryLow(_ context: CoachContext) -> CoachAnswer {
        guard let recovery = context.recovery, recovery.hasScore else {
            return CoachAnswer(
                question: .whyRecoveryLow,
                headline: "Not enough data yet",
                body: "I can't assess recovery until more health data builds up. Keep wearing your watch, including overnight.",
                dataGaps: ["recovery data is still building"]
            )
        }

        guard recovery.score < 50 else {
            return CoachAnswer(
                question: .whyRecoveryLow,
                headline: "Recovery isn't low",
                body: "Your recovery is \(recovery.score) — \(recovery.category.rawValue.lowercased()). \(recovery.explanation)",
                dataGaps: []
            )
        }

        let drivers = recovery.negativeFactors
            .prefix(2)
            .map(\.detail)
            .joined(separator: " ")

        let missing = recovery.missingData.map(\.displayName)
        let missingNote = missing.isEmpty
            ? ""
            : " Data still missing: \(missing.joined(separator: ", "))."

        return CoachAnswer(
            question: .whyRecoveryLow,
            headline: "Main factors",
            body: "\(drivers.isEmpty ? "No single strong factor — several small ones added up." : drivers)\(missingNote)",
            dataGaps: missing.map { "no \($0.lowercased()) data" }
        )
    }

    private static func howDidISleep(_ context: CoachContext) -> CoachAnswer {
        guard let sleep = context.sleep, sleep.hasScore, let score = sleep.score else {
            return CoachAnswer(
                question: .howDidISleep,
                headline: "No sleep analysis yet",
                body: "Wear your watch to bed so myhealth can analyze your sleep stages and timing.",
                dataGaps: ["no sleep data for last night"]
            )
        }

        let breakdown = sleep.night.breakdown
        var lines: [String] = [
            "You slept \(Formatting.hoursMinutes(fromMinutes: breakdown.asleepMinutes)) — \(sleep.rating?.rawValue.lowercased() ?? "scored") night (score \(score)).",
            "Deep \(Formatting.hoursMinutes(fromMinutes: breakdown.deepMinutes)), REM \(Formatting.hoursMinutes(fromMinutes: breakdown.remMinutes)).",
        ]
        if let deficit = sleep.deficitMinutes, deficit > 0 {
            lines.append("That's \(Formatting.hoursMinutes(fromMinutes: Double(deficit))) short of your target.")
        }

        return CoachAnswer(
            question: .howDidISleep,
            headline: "\(sleep.rating?.rawValue ?? "") night",
            body: lines.joined(separator: " "),
            dataGaps: []
        )
    }

    private static func whatToday(_ context: CoachContext) -> CoachAnswer {
        let recommendation = recommendation(for: context)
        var gaps: [String] = []
        if context.recovery?.hasScore != true { gaps.append("recovery") }
        if context.sleep?.hasScore != true { gaps.append("sleep") }

        return CoachAnswer(
            question: .whatToday,
            headline: recommendation.title,
            body: recommendation.detail,
            dataGaps: gaps.map { "still building: \($0)" }
        )
    }

    // MARK: - Helpers

    private static func ratingWord(_ sleep: SleepAnalysisResult?) -> String {
        guard let rating = sleep?.rating else { return "reasonable" }
        return rating.rawValue.lowercased()
    }
}
