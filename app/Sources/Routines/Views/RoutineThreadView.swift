import RoutinesKit
import SwiftUI

/// The thread of one routine: its open questions first, each with a reply field or the permission buttons, then the answered questions.
struct RoutineThreadView: View {
    @Environment(AppModel.self) private var model
    var selection: RoutineSelection

    var body: some View {
        let thread = model.routineThread(selection)
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Tokens.Space.s12) {
                    if thread.open.isEmpty {
                        Text("No question waits for you.").font(Tokens.Font.small).foregroundStyle(Theme.faint)
                    }
                    ForEach(thread.open) { question in OpenQuestionCard(question: question).id(question.id) }
                    if selection == .noOwner, !thread.members.isEmpty {
                        section("NO ROUTINE HANDLES THESE")
                        ForEach(thread.members) { actionable in
                            Text("\(actionable.title) · \(actionable.kind) · \(actionable.state.rawValue)").font(Tokens.Font.small).foregroundStyle(Theme.muted)
                        }
                    }
                    if !thread.answered.isEmpty {
                        section("ANSWERED")
                        ForEach(thread.answered) { item in AnsweredRow(item: item) }
                    }
                }
                .padding(Tokens.Space.s12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .onChange(of: model.focusedQuestion, initial: true) {
                guard let id = model.focusedQuestion else { return }
                withAnimation(.snappy) { reader.scrollTo(id, anchor: .top) }
                model.focusedQuestion = nil
            }
        }
    }

    private func section(_ title: String) -> some View {
        Text(title).font(Tokens.Font.caption).tracking(0.6).foregroundStyle(Theme.faint).padding(.top, Tokens.Space.s8)
    }
}

private struct OpenQuestionCard: View {
    @Environment(AppModel.self) private var model
    var question: RoutineThread.Open
    @State private var reply = ""

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous)
        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
            Text(question.actionable.title).font(Tokens.Font.rowTitle).lineLimit(2)
            Text(question.question.question?.text ?? "").font(Tokens.Font.body).textSelection(.enabled)
            if question.question.question?.permission != nil {
                HStack(spacing: Tokens.Space.s8) {
                    Button("Allow once") { model.allow(question, always: false) }
                    Button("Always allow") { model.allow(question, always: true) }
                    Button("Deny", role: .destructive) { model.deny(question) }
                }
                .controlSize(.small)
            } else {
                HStack(spacing: Tokens.Space.s8) {
                    TextField("Your answer", text: $reply, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Tokens.Font.body)
                        .lineLimit(1...6)
                        .padding(Tokens.Padding.field)
                        .background(RoundedRectangle(cornerRadius: Tokens.Radius.field, style: .continuous).fill(.quinary))
                        .onSubmit(send)
                    Button("Send", action: send).controlSize(.small).disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if let error = model.answerErrors[question.id] {
                Text(error).font(Tokens.Font.small).foregroundStyle(Theme.danger)
            }
        }
        .padding(Tokens.Space.s12)
        .background(shape.fill(Theme.card))
        .overlay(shape.strokeBorder(Theme.cardBorder))
    }

    private func send() {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.answer(text, question: question)
        reply = ""
    }
}

private struct AnsweredRow: View {
    var item: RoutineThread.Answered

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text(item.actionable.title).font(Tokens.Font.rowTitle).lineLimit(1)
            Text(item.question.question?.text ?? "").font(Tokens.Font.small).foregroundStyle(Theme.muted).lineLimit(3)
            Text(answerText).font(Tokens.Font.small)
            Text(item.answer.at.formatted(.relative(presentation: .named))).font(Tokens.Font.meta).foregroundStyle(Theme.faint)
        }
        .padding(.vertical, Tokens.Space.s4)
    }

    private var answerText: String {
        if item.answer.action == .denied { return "You denied it." }
        return item.question.question?.permission != nil ? "You allowed it." : "You: \(item.answer.answer ?? "")"
    }
}
