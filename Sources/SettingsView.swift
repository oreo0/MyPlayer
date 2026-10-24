import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("界面与歌词") {
                Text("外观、主题色、背景效果和歌词设置已移至菜单栏的“显示”菜单。")
                Text("底栏固定开关也可在“显示”菜单中切换。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 180)
    }
}
