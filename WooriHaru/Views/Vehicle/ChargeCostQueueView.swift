import SwiftUI

/// 금액이 빈 충전을 연달아 채우는 화면. 채워 넣는 일 하나만 한다 —
/// 합계도 월 이동도 상세도 없다.
struct ChargeCostQueueView: View {
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
            .vehicleDarkTheme()
            .navigationTitle("금액 등록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // 저장이 도는 중에는 닫지 않는다 — 먼저 닫으면 부모의 새로고침(GET)이
                    // 저장(PUT)보다 먼저 끝나 방금 넣은 금액이 목록·배지에서 빠진 채로 남는다.
                    Button("닫기") { close() }
                        .disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.totalCount > 0 {
                        Text("\(min(viewModel.index + 1, viewModel.items.count)) / \(viewModel.items.count)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(VehicleTheme.textSecondary)
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
                    .foregroundStyle(VehicleTheme.textSecondary)
            }

            HStack(spacing: 8) {
                Text("₩")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(VehicleTheme.textSecondary)
                TextField("금액", text: $text)
                    .keyboardType(.numberPad)
                    .font(.system(size: 28, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(VehicleTheme.textPrimary)
                    .focused($focused)
            }
            .padding(14)
            .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 14))

            if let suggested = viewModel.suggestedCost {
                Text("직전 단가 기준 약 \(LedgerFormat.amount(suggested, currency: "KRW"))")
                    .font(.caption)
                    .foregroundStyle(VehicleTheme.textSecondary)
            }
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(VehicleTheme.danger)
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

    /// 문구는 **남은 건수로 고른다.** 저장했는지로 고르면, 한 건도 저장하지 않고 전부 건너뛴 사람에게
    /// 「채울 게 없어요」라고 말하게 된다 — 건너뛰기는 서버에 아무것도 보내지 않으므로 그 건들은
    /// 그대로 남아 있고 다음에 열면 다시 나온다. 한 번에 최대 50건만 받아 오는 것도 같은 이유로
    /// 「다 채웠다」를 함부로 말할 수 없게 만든다.
    private var finishedState: some View {
        let remaining = max(0, viewModel.totalCount - viewModel.savedCount)
        let title: String
        let description: String
        if remaining > 0 {
            title = viewModel.savedCount > 0 ? "여기까지 채웠어요" : "아직 그대로예요"
            description = viewModel.savedCount > 0
                ? "\(viewModel.savedCount)건을 등록했고 \(remaining)건 남았어요 (다시 열면 이어서 채워요)"
                : "\(remaining)건이 아직 비어 있어요 (건너뛴 건은 다시 나와요)"
        } else if viewModel.savedCount > 0 {
            title = "다 채웠어요"
            description = "\(viewModel.savedCount)건을 등록했어요"
        } else {
            title = "채울 게 없어요"
            description = "금액이 빈 충전이 없어요"
        }
        return ContentUnavailableView {
            Label(title, systemImage: remaining > 0 ? "tray" : "checkmark.circle")
        } description: {
            Text(description)
        } actions: {
            Button("닫기") { close() }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSaving)
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

    /// **바로 닫는다.** 부모 새로고침을 여기서 기다리면 느린 연결에서 닫기를 눌러도
    /// 요청 두 번이 끝날 때까지 화면이 멎어 보인다 — 갱신은 부모가 `onDismiss`에서 맡는다.
    private func close() {
        dismiss()
    }
}
