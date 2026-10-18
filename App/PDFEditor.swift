import AppKit
import PDFKit
import SwiftUI

struct PDFEditView: View {
    @ObservedObject var model: PDFEditModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                VStack(spacing: 2) {
                    Text("Sign & Redact").font(.system(size: 18, weight: .semibold))
                    Text(model.url.lastPathComponent).font(.system(size: 12)).foregroundColor(.white.opacity(0.65)).lineLimit(1)
                }
                HStack {
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                            .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.16)))
                    }.buttonStyle(.plain)
                    Spacer()
                }
            }.padding(14)
            toolbar.padding(.horizontal, 18).padding(.bottom, 10)
            PDFViewHost(model: model)
                .clipShape(RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 18)
            Divider().padding(14)
            HStack {
                Text(hint).font(.system(size: 12)).foregroundColor(.white.opacity(0.65))
                Spacer()
                Button(action: save) {
                    Text(model.hasRedaction ? "Save Redacted PDF" : "Save PDF")
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 22).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10).fill(accent))
                }.buttonStyle(.plain).disabled(model.editCount == 0).opacity(model.editCount == 0 ? 0.4 : 1)
            }.padding(.horizontal, 18).padding(.bottom, 14)
        }
        .frame(width: 860, height: 740)
        .foregroundColor(.white)
        .focusEffectDisabled()
        .liquidGlass(in: RoundedRectangle(cornerRadius: 36))
    }

    private var hint: String {
        switch model.tool {
        case .redact: return "Drag over text or images to black them out. Redacted pages are flattened, the hidden text is gone for good."
        case .sign: return "Click on the page to place your signature. Drag to move, ⌫ to delete."
        case .select: return "Select text or drag existing marks."
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            toolButton(.select, "cursorarrow", "Select")
            toolButton(.redact, "rectangle.fill", "Redact")
            toolButton(.sign, "signature", "Sign")
            Divider().frame(height: 22)
            Button("Signature…") { SignatureWindow.show { model.signature = $0; model.tool = .sign } }.buttonStyle(AccentButton())
            Button { model.resizeSelected(by: 1.15) } label: { Image(systemName: "plus.magnifyingglass") }
                .buttonStyle(.plain).disabled(!(model.selected?.isSignature ?? false)).help("Larger signature")
            Button { model.resizeSelected(by: 1 / 1.15) } label: { Image(systemName: "minus.magnifyingglass") }
                .buttonStyle(.plain).disabled(!(model.selected?.isSignature ?? false)).help("Smaller signature")
            Spacer()
            Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .buttonStyle(.plain).disabled(!model.canUndo).opacity(model.canUndo ? 1 : 0.4)
        }
    }

    private func toolButton(_ tool: EditTool, _ symbol: String, _ title: String) -> some View {
        Button { model.tool = tool } label: {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(model.tool == tool ? accent.opacity(0.7) : Color.white.opacity(0.1)))
        }.buttonStyle(.plain)
    }

    private func save() {
        guard let out = model.save() else {
            let alert = NSAlert()
            alert.messageText = "Speichern fehlgeschlagen"
            alert.runModal()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([out])
        close()
    }
}

enum PDFEditWindow {
    static func show(_ url: URL, tool: EditTool) {
        guard let model = PDFEditModel(url: url, tool: tool) else {
            let alert = NSAlert()
            alert.messageText = "PDF konnte nicht geöffnet werden"
            alert.runModal()
            return
        }
        GlassWindow.present(size: NSSize(width: 860, height: 740)) { close in PDFEditView(model: model, close: close) }
    }
}
