import SwiftUI

struct YearMonthPickerView: View {
    @Binding var isPresented: Bool
    let onSelect: (Int, Int) -> Void

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())

    private let years = Array(2018...2037)
    private let months = Array(1...12)

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 16) {
                HStack {
                    Picker("년", selection: $selectedYear) {
                        ForEach(years, id: \.self) { year in
                            Text("\(year)년").tag(year)
                        }
                    }
                    .pickerStyle(.wheel)

                    Picker("월", selection: $selectedMonth) {
                        ForEach(months, id: \.self) { month in
                            Text("\(month)월").tag(month)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                .frame(height: 150)

                HStack(spacing: 12) {
                    Button("취소") { isPresented = false }
                        .foregroundStyle(Color.slate500)

                    Button("이동") {
                        onSelect(selectedYear, selectedMonth)
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.blue500)
                }
                .font(.subheadline)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white)
                    .shadow(radius: 10)
            )
            .padding(.horizontal, 40)
        }
    }
}
