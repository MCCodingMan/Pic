import SwiftUI
internal import AVFoundation

struct MainTabView: View {
    @State private var selectedTab: Tab = .home
    @State private var isPicCameraPresented = false
    @State private var isShowingCameraDeniedAlert = false
    @Environment(\.colorScheme) var scheme

    enum Tab {
        case home
        case album
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    if selectedTab == .home {
                        HomeView()
                    } else {
                        AlbumView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Custom TabBar
                HStack(spacing: 32) {
                    Button(action: { selectedTab = .home }) {
                        Image(systemName: selectedTab == .home ? "house.fill" : "house")
                            .font(.system(size: 22))
                            .foregroundColor(selectedTab == .home ? DS.ColorToken.brandPrimary(scheme) : DS.ColorToken.textSecondary(scheme))
                    }

                    Button {
                        Task { await handleCameraTap() }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(DS.ColorToken.brandPrimary(scheme))
                                .frame(width: 40, height: 40)
                                .shadow(color: DS.ColorToken.brandPrimary(scheme).opacity(0.4), radius: 6, x: 0, y: 4)
                            Image(systemName: "camera.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }

                    Button(action: { selectedTab = .album }) {
                        Image(systemName: selectedTab == .album ? "photo.on.rectangle.fill" : "photo.on.rectangle")
                            .font(.system(size: 22))
                            .foregroundColor(selectedTab == .album ? DS.ColorToken.brandPrimary(scheme) : DS.ColorToken.textSecondary(scheme))
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 30)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                )
                .padding(.bottom, 10)
            }
            .fullScreenCover(isPresented: $isPicCameraPresented) {
                PicCameraView()
            }
            .alert("需要相机权限", isPresented: $isShowingCameraDeniedAlert) {
                Button("取消", role: .cancel) {}
                Button("去设置") {
                    openAppSettings()
                }
            } message: {
                Text("请先允许访问相机。")
            }
        }
    }

    private func handleCameraTap() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isPicCameraPresented = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                isPicCameraPresented = true
            } else {
                isShowingCameraDeniedAlert = true
            }
        case .denied, .restricted:
            isShowingCameraDeniedAlert = true
        @unknown default:
            isShowingCameraDeniedAlert = true
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
