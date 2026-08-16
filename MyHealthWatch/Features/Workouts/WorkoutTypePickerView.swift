import SwiftUI

/// Workout type chooser — one tap, no typing.
struct WorkoutTypePickerView: View {
    let onSelect: (WorkoutKind) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(WorkoutKind.allCases) { kind in
                    Button {
                        onSelect(kind)
                    } label: {
                        Label(kind.displayName, systemImage: kind.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .navigationTitle("Choose")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
