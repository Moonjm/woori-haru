import SwiftUI

/// 코치 타임라인 — 끼니 카드·총평 카드·질문·답변이 시각 순으로 쌓인다.
///
/// **처음 열어도 빈 화면이 아니다.** 대화창이 아니라 타임라인이라, 끼니를 확정하면 서버가
/// 그 자리에 카드를 쌓아 둔다.
struct DietChatView: View {
    @State private var vm: DietChatViewModel
    @State private var draft = ""

    /// **보고 있던 날짜를 그대로 앵커로 받는다.** 하루도 함께 받아 칩·잠금 판단에 새 호출이
    /// 들지 않게 한다 — `DietHomeView`가 이미 갖고 있다.
    init(anchorDate: Date, day: DailyDiet?, service: any DietServing = DietService()) {
        _vm = State(wrappedValue: DietChatViewModel(service: service, anchorDate: anchorDate, day: day))
    }

    var body: some View {
        VStack(spacing: 0) {
            stream
            composer
        }
        .glassScreenBackground()
        .navigationTitle("식단 코치")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .alert("오류", isPresented: .init(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - 스트림

    private var stream: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if vm.hasMore {
                        topLoader(proxy)
                    }

                    ForEach(vm.rows) { row in
                        rowView(row).id(row.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            // **맨 아래에서 연다.** 보고 있던 날짜 카드로 자동 스크롤하지 않는다 — 첫 페이지에
            // 그 카드가 없을 수도 있고, 채팅앱이 맨 아래에서 열리지 않으면 그 자체로 낯설다.
            .defaultScrollAnchor(.bottom)
            .overlay {
                if vm.isLoadingPage && !vm.hasLoaded {
                    ProgressView()
                }
            }
        }
    }

    /// 맨 위에 닿으면 다음 장을 부른다. **로딩 가드는 뷰모델에 있다** — 스크롤이 위쪽에
    /// 머무는 동안 `onAppear`가 여러 번 뜬다.
    private func topLoader(_ proxy: ScrollViewProxy) -> some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .onAppear {
                Task {
                    // **스크롤 위치를 유지한다.** 위에 붙이면 콘텐츠가 밀려 읽던 자리가 튄다 —
                    // 붙이기 전의 첫 줄에 앵커를 잡았다가 되돌린다.
                    let anchor = vm.rows.first?.id
                    await vm.loadNextPage()
                    if let anchor {
                        proxy.scrollTo(anchor, anchor: .top)
                    }
                }
            }
    }

    @ViewBuilder
    private func rowView(_ row: ChatRow) -> some View {
        switch row {
        case .dateSeparator(let day):
            dateSeparator(day)

        case .message(let message, let badge):
            messageView(message, badge: badge)

        case .pending(let pending, let badge):
            ChatBubble(
                text: pending.text,
                isUser: true,
                badge: badge,
                onRetry: pending.failed ? { Task { await vm.retry() } } : nil
            )

        case .awaitingReply:
            ChatLoadingBubble()
        }
    }

    @ViewBuilder
    private func messageView(_ message: ChatMessage, badge: String?) -> some View {
        switch message.type {
        case .text:
            ChatBubble(text: message.content ?? "", isUser: message.role == .user, badge: badge)
        case .mealCard:
            if let meal = message.meal {
                ChatMealCardView(card: meal, badge: badge)
            }
        case .daySummary:
            if let day = message.day {
                ChatDayCardView(card: day, date: message.date, badge: badge)
            }
        case .unknown:
            // 뷰모델이 이미 걸렀다 — 여기 오면 아무것도 그리지 않는다.
            EmptyView()
        }
    }

    /// **`createdAt` 기준이다.** 말풍선 배지(`date`)와 다른 축이다.
    private func dateSeparator(_ day: String) -> some View {
        HStack(spacing: 8) {
            separatorLine
            Text(Date.from(day)?.monthDayText ?? day)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.slate400)
            separatorLine
        }
        .padding(.vertical, 4)
    }

    private var separatorLine: some View {
        Rectangle()
            .fill(Color.slate200)
            .frame(height: 1)
    }

    // MARK: - 입력

    private var composer: some View {
        VStack(spacing: 8) {
            if !vm.suggestedQuestions.isEmpty {
                suggestionChips
            }

            if let notice = vm.lockedNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let anchorText = vm.anchorChipText {
                anchorChip(anchorText)
            }

            inputRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// 탭하면 **곧바로 전송된다** — 편집할 기회를 주면 두 번 탭해야 한다.
    /// **빈 날이면 뷰모델이 빈 배열을 준다** — 물을 것이 없다.
    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.suggestedQuestions, id: \.self) { question in
                    Button {
                        Task { await vm.send(question) }
                    } label: {
                        Text(question)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.blue500)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .glassInputField(cornerRadius: 16)
                    }
                    .buttonStyle(.plain)
                    .disabled(!vm.canSend)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    /// 「8월 1일에 대해 묻는 중」. `✕`를 누르면 앵커가 **오늘로** 돌아가고 칩은 사라진다.
    private func anchorChip(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.caption2)
            Text(text)
                .font(.caption.weight(.medium))
            Button {
                Task { await vm.resetAnchorToToday() }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("오늘로 돌아가기")
            Spacer()
        }
        .foregroundStyle(Color.slate500)
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("무엇이든 물어보세요!", text: $draft, axis: .vertical)
                .font(.footnote)
                .lineLimit(1...4)
                .disabled(vm.isInputLocked || vm.isSending)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassInputField(cornerRadius: 18)

            Button {
                let text = draft
                draft = ""
                Task { await vm.send(text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canSubmit ? Color.blue500 : Color.slate300)
            .disabled(!canSubmit)
            .accessibilityLabel("보내기")
        }
    }

    /// **전송 중에는 입력창과 칩을 잠근다** — `MealConfirmViewModel.isSaving`과 같은 가드다.
    private var canSubmit: Bool {
        vm.canSend && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
