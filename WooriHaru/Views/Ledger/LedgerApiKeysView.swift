import SwiftUI

/// 단축어용 API 키 관리 — 발급(원본 1회 노출)·폐기.
struct LedgerApiKeysView: View {
    @State private var keys: [LedgerApiKey] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var showingIssue = false
    @State private var newKeyName = ""
    @State private var issuedKey: IssuedLedgerApiKey?
    @State private var deleteTarget: LedgerApiKey?

    private let ledgerService = LedgerService()

    var body: some View {
        List {
            Section {
                if let error = errorMessage {
                    Text(error).font(.caption).foregroundStyle(Color.red500)
                }
                ForEach(keys) { key in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(key.name).font(.subheadline).fontWeight(.semibold)
                        Text("발급 \(displayDate(key.createdAt))")
                            .font(.caption2)
                            .foregroundStyle(Color.slate500)
                    }
                    .swipeActions {
                        Button("폐기", role: .destructive) { deleteTarget = key }
                    }
                }
                Button {
                    newKeyName = ""
                    showingIssue = true
                } label: {
                    Label("새 API 키 발급", systemImage: "plus")
                }
            } footer: {
                Text("아이폰 단축어가 카드 문자·카카오페이 내역을 보낼 때 쓰는 키입니다. 발급 직후 한 번만 전체 키가 보입니다.")
            }
        }
        .scrollContentBackground(.hidden)
        .glassScreenBackground()
        .navigationTitle("단축어 API 키")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading && keys.isEmpty { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
        .alert("API 키 발급", isPresented: $showingIssue) {
            TextField("이름 (예: 내 아이폰)", text: $newKeyName)
            Button("발급") { issue() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 키를 쓸 기기·용도를 구분할 이름을 지어주세요.")
        }
        .sheet(item: $issuedKey) { key in
            IssuedKeySheet(key: key)
        }
        .alert(
            "API 키 폐기",
            isPresented: .init(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )
        ) {
            Button("취소", role: .cancel) { deleteTarget = nil }
            Button("폐기", role: .destructive) {
                if let target = deleteTarget {
                    delete(target)
                    deleteTarget = nil
                }
            }
        } message: {
            if let target = deleteTarget {
                Text("'\(target.name)' 키를 폐기할까요? 이 키를 쓰는 단축어는 더 이상 동작하지 않습니다.")
            }
        }
    }

    private func displayDate(_ raw: String) -> String {
        guard let date = LedgerFormat.parseDateTime(raw) else { return raw }
        return LedgerFormat.full(date)
    }

    // MARK: - 네트워크

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            keys = try await ledgerService.fetchApiKeys()
            errorMessage = nil
        } catch {
            errorMessage = "API 키를 불러오지 못했습니다."
        }
    }

    private func issue() {
        let name = newKeyName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            do {
                issuedKey = try await ledgerService.issueApiKey(name: name)
                await load()
            } catch {
                errorMessage = "발급하지 못했습니다."
            }
        }
    }

    private func delete(_ key: LedgerApiKey) {
        Task {
            do {
                try await ledgerService.deleteApiKey(id: key.id)
                keys.removeAll { $0.id == key.id }
            } catch {
                errorMessage = "폐기하지 못했습니다."
            }
        }
    }
}

/// 발급 직후 원본 키를 1회 노출하는 시트.
private struct IssuedKeySheet: View {
    let key: IssuedLedgerApiKey
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("'\(key.name)' 키가 발급되었습니다")
                    .font(.headline)
                Text("이 키는 지금만 전체가 보입니다. 단축어에 붙여넣고 안전한 곳에 보관하세요.")
                    .font(.subheadline)
                    .foregroundStyle(Color.slate500)

                Text(key.key)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    UIPasteboard.general.string = key.key
                    copied = true
                } label: {
                    Label(copied ? "복사됨" : "키 복사", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .appGlassProminentButton()

                Spacer()
            }
            .padding(20)
            .glassScreenBackground()
            .navigationTitle("API 키")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }
}
