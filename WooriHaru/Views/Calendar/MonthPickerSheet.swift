import SwiftUI
import UIKit

/// 캘린더 상단 제목 탭 시 아래에서 올라오는 년/월 선택 바텀시트.
/// 네이버 달력풍 스케일링 피커(가운데 크게/굵게, 멀수록 작고 흐리게). 확인 시에만 onConfirm 호출.
struct MonthPickerSheet: View {
    let initialYear: Int
    let initialMonth: Int
    let onConfirm: (Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedYear: Int
    @State private var selectedMonth: Int

    private var years: [Int] {
        let y = Calendar.current.component(.year, from: Date())
        let lower = min(initialYear, y - 10)
        let upper = max(initialYear, y + 10)
        return Array(lower...upper)
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
            NaverStyleMonthPicker(
                years: years,
                selectedYear: $selectedYear,
                selectedMonth: $selectedMonth
            )
            .frame(height: 220)

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

// MARK: - 네이버 달력풍 스케일링 피커 (년/월)

private struct NaverStyleMonthPicker: UIViewRepresentable {
    let years: [Int]
    @Binding var selectedYear: Int
    @Binding var selectedMonth: Int
    fileprivate let months = Array(1...12)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.delegate = context.coordinator
        picker.dataSource = context.coordinator
        picker.backgroundColor = .clear
        picker.subviews.forEach { $0.backgroundColor = .clear }
        if let yi = years.firstIndex(of: selectedYear) {
            picker.selectRow(yi, inComponent: 0, animated: false)
        }
        if let mi = months.firstIndex(of: selectedMonth) {
            picker.selectRow(mi, inComponent: 1, animated: false)
        }
        return picker
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.parent = self
        picker.subviews.forEach { $0.backgroundColor = .clear }
    }

    class Coordinator: NSObject, UIPickerViewDelegate, UIPickerViewDataSource {
        var parent: NaverStyleMonthPicker
        init(_ parent: NaverStyleMonthPicker) { self.parent = parent }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            component == 0 ? parent.years.count : parent.months.count
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { 44 }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let selected = pickerView.selectedRow(inComponent: component)
            let dist = abs(row - selected)
            let items = component == 0 ? parent.years : parent.months
            let suffix = component == 0 ? "년" : "월"

            let label = (view as? UILabel) ?? UILabel()
            label.text = "\(items[row])\(suffix)"
            label.textAlignment = .center
            label.backgroundColor = .clear

            let fontSize: CGFloat
            let weight: UIFont.Weight
            let alpha: CGFloat
            switch dist {
            case 0: fontSize = 24; weight = .bold; alpha = 1.0
            case 1: fontSize = 19; weight = .regular; alpha = 0.55
            case 2: fontSize = 16; weight = .regular; alpha = 0.3
            default: fontSize = 14; weight = .regular; alpha = 0.18
            }
            label.font = .systemFont(ofSize: fontSize, weight: weight)
            label.alpha = alpha
            label.textColor = .label
            return label
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            if component == 0 {
                parent.selectedYear = parent.years[row]
            } else {
                parent.selectedMonth = parent.months[row]
            }
            pickerView.reloadComponent(component)
        }
    }
}
