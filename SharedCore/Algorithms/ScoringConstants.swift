/// Every scoring constant in myhealth lives here — no magic numbers in engines
/// or views. Full documentation of each value: docs/ALGORITHMS.md.
enum ScoringConstants {
    enum Baseline {
        /// Minimum samples for a baseline to be considered usable at all.
        static let minimumSamples = 5
        /// Samples at which a baseline is considered well-populated.
        static let preferredSamples = 10
        /// Default rolling window for personal baselines.
        static let preferredWindow: BaselineWindow = .fourteenDays
    }

    enum Recovery {
        // Factor weights (sum = 1.0). Missing factors are renormalized.
        static let weightHeartRateVariability: Double = 0.35
        static let weightRestingHeartRate: Double = 0.20
        static let weightSleepDuration: Double = 0.25
        static let weightSleepTiming: Double = 0.10
        static let weightRecentLoad: Double = 0.10

        /// Score midpoint — a completely neutral day scores 50.
        static let midpoint: Double = 50
        /// Robust z-scores are clamped to ±this before mapping to contributions.
        static let zClamp: Double = 2.0
        /// A factor must move the score by more than this to be "notable".
        static let notableContribution: Double = 0.03
        /// Below this fraction of total weight available, no score is produced.
        static let minimumAvailableWeight: Double = 0.40
        /// Sleep fulfillment divergence (fraction of need) mapped to ±1.
        static let sleepFulfillmentScale: Double = 0.25
        /// Sleep midpoint deviation (minutes) mapped to a full penalty.
        static let sleepTimingScaleMinutes: Double = 90
        /// ACWR above this starts penalizing recovery proportionally.
        static let loadPenaltyRatio: Double = 1.3
        /// ACWR below this earns a (capped) recovery bonus.
        static let loadBonusRatio: Double = 0.8
        static let loadBonusCap: Double = 0.3

        // Category thresholds (0–29 Very Low, 30–49 Low, 50–69 Moderate,
        // 70–84 Good, 85–100 Excellent).
        static let veryLowUpperBound = 30
        static let lowUpperBound = 50
        static let moderateUpperBound = 70
        static let goodUpperBound = 85
    }

    enum Sleep {
        // Component weights (sum = 1.0 when all present).
        static let weightNeedFulfillment: Double = 0.45
        static let weightEfficiency: Double = 0.30
        static let weightConsistency: Double = 0.15
        static let weightDisturbances: Double = 0.10

        /// Default nightly need before a personal baseline exists (8 h).
        static let defaultNeedMinutes: Double = 480
        /// Nights of history used to derive a personal sleep need.
        static let needBaselineNights = 14
        /// Efficiency at or above this earns the full component (95%).
        static let fullEfficiency: Double = 0.95
        /// Awake-as-share-of-asleep at which the disturbance component is zero.
        static let fullDisturbanceShare: Double = 0.30
        /// Minimum asleep minutes for a night to be scoreable at all.
        static let minimumScoreableAsleepMinutes: Double = 60

        static let poorUpperBound = 50
        static let fairUpperBound = 70
        static let goodUpperBound = 85
    }

    enum Load {
        /// Banister TRIMP: minutes × coefficient × e^(exponent × HR-reserve).
        static let trimpCoefficient: Double = 0.64
        static let trimpExponent: Double = 1.92
        /// Raw load points per display unit on the 0–10 scale (100 raw
        /// points ≈ a maximal day).
        static let displayScaleDivisor: Double = 10.0
        static let displayScaleMaximum: Double = 10.0

        // Acute:chronic workload ratio bands.
        static let recoveringUpperRatio: Double = 0.8
        static let productiveUpperRatio: Double = 1.3
        static let acuteWindowDays = 7
        static let chronicWindowDays = 28
        /// Days of chronic history required before an ACWR is reported.
        static let minimumChronicDays = 14

        // Fallback load estimates when heart rate is unavailable.
        static let energyFallbackPointsPerKcal: Double = 0.025
        static let durationFallbackPointsPerMinute: Double = 0.05

        // Tanaka maximum-heart-rate estimate: 208 − 0.7 × age.
        static let maxHeartRateIntercept: Double = 208
        static let maxHeartRateSlope: Double = 0.7
        static let defaultAgeYears: Double = 35
    }

    enum Stress {
        static let windowMinutes: Double = 10
        /// Heart-rate elevation (bpm above resting baseline) that saturates pressure.
        static let heartElevationScaleBPM: Double = 40
        static let weightHeartPressure: Double = 0.65
        static let weightHRVSuppression: Double = 0.35
        /// Stress estimated during sleep windows is damped (sleep raises HRV noise).
        static let sleepWindowDampening: Double = 0.6

        static let moderateLowerBound: Double = 33
        static let elevatedLowerBound: Double = 66
    }

    enum Energy {
        static let weightRecovery: Double = 0.5
        static let weightSleep: Double = 0.3
        static let weightLoadFreshness: Double = 0.2

        static let lowUpperBound = 30
        static let moderateUpperBound = 70
    }
}
