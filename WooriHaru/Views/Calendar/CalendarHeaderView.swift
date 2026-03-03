import SwiftUI

struct CalendarHeaderView: View {
    let monthLabel: String
    let onMenuTap: () -> Void
    let onMonthTap: () -> Void
    let onSearchTap: () -> Void

    var body: some View {
        HStack {
            Button(action: onMenuTap) {
                Image(systemName: "line.3.horizontal")
                    .font(.title3)
                    .foregroundStyle(Color.slate700)
            }

            Spacer()

            Button(action: onMonthTap) {
                HStack(spacing: 4) {
                    Text(monthLabel)
                        .font(.headline)
                        .foregroundStyle(Color.slate900)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Color.slate500)
                }
            }

            Spacer()

            Button(action: onSearchTap) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(Color.slate700)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.white)
    }
}
