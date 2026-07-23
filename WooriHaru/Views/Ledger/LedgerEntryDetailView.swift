import SwiftUI

/// 내역 상세 — 수정·삭제·매월 반복 등록.
struct LedgerEntryDetailView: View {
    let entry: LedgerEntry
    let onChanged: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var isWorking = false
    @State private var successMessage: String?
    /// 실패는 아니지만 알려줄 안내 (예: 이미 등록된 반복) — 에러 빨간색 대신 중립 톤으로 표시.
    @State private var infoMessage: String?
    @State private var errorMessage: String?

    private let ledgerService = LedgerService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    amountCard
                    detailCard
                    recurringButton

                    if let success = successMessage {
                        Text(success)
                            .font(.caption)
                            .foregroundStyle(Color.green700)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let info = infoMessage {
                        Text(info)
                            .font(.caption)
                            .foregroundStyle(Color.slate500)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.red500)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .glassScreenBackground()
            .navigationTitle("상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("수정") { showingEdit = true }
                }
            }
            .safeAreaInset(edge: .bottom) { deleteButton }
            .sheet(isPresented: $showingEdit) {
                LedgerEntryFormView(mode: .edit(entry)) {
                    await onChanged()
                    dismiss()
                }
            }
            .alert("이 내역을 삭제할까요?", isPresented: $showingDeleteConfirm) {
                Button("삭제", role: .destructive) { delete() }
                Button("취소", role: .cancel) {}
            }
        }
    }

    // MARK: - 카드

    private var amountCard: some View {
        GlassCard(alignment: .center) {
            VStack(spacing: 10) {
                Text(LedgerFormat.amount(entry.amount, currency: entry.currency))
                    .font(.system(size: 32, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(LedgerFormat.isForeign(entry.currency) ? Color.blue600 : Color.slate900)
                LedgerSourceBadge(source: entry.source)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private var detailCard: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                detailRow("구매처", entry.merchant ?? "—")
                Divider().padding(.leading, 16)
                detailRow("일시", LedgerFormat.full(entry.date))
                // 환율 기록은 메모에서 분리해 전용 줄로 보여준다.
                if let fxNote = entry.fxNote {
                    Divider().padding(.leading, 16)
                    detailRow("환율", fxNote.replacingOccurrences(of: "환율 ", with: ""))
                }
                if let note = entry.descriptionWithoutFxNote {
                    Divider().padding(.leading, 16)
                    detailRow("메모", note)
                }
            }
        }
    }

    private func detailRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(key)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.slate500)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color.slate900)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }

    private var recurringButton: some View {
        Button {
            registerRecurring()
        } label: {
            HStack {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                Text("매월 반복으로 등록")
                Spacer()
                if isWorking { ProgressView() }
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
        }
        .appGlassButton()
        .disabled(isWorking)
    }

    private var deleteButton: some View {
        Button {
            showingDeleteConfirm = true
        } label: {
            Text("삭제")
                .font(.headline)
                .foregroundStyle(Color.red500)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .appGlassButton()
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - 액션

    private func registerRecurring() {
        isWorking = true
        errorMessage = nil
        successMessage = nil
        infoMessage = nil
        let day = Calendar.current.component(.day, from: entry.date)
        Task {
            do {
                try await ledgerService.createRecurringRule(entryId: entry.id, dayOfMonth: day)
                successMessage = "매월 \(day)일 반복으로 등록했습니다."
            } catch let error where LedgerService.isDuplicateError(error) {
                infoMessage = "이미 매월 \(day)일 반복으로 등록되어 있어요."
            } catch {
                errorMessage = "반복 등록에 실패했습니다."
            }
            isWorking = false
        }
    }

    private func delete() {
        Task {
            do {
                try await ledgerService.deleteEntry(id: entry.id)
                await onChanged()
                dismiss()
            } catch {
                errorMessage = "삭제하지 못했습니다."
            }
        }
    }
}
