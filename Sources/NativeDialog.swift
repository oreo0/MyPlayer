import SwiftUI
import AppKit

struct NativeDialog: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let message: String
    func body(content: Content) -> some View {
        content.onChange(of: isPresented, initial: true) { _, presented in
            guard presented else { return }
            DispatchQueue.main.async {
                guard isPresented else { return }
                guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { isPresented = false; return }
                let alert = NSAlert()
                alert.messageText = title
                alert.informativeText = message
                alert.addButton(withTitle: "好")
                alert.beginSheetModal(for: window) { _ in isPresented = false }
            }
        }
    }
}
extension View {
    func nativeDialog(_ title: String, isPresented: Binding<Bool>, message: String = "") -> some View {
        modifier(NativeDialog(title: title, isPresented: isPresented, message: message))
    }
}
