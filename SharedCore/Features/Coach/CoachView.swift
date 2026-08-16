import SwiftUI

/// Coach tab: the five quick questions with deterministic, data-grounded
/// answers from `CoachEngine`.
struct CoachView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedQuestion: CoachQuestion?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: MyHealthTheme.Spacing.s) {
                    if let recommendation = model.repository.snapshot.recommendation {
                        RecommendationCard(recommendation: recommendation)
                    }
                    ForEach(CoachQuestion.allCases) { question in
                        Button {
                            Haptics.click(enabled: model.hapticsEnabled)
                            selectedQuestion = question
                        } label: {
                            Label(question.rawValue, systemImage: question.systemImage)
                                .font(MyHealthTheme.cardTitle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, MyHealthTheme.Spacing.xs)
                        }
                        .buttonBorderShape(.roundedRectangle(radius: MyHealthTheme.cardCornerRadius))
                    }
                    Text("Answers come from your local health data on this watch. No cloud, no AI processing of your data.")
                        .font(MyHealthTheme.detailText)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, MyHealthTheme.Spacing.xs)
            }
            .background(MyHealthTheme.appBackground)
            .navigationTitle("Coach")
            .navigationDestination(item: $selectedQuestion) { question in
                CoachAnswerView(question: question, context: coachContext)
            }
        }
    }

    private var coachContext: CoachContext {
        let snapshot = model.repository.snapshot
        return CoachContext(
            recovery: snapshot.recovery.value,
            sleep: snapshot.sleep.value,
            load: snapshot.load.value,
            stress: snapshot.stress.value,
            energy: snapshot.energy.value,
            recentWorkouts: snapshot.workouts.value ?? [],
            date: Date()
        )
    }
}

/// Renders one deterministic coach answer.
struct CoachAnswerView: View {
    let question: CoachQuestion
    let context: CoachContext

    var body: some View {
        ScrollView {
            let answer = CoachEngine.answer(question, context: context)
            VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.s) {
                MetricCard(title: answer.question.rawValue, systemImage: answer.question.systemImage) {
                    VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.s) {
                        Text(answer.headline)
                            .font(MyHealthTheme.bodyText.weight(.semibold))
                            .foregroundStyle(MyHealthTheme.accent)
                        Text(answer.body)
                            .font(MyHealthTheme.bodyText)
                        if !answer.dataGaps.isEmpty {
                            VStack(alignment: .leading, spacing: MyHealthTheme.Spacing.xs) {
                                ForEach(answer.dataGaps, id: \.self) { gap in
                                    Label(gap, systemImage: "info.circle")
                                        .font(MyHealthTheme.detailText)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Text("myhealth guidance is wellness-oriented and based on your available data. It is not medical advice.")
                    .font(MyHealthTheme.detailText)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, MyHealthTheme.Spacing.xs)
        }
        .background(MyHealthTheme.appBackground)
        .navigationTitle("Coach")
    }
}
