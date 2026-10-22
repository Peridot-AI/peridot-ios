import SwiftUI

struct ModelPickerView: View {
    @Environment(ChatStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.models.isEmpty {
                        Text("models_unavailable").foregroundStyle(Theme.muted)
                    }
                    ForEach(store.models) { model in
                        Button {
                            store.select(model)
                            dismiss()
                        } label: {
                            row(model)
                        }
                        .disabled(model.isLocked)
                    }
                } header: {
                    Text("model")
                }
                .listRowBackground(Theme.surface)

                Section {
                    Picker(selection: Binding(get: { store.effort }, set: { store.select($0) })) {
                        Text("effort_low").tag(Effort.low)
                        Text("effort_medium").tag(Effort.medium)
                        Text("effort_high").tag(Effort.high)
                    } label: {
                        Text("effort")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("effort")
                } footer: {
                    Text("effort_hint")
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(Text("choose_model"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ model: Model) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(verbatim: model.name)
                        .foregroundStyle(model.isLocked ? Theme.muted : Theme.text)
                        .lineLimit(1)
                    if let badge = model.badge, !badge.isEmpty {
                        Text(verbatim: badge)
                            .font(.caption2)
                            .foregroundStyle(Theme.mint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                if model.isLocked {
                    Text("not_in_plan").font(.footnote).foregroundStyle(Theme.muted)
                } else if let desc = model.desc, !desc.isEmpty {
                    Text(verbatim: desc).font(.footnote).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            if model.isLocked {
                Image(systemName: "lock.fill").foregroundStyle(Theme.muted).accessibilityLabel(Text("not_in_plan"))
            } else if model.id == store.model {
                Image(systemName: "checkmark").foregroundStyle(Theme.mint)
            }
        }
    }
}
