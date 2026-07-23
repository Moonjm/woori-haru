import SwiftUI

/// 파싱에 실패한 카드 문자·카카오페이 원문 목록 — 재시도(파서 수정 후 복구)·삭제.
struct LedgerInboundFailuresView: View {
    @State private var failures: [LedgerInboundFailure] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// 재시도 중인 건의 id — 해당 행에만 스피너를 보여준다.
    @State private var retryingId: Int?
    /// 재시도했지만 여전히 실패한 건의 안내 문구 (id별).
    @State private var retryFailedIds: Set<Int> = []
    @State private var deleteTarget: LedgerInboundFailure?
    /// 진행 중 로드의 세대 번호 — 재시도·삭제 뒤에 도착한 낡은 목록 응답이 변경을 되돌리지 못하게 한다.
    @State private var loadGeneration = 0

    private let ledgerService = LedgerService()

    var body: some View {
        Group {
            if failures.isEmpty && !isLoading {
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
                        Label("실패한 문자가 없어요", systemImage: "checkmark.message")
                    } description: {
                        Text("인식하지 못한 카드 문자가 생기면 여기에 보관돼요")
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
                    ForEach(failures) { failure in
                        failureRow(failure)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions {
                                Button("삭제", role: .destructive) { deleteTarget = failure }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .glassScreenBackground()
        .navigationTitle("실패한 문자")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading && failures.isEmpty { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
        .alert(
            "실패한 문자 삭제",
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
            Text("보관된 원문이 삭제되며 되돌릴 수 없어요.")
        }
    }

    // MARK: - 행

    private func failureRow(_ failure: LedgerInboundFailure) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(failure.rawText)
                .font(.footnote)
                .foregroundStyle(Color.slate900)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Text(LedgerFormat.dayWithYear(failure.date))
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)
                Spacer()
                if retryingId == failure.id {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        retry(failure)
                    } label: {
                        Label("다시 시도", systemImage: "arrow.clockwise")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.blue600)
                    }
                    .buttonStyle(.plain)
                }
            }

            if retryFailedIds.contains(failure.id) {
                Text("여전히 인식할 수 없는 형식이에요")
                    .font(.caption2)
                    .foregroundStyle(Color.slate500)
            }
        }
        .padding(12)
        .background(.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 네트워크

    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer {
            if generation == loadGeneration { isLoading = false }
        }
        do {
            let list = try await ledgerService.fetchInboundFailures()
            guard generation == loadGeneration else { return } // 밀려난 응답은 폐기
            failures = list
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = "실패한 문자를 불러오지 못했습니다."
        }
    }

    private func retry(_ failure: LedgerInboundFailure) {
        retryingId = failure.id
        retryFailedIds.remove(failure.id)
        errorMessage = nil
        // 진행 중이던 로드 응답이 재시도 결과를 되돌리지 못하게 무효화한다.
        loadGeneration += 1
        isLoading = false
        Task {
            do {
                try await ledgerService.retryInbound(id: failure.id)
                failures.removeAll { $0.id == failure.id } // 성공 → 내역으로 등록됨
            } catch let error where LedgerService.isParseFailedError(error) {
                retryFailedIds.insert(failure.id) // 파서가 아직 이 형식을 지원하지 않음
            } catch {
                errorMessage = "재시도하지 못했습니다."
            }
            retryingId = nil
        }
    }

    private func delete(_ failure: LedgerInboundFailure) {
        // 진행 중이던 로드 응답이 삭제한 건을 되살리지 못하게 무효화한다.
        loadGeneration += 1
        isLoading = false
        Task {
            do {
                try await ledgerService.deleteInboundFailure(id: failure.id)
                failures.removeAll { $0.id == failure.id }
            } catch {
                errorMessage = "삭제하지 못했습니다."
            }
        }
    }
}
