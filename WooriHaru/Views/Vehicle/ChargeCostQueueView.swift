import SwiftUI

/// 금액이 빈 충전을 연달아 채우는 화면. 채워 넣는 일 하나만 한다 —
/// 합계도 월 이동도 상세도 없다.
struct ChargeCostQueueView: View {
    /// 닫을 때 요약 탭이 배지와 목록을 다시 받게 한다.
    let onClose: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ChargeCostQueueViewModel()
    @State private var text = ""
    @FocusState private var focused: Bool

    private var parsedCost: Decimal? { ChargeFormat.parseCost(text) }

    var body: some View {
        NavigationStack {
            Group {
                if let item = viewModel.current {
                    form(item)
                } else if viewModel.isFinished {
                    finishedState
                } else if let error = viewModel.errorMessage, !viewModel.isLoading {
                    // 못 받은 것을 「채울 게 없어요」로 그리지 않는다 — 재시도가 있는 상태다.
                    errorState(error)
                } else {
                    // 아직 못 받았다. 빈 큐를 「다 채웠다」로 보여주지 않는다 — 뷰모델의 hasLoaded가 그 구분이다.
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassScreenBackground()
            .navigationTitle("금액 등록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { close() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.totalCount > 0 {
                        Text("\(min(viewModel.index + 1, viewModel.items.count)) / \(viewModel.items.count)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Color.slate500)
                    }
                }
            }
            .task {
                await viewModel.load()
                fillSuggestion()
            }
        }
    }

    private func form(_ item: ChargeItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(LedgerFormat.dayWithYear(item.startDate))
                    .font(.title3)
                    .fontWeight(.heavy)
                Text([item.locationName ?? "장소 없음",
                      ChargeFormat.energy(item.energyUsedKwh),
                      ChargeFormat.duration(item.durationMin),
                      ChargeFormat.batteryRange(item.startBatteryLevel, item.endBatteryLevel)]
                        .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
            }

            HStack(spacing: 8) {
                Text("₩")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.slate500)
                TextField("금액", text: $text)
                    .keyboardType(.numberPad)
                    .font(.system(size: 28, weight: .bold))
                    .monospacedDigit()
                    .focused($focused)
            }
            .padding(14)
            .background(Color.slate100, in: RoundedRectangle(cornerRadius: 14))

            if let suggested = viewModel.suggestedCost {
                Text("직전 단가 기준 약 \(LedgerFormat.amount(suggested, currency: "KRW"))")
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
            }
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.red500)
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button("건너뛰기") {
                    viewModel.skip()
                    fillSuggestion()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isSaving)
                Button("저장 · 다음") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(parsedCost == nil || viewModel.isSaving)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .onAppear { focused = true }
    }

    /// 한 번에 최대 50건만 받아 오므로, 다 돌아도 서버에는 더 남아 있을 수 있다 —
    /// `totalCount`(서버가 센 전체)와 `savedCount`를 견줘 「다 채웠다」를 함부로 말하지 않는다.
    private var finishedState: some View {
        let remaining = viewModel.totalCount - viewModel.savedCount
        let title: String
        let description: String
        if viewModel.savedCount > 0 && remaining > 0 {
            title = "여기까지 채웠어요"
            description = "\(remaining)건 남았어요 (다시 열면 이어서 채워요)"
        } else if viewModel.savedCount > 0 {
            title = "다 채웠어요"
            description = "\(viewModel.savedCount)건을 등록했어요"
        } else {
            title = "채울 게 없어요"
            description = "금액이 빈 충전이 없어요"
        }
        return ContentUnavailableView {
            Label(title, systemImage: "checkmark.circle")
        } description: {
            Text(description)
        } actions: {
            Button("닫기") { close() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("불러오지 못했어요", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("다시 시도") { Task { await viewModel.load() } }
                .buttonStyle(.borderedProminent)
        }
    }

    private func save() {
        guard let cost = parsedCost else { return }
        Task {
            await viewModel.save(cost: cost)
            // 실패하면 같은 건이 남아 있으므로 입력도 그대로 둔다.
            if viewModel.errorMessage == nil { fillSuggestion() }
        }
    }

    /// 다음 건으로 넘어갈 때 제안값을 채워 둔다. 근거가 없으면 비운다.
    private func fillSuggestion() {
        text = viewModel.suggestedCost.map(ChargeFormat.plainNumber) ?? ""
        focused = viewModel.current != nil
    }

    private func close() {
        Task {
            await onClose()
            dismiss()
        }
    }
}
