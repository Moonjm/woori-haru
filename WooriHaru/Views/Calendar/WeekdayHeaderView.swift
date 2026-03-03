import SwiftUI

struct WeekdayHeaderView: View {
    private let days = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                Text(day)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(index == 0 ? Color.red500 : index == 6 ? Color.blue500 : Color.slate500)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .background(.white)
    }
}
