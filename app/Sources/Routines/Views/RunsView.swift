import RoutinesKit
import SwiftUI

/// The runs and actions, newest first. Clicking one opens its log in a dialog.
struct RunsView: View {
    @Environment(AppModel.self) private var model
    var pluginId: String?
    @State private var selected: RunRecord.ID?

    var body: some View {
        let records = pluginId.map { model.host.runs.records(of: $0) } ?? model.host.runs.records
        VStack(alignment: .leading, spacing: 0) {
            if pluginId == nil {
                PageHeader(trail: ["Routines", "Runs"], title: "Runs", subtitle: "Each run and each card action, with its log.") { EmptyView() }
                    .padding(.bottom, 12)
            }
            Table(records, selection: $selected) {
                TableColumn("") { record in OutcomeIcon(outcome: record.outcome) }.width(18)
                TableColumn("Routine") { record in Text(model.host.plugin(record.pluginId)?.manifest.name ?? record.pluginId) }
                TableColumn("Trigger") { record in Text(trigger(record)).lineLimit(1) }
                TableColumn("Started") { record in Text(record.startedAt.formatted(date: .abbreviated, time: .shortened)) }
                TableColumn("Time") { record in Text(duration(record)).monospacedDigit() }.width(60)
                TableColumn("Result") { record in Text(record.message ?? "").lineLimit(1).foregroundStyle(Theme.muted) }
            }
            .padding(.horizontal, Tokens.Size.pageGutter)
            .padding(.bottom, 20)
        }
        // Closing the dialog clears the selection, so a click on the same row opens it again.
        .sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            if let record = records.first(where: { $0.id == selected }) {
                RunLogDialog(record: record, routine: model.host.plugin(record.pluginId)?.manifest.name ?? record.pluginId)
            }
        }
    }
}

private func trigger(_ record: RunRecord) -> String {
    record.kind == .action ? "action \(record.trigger)" : record.trigger
}

private func duration(_ record: RunRecord) -> String {
    let seconds = Int((record.endedAt ?? Date()).timeIntervalSince(record.startedAt))
    return seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m \(seconds % 60)s"
}

private struct RunLogDialog: View {
    @Environment(\.dismiss) private var dismiss
    var record: RunRecord
    var routine: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        OutcomeIcon(outcome: record.outcome)
                        Text(routine).font(Tokens.Font.title)
                    }
                    Text("\(trigger(record)) · \(record.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(duration(record))")
                        .font(Tokens.Font.meta)
                        .foregroundStyle(Theme.faint)
                    if let message = record.message, !message.isEmpty {
                        Text(message).font(Tokens.Font.body).foregroundStyle(Theme.muted).textSelection(.enabled)
                    }
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            LogView(record: record)
                .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 760, height: 560)
    }
}

private struct OutcomeIcon: View {
    var outcome: RunRecord.Outcome

    var body: some View {
        switch outcome {
        case .running: ProgressView().controlSize(.mini)
        case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.danger)
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(Theme.faint)
        }
    }
}

/// One row per log line, so a long log builds only the lines on screen.
private struct LogView: View {
    var record: RunRecord
    @State private var lines: [String] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(lines.indices, id: \.self) { index in
                    Text(lines[index]).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(Tokens.Font.mono.monospaced())
            .padding(12)
        }
        .background(Theme.column, in: RoundedRectangle(cornerRadius: Tokens.Radius.panel))
        // A running call keeps writing, so the view reads its file again each second until it ends.
        // The outcome is part of the key, so the loop ends when the run ends.
        .task(id: "\(record.id.uuidString)/\(record.outcome.rawValue)") {
            while !Task.isCancelled {
                lines = RunLog.read(record.logFile).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                guard record.outcome == .running else { return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
