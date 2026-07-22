import SwiftUI

/// 매월 반복 지출 규칙 관리 — 수정·켜기/끄기·삭제.
struct LedgerRecurringView: View {
    @State private var rules: [RecurringRule] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var editingRule: RecurringRule?
    @State private var deleteTarget: RecurringRule?

    private let ledgerService = LedgerService()

    var body: some View {
        Group {
            if rules.isEmpty && !isLoading {
                // 로딩 실패를 "규칙 없음"으로 오해하지 않도록 에러 상태를 우선 표시한다.
                if errorMessage != nil {
                    ContentUnavailableView {
                        Label("불러오지 못했어요", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("네트워크 상태를 확인한 뒤 다시 시도해 주세요")
                    } actions: {
                        Button("다시 시도") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView {
                        Label("반복 규칙이 없어요", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    } description: {
                        Text("내역 상세에서 '매월 반복으로 등록'을 눌러 만들 수 있어요")
                    }
                }
            } else {
                List {
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.red500)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(rules) { rule in
                        Button { editingRule = rule } label: { ruleRow(rule) }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions {
                                Button("삭제", role: .destructive) { deleteTarget = rule }
                                Button(rule.active ? "끄기" : "켜기") { toggle(rule) }
                                    .tint(rule.active ? Color.slate500 : Color.blue500)
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .glassScreenBackground()
        .navigationTitle("반복 관리")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading && rules.isEmpty { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editingRule) { rule in
            LedgerRecurringEditView(rule: rule) { await load() }
        }
        .alert(
            "반복 규칙 삭제",
            isPresented: .init(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )
        ) {
            Button("취소", role: .cancel) { deleteTarget = nil }
            Button("삭제", role: .destructive) {
                if let target = deleteTarget {
                    delete(target)
                    deleteTarget = nil
                }
            }
        } message: {
            if let target = deleteTarget {
                Text("'\(target.merchant ?? "반복 지출")' 규칙을 삭제할까요?")
            }
        }
    }

    private func ruleRow(_ rule: RecurringRule) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text("매월")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.slate500)
                Text("\(rule.dayOfMonth)일")
                    .font(.subheadline)
                    .fontWeight(.heavy)
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.merchant ?? "반복 지출")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(rule.active ? Color.slate900 : Color.slate400)
                    .lineLimit(1)
                if let note = rule.description, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(Color.slate400)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(LedgerFormat.amount(rule.amount, currency: rule.currency))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .monospacedDigit()
                if !rule.active {
                    Text("꺼짐")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.slate400)
                }
            }
        }
        .padding(12)
        .background(.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(.rect)
    }

    // MARK: - 네트워크

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            rules = try await ledgerService.fetchRecurringRules()
            errorMessage = nil
        } catch {
            errorMessage = "반복 규칙을 불러오지 못했습니다."
        }
    }

    private func toggle(_ rule: RecurringRule) {
        let request = RecurringUpdateRequest(
            dayOfMonth: rule.dayOfMonth, amount: rule.amount, currency: rule.currency,
            type: rule.type, merchant: rule.merchant, description: rule.description,
            active: !rule.active
        )
        Task {
            do {
                try await ledgerService.updateRecurringRule(id: rule.id, request)
                await load()
            } catch let error where LedgerService.isDuplicateError(error) {
                // 재활성화가 기존 활성 규칙과 겹치면 서버가 거절한다 — 켜지면 매달 2건씩 생기므로.
                errorMessage = "같은 조건의 반복 규칙이 이미 켜져 있어 켤 수 없어요."
            } catch {
                errorMessage = "변경하지 못했습니다."
            }
        }
    }

    private func delete(_ rule: RecurringRule) {
        Task {
            do {
                try await ledgerService.deleteRecurringRule(id: rule.id)
                rules.removeAll { $0.id == rule.id }
            } catch {
                errorMessage = "삭제하지 못했습니다."
            }
        }
    }
}

// MARK: - 반복 규칙 수정

struct LedgerRecurringEditView: View {
    let rule: RecurringRule
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var dayOfMonth: Int
    @State private var amountText: String
    @State private var currency: String
    @State private var merchant: String
    @State private var note: String
    @State private var active: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let ledgerService = LedgerService()

    init(rule: RecurringRule, onSaved: @escaping () async -> Void) {
        self.rule = rule
        self.onSaved = onSaved
        _dayOfMonth = State(initialValue: rule.dayOfMonth)
        _amountText = State(initialValue: NSDecimalNumber(decimal: rule.amount).stringValue)
        _currency = State(initialValue: rule.currency.uppercased())
        _merchant = State(initialValue: rule.merchant ?? "")
        _note = State(initialValue: rule.description ?? "")
        _active = State(initialValue: rule.active)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("사용", isOn: $active)
                    Picker("매월 반복일", selection: $dayOfMonth) {
                        ForEach(1...31, id: \.self) { Text("\($0)일").tag($0) }
                    }
                }
                Section("금액") {
                    HStack {
                        TextField("0", text: $amountText)
                            .keyboardType(LedgerFormat.integerAmount(currency) ? .numberPad : .decimalPad)
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                        Picker("", selection: $currency) {
                            ForEach(LedgerFormat.currencies, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    }
                }
                Section("내용") {
                    TextField("구매처", text: $merchant)
                    TextField("메모 (선택)", text: $note, axis: .vertical).lineLimit(1...3)
                }
                if let error = errorMessage {
                    Text(error).font(.caption).foregroundStyle(Color.red500)
                }
            }
            .navigationTitle("반복 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("저장") { save() }.disabled(parsedAmount == nil)
                    }
                }
            }
        }
    }

    private var parsedAmount: Decimal? {
        let cleaned = amountText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: cleaned), value > 0 else { return nil }
        // KRW·JPY 등 소수 없는 통화는 소수 금액을 거부한다.
        if LedgerFormat.integerAmount(currency), !value.isWholeNumber { return nil }
        return value
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespaces)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let request = RecurringUpdateRequest(
            dayOfMonth: dayOfMonth, amount: amount, currency: currency,
            type: rule.type, // 화면에서 종류는 다루지 않지만 기존 값은 보존
            merchant: trimmedMerchant.isEmpty ? nil : trimmedMerchant,
            description: trimmedNote.isEmpty ? nil : trimmedNote,
            active: active
        )
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await ledgerService.updateRecurringRule(id: rule.id, request)
                await onSaved()
                dismiss()
            } catch let error where LedgerService.isDuplicateError(error) {
                errorMessage = "같은 조건의 반복 규칙이 이미 있어요."
                isSaving = false
            } catch {
                errorMessage = "저장하지 못했습니다."
                isSaving = false
            }
        }
    }
}
