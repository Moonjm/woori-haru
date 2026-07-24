import SwiftUI

/// 오늘 공부 흐름 타임라인 — 세션별 공부/휴식 구간을 비율 막대로 표시, 구간 탭 시 툴팁.
struct StudyTodayTimelineView: View {
    @Environment(StudyTimerViewModel.self) private var vm
    @Environment(PauseTypeStore.self) private var pauseTypeStore
    /// 선택된 구간 키("세션id-구간idx") — 화면 어디를 탭해도 해제되도록 부모가 소유한다.
    @Binding var selectedSegmentKey: String?

    /// 차트에서 무시할 최소 세그먼트 길이(초) — 타이밍 오차로 생긴 미세 구간 필터링
    private let minimumSegmentDuration: TimeInterval = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("오늘 공부 흐름")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.slate700)

            if vm.todaySessions.isEmpty {
                Text("아직 기록이 없습니다")
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 6) {
                    ForEach(vm.todaySessions) { session in
                        timelineBar(session)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private func timelineBar(_ session: StudySession) -> some View {
        let startText = formatTime(session.startedAt)

        return HStack(spacing: 8) {
            Text(startText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.slate400)
                .frame(width: 38, alignment: .trailing)

            timelineSegments(session)
                .frame(height: 10)
        }
    }

    private func timelineSegments(_ session: StudySession) -> some View {
        let segments = buildTimelineSegments(session)
        let totalDuration = segments.reduce(0.0) { $0 + $1.duration }

        return GeometryReader { geo in
            if totalDuration > 0 {
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(segments.indices, id: \.self) { i in
                            let seg = segments[i]
                            let width = geo.size.width * (seg.duration / totalDuration)
                            let key = "\(session.id)-\(i)"
                            let isSelected = selectedSegmentKey == key

                            RoundedRectangle(cornerRadius: 3)
                                .fill(seg.isStudy ? Color.blue400 : Color.slate200)
                                .frame(width: max(width, 1))
                                .overlay(alignment: .top) {
                                    if isSelected {
                                        segmentTooltip(seg)
                                            .offset(y: -28)
                                    }
                                }
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedSegmentKey = isSelected ? nil : key
                                    }
                                }
                        }
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.blue400)
            }
        }
    }

    private func segmentTooltip(_ segment: TimelineSegment) -> some View {
        let seconds = Int(segment.duration)
        let label = segment.isStudy ? "공부" : pauseTypeLabel(segment.typeValue)
        return VStack(spacing: 0) {
            Text("\(label) \(seconds.durationText)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.slate700)
                .clipShape(Capsule())
            Triangle()
                .fill(Color.slate700)
                .frame(width: 8, height: 5)
        }
        .fixedSize()
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                p.closeSubpath()
            }
        }
    }

    private struct TimelineSegment {
        let isStudy: Bool
        let duration: Double
        let typeValue: String
    }

    private func buildTimelineSegments(_ session: StudySession) -> [TimelineSegment] {
        guard let start = Date.fromISO(session.startedAt) else { return [] }
        let end = session.effectiveEndDate
        let sortedPauses = session.pauses
            .compactMap { pause -> (start: Date, end: Date, type: String)? in
                guard let ps = Date.fromISO(pause.pausedAt) else { return nil }
                let pe = pause.resumedAt.flatMap { Date.fromISO($0) } ?? end
                return (ps, pe, pause.type ?? "REST")
            }
            .sorted { $0.start < $1.start }

        guard !sortedPauses.isEmpty else {
            return [TimelineSegment(isStudy: true, duration: end.timeIntervalSince(start), typeValue: "")]
        }

        var segments: [TimelineSegment] = []
        var cursor = start
        for pause in sortedPauses {
            if cursor < pause.start {
                segments.append(TimelineSegment(isStudy: true, duration: pause.start.timeIntervalSince(cursor), typeValue: ""))
            }
            if pause.start < pause.end {
                segments.append(TimelineSegment(isStudy: false, duration: pause.end.timeIntervalSince(pause.start), typeValue: pause.type))
            }
            cursor = pause.end
        }
        if cursor < end {
            segments.append(TimelineSegment(isStudy: true, duration: end.timeIntervalSince(cursor), typeValue: ""))
        }
        return segments.filter { $0.duration >= minimumSegmentDuration }
    }

    private func pauseTypeLabel(_ value: String) -> String {
        pauseTypeStore.pauseTypes.first(where: { $0.value == value })?.label ?? value
    }

    // MARK: - Time Helpers

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func formatTime(_ isoString: String) -> String {
        if let date = Date.fromISO(isoString) {
            return Self.timeFormatter.string(from: date)
        }
        return "??:??"
    }
}
