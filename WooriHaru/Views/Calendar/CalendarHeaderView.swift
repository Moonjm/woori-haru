import SwiftUI

struct CalendarHeaderView: View {
    let monthLabel: String
    let isPickerOpen: Bool
    let onMenuTap: () -> Void
    let onMonthTap: () -> Void
    let onSearchTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onMenuTap) {
                Image(systemName: "line.3.horizontal")
                    .font(.title2)
                    .foregroundStyle(Color.slate700)
            }

            Button(action: onMonthTap) {
                HStack(spacing: 6) {
                    Text(monthLabel)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.slate900)
                    Image(systemName: isPickerOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.slate400)
                }
            }

            Spacer()

            Button(action: onSearchTap) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(Color.slate700)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.white)
    }
}
