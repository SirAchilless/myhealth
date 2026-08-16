import SwiftUI

/// Load detail: today's load, week total, ACWR band, recent workouts.
struct LoadDetailView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: MyHealthTheme.Spacing.s) {
                switch model.repository.snapshot.load {
                case .available(let result):
                    headerSection(result)
                    ratioSection(result)
                    recentWorkouts
                    trendSection
                case .loading:
                    LoadingStateView(label: "Calculating load…")
                case .unavailable(let reason):
                    UnavailableView(reason: reason)
                }
            }
            .padding(.horizontal, MyHealthTheme.Spacing.xs)
        }
        .background(MyHealthTheme.appBackground)
        .navigationTitle("Load")
    }

    private func headerSection(_ result: LoadResult) -> some View {
        MetricCard(title: "Today", systemImage: "flame.fill") {
            VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
                MetricHeadline(
                    value: result.todayLoad.map { Formatting.oneDecimal($0) } ?? "0",
                    label: result.band.rawValue,
                    color: MyHealthTheme.color(for: result.band)
                )
                ConfidenceBadge(level: result.confidence)
                Text("Week total \(Int(result.weekRawPoints)) points.")
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)
                Text(result.explanation)
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func ratioSection(_ result: LoadResult) -> some View {
        MetricCard(title: "Week vs month", systemImage: "scalemass") {
            if let ratio = result.acuteToChronicRatio {
                VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
                    HStack {
                        Text(String(format: "%.2f", ratio))
                            .font(MyHealthTheme.metricNumber)
                            .foregroundStyle(MyHealthTheme.color(for: result.band))
                        Spacer()
                        HealthStatusBadge(text: result.band.rawValue, color: MyHealthTheme.color(for: result.band))
                    }
                    Text("Above 1.3 means your week is much harder than your month; below 0.8 means you're backing off.")
                        .font(MyHealthTheme.detailText)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("A full month of workout history unlocks this comparison.")
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var recentWorkouts: some View {
        MetricCard(title: "Recent", systemImage: "clock") {
            if case .available(let workouts) = model.repository.snapshot.workouts {
                if workouts.isEmpty {
                    Text("No workouts recorded yet.")
                        .font(MyHealthTheme.detailText)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.m) {
                        ForEach(workouts.prefix(4)) { workout in
                            workoutRow(workout)
                        }
                    }
                }
            }
        }
    }

    private func workoutRow(_ workout: WorkoutSummary) -> some View {
        VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
            HStack {
                Label(workout.kind.displayName, systemImage: workout.kind.systemImage)
                    .font(MyHealthTheme.cardTitle)
                Spacer()
                Text(Formatting.oneDecimal(workout.loadPoints))
                    .font(MyHealthTheme.detailText.weight(.semibold))
                    .foregroundStyle(MyHealthTheme.accent)
            }
            Text(subtitle(workout))
                .font(MyHealthTheme.detailText)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ workout: WorkoutSummary) -> String {
        var parts = [dateText(workout.start), Formatting.duration(fromSeconds: workout.durationMinutes * 60)]
        if let hr = workout.averageHeartRate {
            parts.append("\(Int(hr)) bpm avg")
        }
        if let km = workout.distanceKilometers, km > 0.05 {
            parts.append(String(format: "%.1f km", km))
        }
        return parts.joined(separator: " · ")
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }

    private var trendSection: some View {
        MetricCard(title: "Load trend", systemImage: "chart.line.uptrend.xyaxis") {
            if case .available(let heart) = model.repository.snapshot.heart {
                TrendChart(points: heart.loadTrend, color: MyHealthTheme.statusCaution, unitLabel: "points")
            } else {
                Text("Trend appears as workouts accumulate.")
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
