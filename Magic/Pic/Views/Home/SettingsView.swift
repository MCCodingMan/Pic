import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var scheme
    
    var body: some View {
        NavigationStack {
            List {
                Section("通用") {
                    HStack {
                        Text("导出质量")
                        Spacer()
                        Text("高清").foregroundColor(.secondary)
                    }
                    Toggle("保存原图", isOn: .constant(true))
                }
                
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0").foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
