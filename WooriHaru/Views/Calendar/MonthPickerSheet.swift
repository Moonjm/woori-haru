import SwiftUI

/// 캘린더 상단 제목 탭 시 아래에서 올라오는 년/월 선택 바텀시트.
/// 확인 시에만 onConfirm 호출(즉시 적용 아님), 취소는 변경 없이 닫기.
struct MonthPickerSheet: View {
    let initialYear: Int
    let initialMonth: Int
    let onConfirm: (Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedYear: Int
    @State private var selectedMonth: Int

    private static var years: [Int] {
        let y = Calendar.current.component(.year, from: Date())
        return Array((y - 10)...(y + 10))
    }

    init(initialYear: Int, initialMonth: Int, onConfirm: @escaping (Int, Int) -> Void) {
        self.initialYear = initialYear
        self.initialMonth = initialMonth
        self.onConfirm = onConfirm
        _selectedYear = State(initialValue: initialYear)
        _selectedMonth = State(initialValue: initialMonth)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Picker("연도", selection: $selectedYear) {
                    ForEach(Self.years, id: \.self) { y in
                        Text("\(String(y))년").tag(y)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                Picker("월", selection: $selectedMonth) {
                    ForEach(1...12, id: \.self) { m in
                        Text("\(m)월").tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 200)

            HStack(spacing: 12) {
                Button("취소") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundStyle(Color.slate700)

                Button("확인") {
                    onConfirm(selectedYear, selectedMonth)
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .appGlassProminentButton()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .padding(.top, 12)
    }
}
