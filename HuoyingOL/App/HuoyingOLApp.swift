//
//  HuoyingOLApp.swift
//  HuoyingOL
//
//  火影OL AIR 启动器 - iOS版本
//  主应用入口，注册URL Scheme处理器
//

import SwiftUI

@main
struct HuoyingOLApp: App {
    // 账号管理器，全局单例
    @StateObject private var accountManager = AccountManager()
    // 应用设置
    @StateObject private var appSettings = AppSettings()
    
    var body: some Scene {
        WindowGroup {
            AccountListView()
                .environmentObject(accountManager)
                .environmentObject(appSettings)
                .onOpenURL { url in
                    // 处理 huoyingairqq:// URL Scheme 回调
                    handleURLScheme(url)
                }
                // 强制横屏显示
                .statusBarHidden(true)
        }
    }
    
    /// 处理 QQ 登录回调。快捷登录约定回到 huoyingairqq://，部分客户端会用 tencent{appid}://。
    private func handleURLScheme(_ url: URL) {
        guard QQLoginService.isAppCallback(url) else { return }

        NotificationCenter.default.post(
            name: .qqLoginCallback,
            object: nil,
            userInfo: ["url": url]
        )
    }
}

// MARK: - 通知名称扩展
extension Notification.Name {
    /// QQ登录回调通知
    static let qqLoginCallback = Notification.Name("qqLoginCallback")
    /// 游戏速度变更通知
    static let speedMultiplierChanged = Notification.Name("speedMultiplierChanged")
    /// 自动点击状态变更通知
    static let autoClickChanged = Notification.Name("autoClickChanged")
}
