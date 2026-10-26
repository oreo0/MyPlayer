import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("界面与歌词") {
                Text("外观和背景效果可在“外观”菜单调整，歌词设置位于“歌词”菜单。主题色自动跟随封面。")
                Text("底栏固定开关也可在“外观”菜单中切换。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 180)
    }
}
