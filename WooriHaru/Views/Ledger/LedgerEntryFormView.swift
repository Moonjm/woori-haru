import SwiftUI

/// 지출 내역 등록·수정 — 큰 금액 + 카드형 필드. (수입/분류는 다루지 않음)
struct LedgerEntryFormView: View {
    enum Mode {
        case create
        case edit(LedgerEntry)
    }

    let mode: Mode
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var entryAt = Date.now
    @State private var amountText = ""
    @State private var currency = "KRW"
    @State private var merchant = ""
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var amountFocused: Bool

    private let ledgerService = LedgerService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    amountCard
                    fieldCard
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.red500)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .glassScreenBackground()
            .navigationTitle(isEditing ? "내역 수정" : "내역 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { saveBar }
            .onAppear {
                prefill()
                if case .create = mode { amountFocused = true }
            }
        }
    }

    // MARK: - 금액

    private var amountCard: some View {
        GlassCard {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(LedgerFormat.symbol(for: currency))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.slate500)
                TextField("0", text: $amountText)
                    .keyboardType(LedgerFormat.integerAmount(currency) ? .numberPad : .decimalPad)
                    .font(.system(size: 38, weight: .heavy))
                    .monospacedDigit()
                    .focused($amountFocused)
                Spacer(minLength: 8)
                Menu {
                    Picker("통화", selection: $currency) {
                        ForEach(LedgerFormat.currencies, id: \.self) { Text($0).tag($0) }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(currency).font(.caption).fontWeight(.bold)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Color.blue600)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.blue600.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    // MARK: - 필드

    private var fieldCard: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                fieldRow("구매처") {
                    TextField("가게 이름", text: $merchant)
                }
                Divider().padding(.leading, 16)
                fieldRow("메모") {
                    TextField("선택 입력", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
                Divider().padding(.leading, 16)
                fieldRow("날짜") {
                    // 내역 화면이 미래 달 이동을 막으므로, 보이지 않게 될 미래 날짜 저장도 막는다.
                    DatePicker("", selection: $entryAt, in: ...Date.now, displayedComponents: [.date])
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "ko_KR"))
                }
            }
        }
    }

    private func fieldRow(_ key: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.slate500)
                .frame(width: 52, alignment: .leading)
            content()
                .font(.subheadline)
        }
        .padding(16)
    }

    // MARK: - 저장

    private var saveBar: some View {
        Button {
            save()
        } label: {
            Group {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text("저장").font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .appGlassProminentButton()
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.5)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - 로직

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var parsedAmount: Decimal? {
        let cleaned = amountText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: cleaned), value > 0 else { return nil }
        // KRW·JPY 등 소수 없는 통화는 소수 금액을 거부한다 — 표시 시 반올림돼 다른 값으로 보이는 것을 막는다.
        if LedgerFormat.integerAmount(currency), !value.isWholeNumber { return nil }
        return value
    }

    private var canSave: Bool { parsedAmount != nil && !isSaving }

    /// 화면에서는 날짜만 고른다 — 등록은 자정, 수정은 기존 시각을 보존한 채 날짜만 바꾼다.
    private func resolvedEntryAt() -> Date {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: entryAt)
        if case let .edit(entry) = mode {
            let time = calendar.dateComponents([.hour, .minute, .second], from: entry.date)
            return calendar.date(byAdding: time, to: day) ?? day
        }
        return day
    }

    private func prefill() {
        guard case let .edit(entry) = mode else { return }
        entryAt = entry.date
        amountText = NSDecimalNumber(decimal: entry.amount).stringValue
        currency = entry.currency.uppercased()
        merchant = entry.merchant ?? ""
        // 환율 메모는 편집 대상이 아니다 — 순수 메모만 보여주고, 저장 시 조건부로 다시 붙인다.
        note = entry.descriptionWithoutFxNote ?? ""
    }

    /// 수정 시 원본의 환율 메모 처리 — 금액·통화가 그대로면 보존하고,
    /// 바뀌었으면 환산액이 더는 맞지 않으므로 버린다.
    private func resolvedDescription(note: String, amount: Decimal) -> String? {
        var parts: [String] = note.isEmpty ? [] : [note]
        if case let .edit(entry) = mode,
           let fxNote = entry.fxNote,
           amount == entry.amount,
           currency == entry.currency.uppercased() {
            parts.append(fxNote)
        }
        let joined = parts.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespaces)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let request = LedgerEntryRequest(
            entryAt: LedgerFormat.formatDateTime(resolvedEntryAt()),
            amount: amount,
            currency: currency,
            type: {
                // 화면에서는 지출만 다루지만, 수정 시 기존 종류는 보존한다.
                if case let .edit(entry) = mode { return entry.type }
                return .expense
            }(),
            merchant: trimmedMerchant.isEmpty ? nil : trimmedMerchant,
            description: resolvedDescription(note: trimmedNote, amount: amount)
        )
        isSaving = true
        errorMessage = nil
        Task {
            do {
                switch mode {
                case .create:
                    try await ledgerService.createEntry(request)
                case let .edit(entry):
                    try await ledgerService.updateEntry(id: entry.id, request)
                }
                await onSaved()
                dismiss()
            } catch {
                errorMessage = "저장하지 못했습니다."
                isSaving = false
            }
        }
    }
}
