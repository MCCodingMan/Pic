//
//  UIApplication+SafeArea.swift
//  Magic
//
//  Created by CoderWan on 2024/12/11.
//

import UIKit

/// 应用级全局工具命名空间。
/// 统一封装系统 API 访问入口, 便于替换被弃用的全局符号 (如 iOS 26 起弃用的 `UIScreen.main`)。
enum SwiftApp {
    static var safeAreaInsets: UIEdgeInsets {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: { $0.isKeyWindow })
        else {
            return .zero
        }
        return window.safeAreaInsets
        
    }
    
    // MARK: - Screen
    
    /// 当前活动的 `UIScreen` (来自 foreground active 的 windowScene)。
    static var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .screen
        ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .screen
    }
    
    /// 屏幕尺寸 (points)。
    static var screenBounds: CGRect {
        screen?.bounds ?? .zero
    }
    
    /// 屏幕宽度 (points)。
    static var screenWidth: CGFloat {
        screenBounds.width
    }
    
    /// 屏幕高度 (points)。
    static var screenHeight: CGFloat {
        screenBounds.height
    }
    
    /// 屏幕像素密度。
    static var screenScale: CGFloat {
        screen?.scale ?? 2.0
    }
}
