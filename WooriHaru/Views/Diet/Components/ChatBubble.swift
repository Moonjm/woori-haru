import SwiftUI

/// 말풍선 + 날짜 배지.
///
/// **좌우 정렬로 가른다** — `role == .user`가 오른쪽, `.assistant`와 카드가 왼쪽이다.
/// **코치 이름·아바타를 두지 않는다** — 서버 설계가 「이름·캐릭터를 두지 않는다」로 정했다.
/// 이름을 붙이면 말투의 일관성을 계속 맞춰야 하고, 얻는 것이 그것뿐이다.
struct ChatBubble: View {
    let text: String
    let isUser: Bool
    /// 「08-01」. **`date`가 구분선 날짜와 다를 때만 온다** — 판단은 뷰모델이 한다.
    var badge: String?
    /// 보내지 못한 말풍선이면 온다.
    var failureText: String?
    /// **다시 보낼 수 있을 때만 온다.** 빈 날처럼 결과가 뻔한 실패에는 재시도를 두지 않는다 —
    /// 눌러도 같은 거절이 돌아온다.
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            if isUser { Spacer(minLength: 48) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if let badge {
                    ChatDateBadge(text: badge)
                }

                Text(text)
                    .font(.footnote)
                    .foregroundStyle(isUser ? .white : Color.slate700)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .modifier(BubbleSurface(isUser: isUser))

                if let failureText {
                    failureRow(failureText, onRetry)
                }
            }

            if !isUser { Spacer(minLength: 48) }
        }
    }

    /// 내 말풍선만 색을 채운다 — 코치 쪽은 카드와 같은 유리다.
    private struct BubbleSurface: ViewModifier {
        let isUser: Bool

        func body(content: Content) -> some View {
            let shape = RoundedRectangle(cornerRadius: 14)
            if isUser {
                content.background(Color.blue500, in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        }
    }

    /// **말풍선을 지우지 않는다** — 지우면 사용자가 다시 타이핑해야 한다. 서버는 실패하면
    /// 질문도 저장하지 않으므로(한 트랜잭션) 재시도가 안전하다.
    ///
    /// **이유를 적는다.** 전송 실패는 알럿을 띄우지 않으므로(이 줄이 그 자리를 지킨다)
    /// 여기가 비면 사용자는 왜 실패했는지 영영 알 수 없다.
    private func failureRow(_ text: String, _ onRetry: (() -> Void)?) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.caption2)
                .foregroundStyle(Color.red500)
                .fixedSize(horizontal: false, vertical: true)
            if let onRetry {
                Button("다시 시도", action: onRetry)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.blue500)
                    .buttonStyle(.plain)
            }
        }
    }
}

/// 「어느 날 밥 얘기인가」. 구분선(`createdAt`)과 다를 때만 붙는다.
struct ChatDateBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.slate500)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.slate100, in: Capsule())
    }
}

/// 답을 기다리는 코치 자리. LLM이 수 초 걸린다.
struct ChatLoadingBubble: View {
    var body: some View {
        HStack(spacing: 0) {
            ProgressView()
                .controlSize(.small)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
            Spacer(minLength: 48)
        }
        .accessibilityLabel("답변을 만들고 있어요")
    }
}
