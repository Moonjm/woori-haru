import SwiftUI

/// 스트립이 그리는 사진 한 장. **`id`는 `fileId`다** — 확인 화면(확정 전)과 상세 화면
/// (확정 후) 둘 다 같은 값으로 사진을 가리킨다.
struct StripPhoto: Identifiable, Hashable {
    let id: Int
    /// presigned URL. **10분 만료라 오래 들고 있지 않는다.**
    let url: String?
}

/// 사진 여러 장 가로 스트립 (확인·상세 공용).
/// **사진이 없으면 아무것도 그리지 않는다** — 사진 없이 기록한 끼니는 `photos`가 빈 배열이다.
struct PhotoStrip: View {
    let photos: [StripPhoto]
    /// 인식에 실패한 사진. **감추지 않고 배지를 단다.**
    var failedIds: Set<Int> = []
    /// 탭했을 때. 없으면 탭에 반응하지 않는다 — 확인 화면처럼 열어 볼 자리가 없는 곳도 있다.
    var onTap: ((StripPhoto) -> Void)?

    var body: some View {
        if photos.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photos) { photo in
                        ZStack(alignment: .bottomLeading) {
                            thumbnail(photo.url)

                            if failedIds.contains(photo.id) {
                                Text("인식 실패")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.red500, in: Capsule())
                                    .padding(6)
                            }
                        }
                        // 탭을 받는 곳에서만 버튼이 된다 — 아무 동작 없는 버튼은 눌러도
                        // 반응 없고 접근성 포커스만 잡힌다.
                        .modifier(TapToOpen(photo: photo, onTap: onTap))
                    }
                }
            }
        }
    }

    /// `onTap`이 있을 때만 버튼으로 감싼다.
    private struct TapToOpen: ViewModifier {
        let photo: StripPhoto
        let onTap: ((StripPhoto) -> Void)?

        func body(content: Content) -> some View {
            if let onTap {
                Button { onTap(photo) } label: { content }
                    .buttonStyle(.plain)
                    .accessibilityLabel("사진 크게 보기")
            } else {
                content
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ url: String?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        if let url, let parsed = URL(string: url) {
            AsyncImage(url: parsed) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "photo")
                        .foregroundStyle(Color.slate300)
                default:
                    ProgressView()
                }
            }
            .frame(width: 110, height: 110)
            .clipShape(shape)
        } else {
            shape
                .fill(Color.slate100)
                .frame(width: 110, height: 110)
                .overlay(Image(systemName: "photo").foregroundStyle(Color.slate300))
        }
    }
}
