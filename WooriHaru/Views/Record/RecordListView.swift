import SwiftUI

struct RecordListView: View {
    let records: [DailyRecord]
    let onDelete: (DailyRecord) -> Void
    let onTap: (DailyRecord) -> Void

    var body: some View {
        if records.isEmpty {
            Text("기록이 없습니다")
                .font(.subheadline)
                .foregroundStyle(Color.slate400)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("나의 기록")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.slate600)

                FlowLayout(spacing: 6) {
                    ForEach(records) { record in
                        RecordPill(record: record, onDelete: { onDelete(record) })
                            .onTapGesture { onTap(record) }
                    }
                }
            }
        }
    }
}

struct RecordPill: View {
    let record: DailyRecord
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(record.category.emoji)
                .font(.subheadline)
            Text(record.category.name)
                .font(.caption)
            if let memo = record.memo, !memo.isEmpty {
                Text(memo)
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
            }
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.red400)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
                .stroke(Color.slate200, lineWidth: 1)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
