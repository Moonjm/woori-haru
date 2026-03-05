import SwiftUI
import UIKit

struct YearMonthPickerView: View {
    @Binding var isPresented: Bool
    let initialYear: Int
    let initialMonth: Int
    let onSelect: (Int, Int) -> Void

    @State private var selectedYear: Int
    @State private var selectedMonth: Int

    init(isPresented: Binding<Bool>, initialYear: Int, initialMonth: Int, onSelect: @escaping (Int, Int) -> Void) {
        _isPresented = isPresented
        self.initialYear = initialYear
        self.initialMonth = initialMonth
        self.onSelect = onSelect
        _selectedYear = State(initialValue: initialYear)
        _selectedMonth = State(initialValue: initialMonth)
    }

    var body: some View {
        NaverStylePicker(
            selectedYear: $selectedYear,
            selectedMonth: $selectedMonth
        )
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.15, green: 0.15, blue: 0.17))
        .onChange(of: selectedYear) { _, val in onSelect(val, selectedMonth) }
        .onChange(of: selectedMonth) { _, val in onSelect(selectedYear, val) }
    }
}

// MARK: - UIKit UIPickerView wrapper for Naver-style scaling

private struct NaverStylePicker: UIViewRepresentable {
    @Binding var selectedYear: Int
    @Binding var selectedMonth: Int

    private static let years = Array(2020...(Calendar.current.component(.year, from: Date()) + 10))
    private static let months = Array(1...12)

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.delegate = context.coordinator
        picker.dataSource = context.coordinator
        picker.backgroundColor = .clear

        // Hide default selection indicator
        picker.subviews.forEach { $0.backgroundColor = .clear }

        // Set initial position
        if let yearIdx = Self.years.firstIndex(of: selectedYear) {
            picker.selectRow(yearIdx, inComponent: 0, animated: false)
        }
        if let monthIdx = Self.months.firstIndex(of: selectedMonth) {
            picker.selectRow(monthIdx, inComponent: 1, animated: false)
        }

        return picker
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        picker.subviews.forEach { $0.backgroundColor = .clear }
    }

    class Coordinator: NSObject, UIPickerViewDelegate, UIPickerViewDataSource {
        var parent: NaverStylePicker

        init(_ parent: NaverStylePicker) {
            self.parent = parent
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            component == 0 ? NaverStylePicker.years.count : NaverStylePicker.months.count
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { 40 }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let selected = pickerView.selectedRow(inComponent: component)
            let dist = abs(row - selected)

            let items = component == 0 ? NaverStylePicker.years : NaverStylePicker.months
            let suffix = component == 0 ? "년" : "월"
            let text = "\(items[row])\(suffix)"

            let label = (view as? UILabel) ?? UILabel()
            label.text = text
            label.textAlignment = .center
            label.backgroundColor = .clear

            let fontSize: CGFloat
            let weight: UIFont.Weight
            let alpha: CGFloat

            switch dist {
            case 0:
                fontSize = 22
                weight = .bold
                alpha = 1.0
            case 1:
                fontSize = 18
                weight = .regular
                alpha = 0.6
            case 2:
                fontSize = 15
                weight = .regular
                alpha = 0.35
            default:
                fontSize = 13
                weight = .regular
                alpha = 0.2
            }

            label.font = .systemFont(ofSize: fontSize, weight: weight)
            label.alpha = alpha
            label.textColor = .white

            return label
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            if component == 0 {
                parent.selectedYear = NaverStylePicker.years[row]
            } else {
                parent.selectedMonth = NaverStylePicker.months[row]
            }
            pickerView.reloadComponent(component)
        }
    }
}
