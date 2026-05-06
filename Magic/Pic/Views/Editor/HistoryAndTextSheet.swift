import SwiftUI

struct HistoryView: View {
    let undoStack: [EditState]
    let currentState: EditState
    let redoStack: [EditState]
    let onJump: (Int) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("重做")) {
                    ForEach(redoStack.reversed()) { state in
                        Text(state.description)
                            .foregroundColor(.gray)
                    }
                }
                
                Section(header: Text("当前")) {
                    HStack {
                        Text(currentState.description)
                            .fontWeight(.bold)
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
                
                Section(header: Text("历史")) {
                    ForEach(Array(undoStack.enumerated()).reversed(), id: \.element.id) { index, state in
                        Button(action: {
                            onJump(index)
                            onDismiss()
                        }) {
                            Text(state.description)
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .navigationTitle("编辑历史")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { onDismiss() }
                }
            }
        }
    }
}

struct TextEditorSheet: View {
    @Binding var text: String
    @Binding var color: Color
    @Binding var fontName: String
    let onCommit: () -> Void
    let onCancel: () -> Void
    
    let fonts = ["System", "Helvetica", "Courier", "Times New Roman", "Chalkboard SE"]
    let colors: [Color] = [.black, .white, .red, .blue, .green, .yellow, .orange, .purple, .pink]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("输入文字...", text: $text)
                    .font(.system(size: 24))
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                
                // Color Picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(colors, id: \.self) { c in
                            Circle()
                                .fill(c)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .stroke(Color.gray, lineWidth: color == c ? 3 : 1)
                                )
                                .onTapGesture {
                                    color = c
                                }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Font Picker
                List {
                    ForEach(fonts, id: \.self) { font in
                        Button(action: { fontName = font }) {
                            HStack {
                                Text(font)
                                    .font(.custom(font == "System" ? ".AppleSystemUIFont" : font, size: 18))
                                Spacer()
                                if fontName == font {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
                
                Spacer()
            }
            .padding(.top)
            .navigationTitle("添加文字")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        if !text.isEmpty {
                            onCommit()
                        }
                    }
                    .disabled(text.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
