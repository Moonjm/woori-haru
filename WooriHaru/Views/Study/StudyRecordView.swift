import SwiftUI

struct StudyRecordView: View {
    @State private var vm = StudyRecordViewModel()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    monthNavigationHeader
                    monthlyHeatmap
                    monthlySummaryCard

                    if !vm.dailyRecords.isEmpty {
                        dailyBarChart
                        subjectBreakdown
                        hourlyPattern
                    }

                    dailySessionList
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Color.slate50)
            .onChange(of: vm.selectedDate) {
                if let date = vm.selectedDate {
                    withAnimation {
                        proxy.scrollTo("sessions-\(date.dateString)", anchor: .top)
                    }
                }
            }
        }
        .navigationTitle("전체 기록")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !vm.isCurrentMonth {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("오늘") { vm.goToToday() }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.blue500)
                }
            }
        }
        .task { await vm.loadMonth() }
        .alert("오류", isPresented: .init(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Month Navigation

    private var monthNavigationHeader: some View {
        HStack {
            Button { vm.goToPreviousMonth() } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.slate600)
            }

            Spacer()

            Text(vm.monthLabel)
                .font(.headline)
                .foregroundStyle(Color.slate900)

            Spacer()

            Button { vm.goToNextMonth() } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(vm.isCurrentMonth ? Color.slate200 : Color.slate600)
            }
            .disabled(vm.isCurrentMonth)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    // MARK: - Monthly Heatmap

    private var monthlyHeatmap: some View {
        VStack(alignment: .leading, spacing: 12) {
            let weekdays = ["일", "월", "화", "수", "목", "금", "토"]
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

            // 요일 헤더
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.slate400)
                        .frame(maxWidth: .infinity)
                }
            }

            // 히트맵 셀
            LazyVGrid(columns: columns, spacing: 4) {
                // 첫째 주 빈 칸
                let firstWeekday = vm.dailyRecords.first?.date.weekday ?? 1
                ForEach(0..<(firstWeekday - 1), id: \.self) { _ in
                    Color.clear.frame(height: 36)
                }

                ForEach(vm.dailyRecords) { record in
                    heatmapCell(record)
                }
            }

            // 범례
            HStack(spacing: 4) {
                Spacer()
                Text("적음")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.slate400)
                ForEach(0...4, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(heatmapColor(level: level))
                        .frame(width: 14, height: 14)
                }
                Text("많음")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.slate400)
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func heatmapCell(_ record: DailyStudyRecord) -> some View {
        let isSelected = vm.selectedDate?.dateString == record.date.dateString
        let level = vm.heatmapLevel(for: record.totalSeconds)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                vm.selectedDate = isSelected ? nil : record.date
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(heatmapColor(level: level))
                    .frame(height: 36)

                Text("\(record.date.day)")
                    .font(.system(size: 12, weight: level > 2 ? .medium : .regular))
                    .foregroundStyle(level > 2 ? .white : Color.slate700)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.blue500 : .clear, lineWidth: 2)
            )
        }
    }

    private func heatmapColor(level: Int) -> Color {
        switch level {
        case 0: return Color.slate100
        case 1: return Color.blue50
        case 2: return Color.blue300
        case 3: return Color.blue500
        default: return Color.blue700
        }
    }

    // MARK: - Monthly Summary Card

    private var monthlySummaryCard: some View {
        let s = vm.summary
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
            summaryItem(label: "총 공부시간", value: s.totalFormatted, icon: "clock")
            summaryItem(label: "공부한 날", value: "\(s.studyDays)일", icon: "calendar")
            summaryItem(label: "일 평균", value: s.averageFormatted, icon: "chart.line.uptrend.xyaxis")
            summaryItem(label: "최고 기록", value: s.maxFormatted, icon: "flame")
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func summaryItem(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.blue500)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.slate400)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate900)
            }

            Spacer()
        }
        .padding(10)
        .background(Color.slate50)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Daily Bar Chart

    private var dailyBarChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("일별 공부시간")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.slate700)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(vm.dailyRecords) { record in
                        let isSelected = vm.selectedDate?.dateString == record.date.dateString
                        let maxSeconds = max(vm.maxDailySeconds, 1)
                        let totalWithPause = record.totalSeconds + record.pauseSeconds
                        let fullHeight = max(CGFloat(totalWithPause) / CGFloat(maxSeconds) * 100, totalWithPause > 0 ? 4 : 1)
                        let studyHeight = totalWithPause > 0 ? fullHeight * CGFloat(record.totalSeconds) / CGFloat(totalWithPause) : fullHeight
                        let pauseHeight = fullHeight - studyHeight

                        VStack(spacing: 0) {
                            if pauseHeight > 0 {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(isSelected ? Color.slate400 : Color.slate200)
                                    .frame(width: 8, height: pauseHeight)
                            }
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isSelected ? Color.blue500 : (record.totalSeconds > 0 ? Color.blue300 : Color.slate100))
                                .frame(width: 8, height: max(studyHeight, totalWithPause > 0 ? 2 : 1))
                        }

                        .overlay(alignment: .bottom) {
                            if record.date.day % 5 == 1 || record.date.day == 1 {
                                Text("\(record.date.day)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.slate400)
                                    .offset(y: 14)
                            }
                        }
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                vm.selectedDate = isSelected ? nil : record.date
                            }
                        }
                    }
                }
                .frame(height: 120)
                .padding(.horizontal, 4)
                .padding(.bottom, 16)
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Subject Breakdown

    private var subjectBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("과목별 공부시간")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.slate700)

            if vm.subjectRecords.isEmpty {
                Text("기록이 없습니다")
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ForEach(vm.subjectRecords) { subject in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(subject.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.slate900)

                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.blue400)
                                    .frame(width: geo.size.width * subject.ratio)
                            }
                            .frame(height: 6)
                        }

                        Text(subject.totalSeconds.durationText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.blue600)
                            .frame(minWidth: 60, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Hourly Pattern

    private var hourlyPattern: some View {
        let pattern = vm.hourlyPattern
        let maxVal = max(pattern.max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("시간대별 공부 패턴")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)
                Spacer()
                if let peak = vm.peakHourRange {
                    Text("집중 시간대 \(peak)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.blue500)
                }
            }

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    let val = pattern[hour]
                    let height = max(CGFloat(val) / CGFloat(maxVal) * 60, val > 0 ? 3 : 1)

                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(val > 0 ? Color.blue400 : Color.slate100)
                            .frame(height: height)

                        if hour % 6 == 0 {
                            Text("\(hour)")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.slate400)
                        } else {
                            Text("")
                                .font(.system(size: 9))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 80)
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Daily Session List

    private var dailySessionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("날짜별 기록")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.slate700)

            let records = filteredRecords

            if records.allSatisfy({ $0.sessions.isEmpty }) {
                emptyStateView
            } else {
                ForEach(records.reversed().filter { !$0.sessions.isEmpty }) { record in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(dayHeaderText(record.date))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.slate500)
                            Spacer()
                            Text(record.totalSeconds.durationText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.blue500)
                        }

                        ForEach(record.sessions) { session in
                            sessionRow(session)
                        }
                    }
                    .id("sessions-\(record.id)")
                    .padding(12)
                    .background(Color.slate50)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var filteredRecords: [DailyStudyRecord] {
        if let date = vm.selectedDate {
            return vm.dailyRecords.filter { $0.date.dateString == date.dateString }
        }
        return vm.dailyRecords
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

    private func sessionRow(_ session: StudySession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.subject.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.slate900)
                Text(sessionTimeRange(session))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.slate400)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("공부 \(session.totalSeconds.durationText)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.blue600)
                if session.pauseSeconds > 0 {
                    Text("휴식 \(session.pauseSeconds.durationText)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.slate400)
                }
            }
        }
    }

    // MARK: - Helpers

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

    private func sessionTimeRange(_ session: StudySession) -> String {
        let start = formatTime(session.startedAt)
        let end = session.endedAt.map { formatTime($0) } ?? "진행중"
        return "\(start) - \(end)"
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
}
