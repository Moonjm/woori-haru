import SwiftUI

struct WeeklyStudyRecordSection: View {
    let vm: StudyRecordViewModel
    let showAllRecordsLink: Bool

    @State private var expandedWeekId: String?
    @State private var selectedTooltip: DailyTooltipKey?

    private enum DailyTooltipType {
        case study, rest
    }

    private struct DailyTooltipKey: Equatable {
        let dateId: String
        let type: DailyTooltipType
    }

    init(vm: StudyRecordViewModel, showAllRecordsLink: Bool = false) {
        self.vm = vm
        self.showAllRecordsLink = showAllRecordsLink
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            let activeWeeks = Array(
                vm.weeklyRecords
                    .filter { $0.totalSeconds + $0.pauseSeconds > 0 }
                    .reversed()
            )

            if activeWeeks.isEmpty {
                emptyStateView
            } else {
                ForEach(activeWeeks) { week in
                    weekGroup(week)
                }
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .simultaneousGesture(TapGesture().onEnded {
            if selectedTooltip != nil {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedTooltip = nil
                }
            }
        })
        .onChange(of: vm.selectedDate) {
            guard let date = vm.selectedDate,
                  let weekId = vm.weekId(for: date) else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                expandedWeekId = weekId
                selectedTooltip = nil
            }
        }
    }

    private var header: some View {
        HStack {
            Text("주간 공부 기록")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.slate700)
            Spacer()
            if showAllRecordsLink {
                NavigationLink(value: AppDestination.studyRecord) {
                    HStack(spacing: 4) {
                        Text("전체 기록")
                            .font(.caption)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(Color.blue500)
                }
            }
        }
    }

    private func weekGroup(_ week: WeeklyStudyRecord) -> some View {
        let isExpanded = expandedWeekId == week.id
        return VStack(spacing: 0) {
            weeklyRow(week, isExpanded: isExpanded)
            if isExpanded {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.blue300)
                        .frame(width: 3)
                    VStack(spacing: 6) {
                        ForEach(week.dailyRecords.filter { !$0.sessions.isEmpty }) { record in
                            dailyRecordRow(record)
                        }
                    }
                }
                .padding(.leading, 14)
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func weeklyRow(_ week: WeeklyStudyRecord, isExpanded: Bool) -> some View {
        let goalMinutes = StudyTimerViewModel.weeklyGoalMinutes
        let goalSeconds = goalMinutes * 60
        let goalHoursText = "\(goalMinutes / 60)시간"
        let rawRatio = Double(week.totalSeconds) / Double(goalSeconds)
        let studyRatio = min(rawRatio, 1.0)
        let studyPct = Int((rawRatio * 100).rounded())

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(weekRangeText(week))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.slate500)
                Spacer()
                HStack(spacing: 8) {
                    Text("공부 \(week.totalSeconds.durationText) / \(goalHoursText) (\(studyPct)%)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.blue500)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.slate400)
                }
            }

            GeometryReader { geo in
                let barWidth = geo.size.width
                let studyWidth = barWidth * studyRatio

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.slate200)
                        .frame(width: barWidth)
                    if studyWidth > 0 {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.blue400)
                            .frame(width: studyWidth)
                            .overlay {
                                if studyWidth >= 32 {
                                    Text("\(studyPct)%")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                }
            }
            .frame(height: 20)
        }
        .padding(12)
        .background(isExpanded ? Color.blue50 : Color.slate50)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.18)) {
                expandedWeekId = isExpanded ? nil : week.id
                selectedTooltip = nil
            }
        }
    }

    private func dailyRecordRow(_ record: DailyStudyRecord) -> some View {
        let total = record.totalSeconds + record.pauseSeconds
        let studyRatio = total > 0 ? Double(record.totalSeconds) / Double(total) : 1.0
        let hasRest = record.pauseSeconds > 0
        let isStudySelected = selectedTooltip == DailyTooltipKey(dateId: record.id, type: .study)
        let isRestSelected = selectedTooltip == DailyTooltipKey(dateId: record.id, type: .rest)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(dayHeaderText(record.date))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.slate500)
                Spacer()
                HStack(spacing: 6) {
                    Text("공부 \(record.totalSeconds.durationText)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.blue500)
                    if hasRest {
                        Text("휴식 \(record.pauseSeconds.durationText)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.slate400)
                    }
                }
            }

            GeometryReader { geo in
                let barWidth = geo.size.width
                let studyWidth = barWidth * studyRatio
                let restWidth = barWidth - studyWidth
                let studyPct = Int((studyRatio * 100).rounded())
                let restPct = 100 - studyPct

                HStack(spacing: 0) {
                    if studyWidth > 0 {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 3, bottomLeadingRadius: 3,
                            bottomTrailingRadius: hasRest ? 0 : 3,
                            topTrailingRadius: hasRest ? 0 : 3
                        )
                        .fill(isStudySelected ? Color.blue500 : Color.blue400)
                        .frame(width: studyWidth)
                        .overlay {
                            if studyWidth >= 26 {
                                Text("\(studyPct)%")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTooltip = isStudySelected ? nil : DailyTooltipKey(dateId: record.id, type: .study)
                            }
                        }
                    }
                    if hasRest && restWidth > 0 {
                        UnevenRoundedRectangle(
                            topLeadingRadius: studyWidth > 0 ? 0 : 3,
                            bottomLeadingRadius: studyWidth > 0 ? 0 : 3,
                            bottomTrailingRadius: 3, topTrailingRadius: 3
                        )
                        .fill(isRestSelected ? Color.slate400 : Color.slate200)
                        .frame(width: restWidth)
                        .overlay {
                            if restWidth >= 26 {
                                Text("\(restPct)%")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(Color.slate600)
                            }
                        }
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTooltip = isRestSelected ? nil : DailyTooltipKey(dateId: record.id, type: .rest)
                            }
                        }
                    }
                }
            }
            .frame(height: 14)

            if isStudySelected {
                dailyBreakdownDetail(
                    title: "과목별",
                    items: vm.subjectBreakdown(for: record).map { ($0.name, $0.seconds) },
                    color: Color.blue500
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isRestSelected {
                dailyBreakdownDetail(
                    title: "휴식 종류별",
                    items: vm.pauseBreakdown(for: record).map { ($0.label, $0.seconds) },
                    color: Color.slate500
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.slate50)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func dailyBreakdownDetail(title: String, items: [(String, Int)], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.0)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.slate700)
                    Spacer()
                    Text(item.1.durationText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.slate600)
                }
            }
        }
        .padding(6)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "book.closed")
                .font(.title2)
                .foregroundStyle(Color.slate200)
            Text("아직 기록이 많지 않아요")
                .font(.caption)
                .foregroundStyle(Color.slate400)
            Text("오늘부터 공부 기록을 쌓아보세요")
                .font(.caption)
                .foregroundStyle(Color.slate400)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private static let dayHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 EEEE"
        return f
    }()

    private func dayHeaderText(_ date: Date) -> String {
        Self.dayHeaderFormatter.string(from: date)
    }

    private func weekRangeText(_ week: WeeklyStudyRecord) -> String {
        let startMonth = week.weekStart.month
        let endMonth = week.weekEnd.month
        let startDay = week.weekStart.day
        let endDay = week.weekEnd.day
        if startMonth == endMonth {
            return "\(startMonth)월 \(startDay)일 - \(endDay)일"
        }
        return "\(startMonth)월 \(startDay)일 - \(endMonth)월 \(endDay)일"
    }
}
