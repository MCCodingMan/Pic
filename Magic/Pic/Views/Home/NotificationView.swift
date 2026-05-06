import SwiftUI

struct NotificationView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var scheme
    
    var body: some View {
        NavigationStack {
            VStack {
                if true { // 暂无通知的占位状态
                    ContentUnavailableView(
                        "暂无消息",
                        systemImage: "bell.slash",
                        description: Text("当有新功能或活动时，我们会通知您")
                    )
                }
            }
            .navigationTitle("消息中心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
