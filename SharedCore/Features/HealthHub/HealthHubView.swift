import SwiftUI

/// Health hub: entry points to the metric detail screens.
struct HealthHubView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        NavigationStack(path: $router.healthPath) {
            List {
                Section {
                    NavigationLink(value: AppRoute.recovery) {
                        Label("Recovery", systemImage: "heart.text.square")
                    }
                    NavigationLink(value: AppRoute.sleep) {
                        Label("Sleep", systemImage: "bed.double.fill")
                    }
                    NavigationLink(value: AppRoute.load) {
                        Label("Load", systemImage: "flame.fill")
                    }
                }
                Section {
                    NavigationLink(value: AppRoute.stress) {
                        Label("Stress", systemImage: "waveform.path.ecg")
                    }
                    NavigationLink(value: AppRoute.energy) {
                        Label("Energy", systemImage: "bolt.heart.fill")
                    }
                    NavigationLink(value: AppRoute.heart) {
                        Label("Heart", systemImage: "heart.fill")
                    }
                }
            }
            .navigationTitle("Health")
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .recovery: RecoveryDetailView()
                case .sleep: SleepDetailView()
                case .load: LoadDetailView()
                case .stress: StressDetailView()
                case .energy: EnergyDetailView()
                case .heart: HeartView()
                }
            }
        }
    }
}
