import SwiftUI

/// 연별 통계에서 기간 타이틀 탭 시 올라오는 연도 선택 바텀시트 — MonthPickerSheet와 같은 톤.
struct YearPickerSheet: View {
    let initialYear: Int
    let range: ClosedRange<Int>
    let onConfirm: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Int

    init(initialYear: Int, range: ClosedRange<Int>, onConfirm: @escaping (Int) -> Void) {
        self.initialYear = initialYear
        self.range = range
        self.onConfirm = onConfirm
        _selected = State(initialValue: initialYear)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("연도", selection: $selected) {
                ForEach(Array(range), id: \.self) { Text("\($0)년").tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(height: 220)

            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Text("취소")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundStyle(Color.slate700)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.slate200, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)

                Button {
                    onConfirm(selected)
                    dismiss()
                } label: {
                    Text("확인")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundStyle(.white)
                        .background(Color.slate900)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .padding(.top, 12)
    }
}
