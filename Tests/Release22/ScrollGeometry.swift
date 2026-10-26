import SwiftUI
import AppKit
@MainActor final class Probe: ObservableObject { var values: [Bool] = [] }
struct ListProbe: View {
let probe: Probe
var body: some View { List(0..<50,id:\.self) {Text("Row \($0)").frame(height:40)}.listStyle(.plain).onScrollGeometryChange(for:Bool.self) {$0.contentOffset.y + $0.contentInsets.top > 1} action: {_,value in probe.values.append(value)} }
}
@main struct Test {
@MainActor static func find(_ view:NSView)->NSScrollView? { if let scroll=view as? NSScrollView{return scroll};return view.subviews.compactMap{find($0)}.first }
@MainActor static func main() async throws {NSApplication.shared.setActivationPolicy(.prohibited);let probe=Probe(),host=NSHostingView(rootView:ListProbe(probe:probe));let window=NSWindow(contentRect:.init(x:0,y:0,width:400,height:500),styleMask:[.titled],backing:.buffered,defer:false);window.contentView=host;host.layoutSubtreeIfNeeded();try await Task.sleep(for:.milliseconds(200));let scroll=find(host)!;precondition(probe.values == [false]);scroll.contentView.scroll(to:.init(x:0,y:100));scroll.reflectScrolledClipView(scroll.contentView);try await Task.sleep(for:.milliseconds(250));precondition(probe.values == [false, true]);scroll.contentView.scroll(to:.init(x:0,y:0));scroll.reflectScrolledClipView(scroll.contentView);try await Task.sleep(for:.milliseconds(150));precondition(probe.values == [false,true,false]);print("PASS: native List scroll geometry crosses and resets the queue fade threshold")}
}
