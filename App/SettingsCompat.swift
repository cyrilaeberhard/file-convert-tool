import SwiftUI

struct MatrixView: View {
    let rows: [String]
    let cols: [String]

    private func cell(_ content: some View) -> some View {
        content.frame(minWidth: 30, minHeight: 30).background(Color.primary.opacity(0.06))
    }

    var body: some View {
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            GridRow {
                cell(Image(systemName: "arrow.turn.up.right").foregroundColor(.secondary).frame(width: 52))
                ForEach(cols, id: \.self) { cell(Text($0.uppercased()).font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)) }
            }
            ForEach(rows, id: \.self) { row in
                GridRow {
                    cell(Text(row.uppercased()).font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.tail).frame(width: 52))
                    ForEach(cols, id: \.self) { col in
                        if row == col { cell(Text("–").foregroundColor(.secondary.opacity(0.5))) }
                        else if Caps.targets(of: row).contains(col) { cell(Image(systemName: "checkmark")) }
                        else { cell(Text("–").foregroundColor(.secondary.opacity(0.5))) }
                    }
                }
            }
        }
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct CompatibilityTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("Format Compatibility", systemImage: "tablecells").font(.callout)
                ForEach(Caps.groups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(group.title, systemImage: group.symbol).font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            MatrixView(rows: group.rows, cols: group.cols)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.07)))
                }
            }
        }
    }
}
