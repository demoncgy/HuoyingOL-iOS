//
//  AppSettings.swift
//  HuoyingOL
//
//  全局应用设置
//  管理速度倍率、自动点击等全局配置
//

import Foundation
import Combine

/// 全局应用设置
/// 使用 @AppStorage 进行持久化，通过 ObservableObject 通知UI更新
class AppSettings: ObservableObject {
    // MARK: - 常量
    
    /// 最大账号数量
    static let maxAccounts = 8
    /// 最小速度倍率
    static let minSpeed: Double = 0.5
    /// 最大速度倍率
    static let maxSpeed: Double = 5.0
    /// 默认速度倍率
    static let defaultSpeed: Double = 1.0
    /// 旧版 QQ AppID（tencent scheme 仍需注册）
    static let qqAppId = "1103286479"
    /// 官网当前 QQ 互联 AppID（qqConnectConfig.js 的 qcAppid）
    static let qqConnectAppId = "102045649"
    /// 自定义UserAgent
    static let customUserAgent = "HuoyingAIR/0.2"
    /// 选区页和游戏客户端用手机 UA。桌面 Safari 不是 Chrome，narutoweb.js 会弹出 Flash 安装提示。
    static let mobileWebUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 \(customUserAgent)"
    /// 只给 QQ 登录页（graph / ptlogin）。手机 UA 会进 style=35，回调缺少 s_url。
    static let desktopWebUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15 \(customUserAgent)"

    /// 主框架进游戏或回选区时用手机 UA；登录域用桌面 UA。
    static func userAgent(forMainFrame url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        if host == "graph.qq.com" || host == "connect.qq.com" || host.contains("ptlogin2.qq.com") {
            return desktopWebUserAgent
        }
        return mobileWebUserAgent
    }
    /// 游戏主页URL
    static let gameHomeURL = "https://huoying.qq.com/server/website/"
    /// 游戏服务器URL
    static let gameServerURL = "https://game.huoying.qq.com"
    /// 资源CDN URL
    static let resourceCDN = "https://res.huoying.qq.com/"
    /// QQ OAuth URL
    static let qqOAuthURL = "https://graph.qq.com/oauth2.0/authorize"
    /// QQ登录页面URL
    static let qqLoginURL = "https://xui.ptlogin2.qq.com/cgi-bin/xlogin?daid=207&target=self&appid=7000201"
    /// 小游戏入口URL
    static let miniGameURL = "https://minigame.qq.com/plat/social_hall/app_frame/index_v4.html?appid=1103286479"
    /// QQ回调Scheme
    static let qqCallbackScheme = "huoyingairqq"
    
    // MARK: - 持久化设置
    
    /// 全局默认速度倍率
    @Published var defaultSpeedMultiplier: Double {
        didSet {
            UserDefaults.standard.set(defaultSpeedMultiplier, forKey: "defaultSpeedMultiplier")
        }
    }
    
    /// 全局默认自动点击开关
    @Published var defaultAutoClickEnabled: Bool {
        didSet {
            UserDefaults.standard.set(defaultAutoClickEnabled, forKey: "defaultAutoClickEnabled")
        }
    }
    
    /// 默认登录模式
    @Published var defaultLoginMode: GameAccount.LoginMode {
        didSet {
            UserDefaults.standard.set(defaultLoginMode.rawValue, forKey: "defaultLoginMode")
        }
    }
    
    /// 是否启用后台保活
    @Published var backgroundKeepAlive: Bool {
        didSet {
            UserDefaults.standard.set(backgroundKeepAlive, forKey: "backgroundKeepAlive")
        }
    }
    
    /// 是否显示调试信息
    @Published var showDebugInfo: Bool {
        didSet {
            UserDefaults.standard.set(showDebugInfo, forKey: "showDebugInfo")
        }
    }
    
    // MARK: - 初始化
    
    init() {
        let defaults = UserDefaults.standard
        
        // 读取已保存的设置，如果没有则使用默认值
        let savedSpeed = defaults.double(forKey: "defaultSpeedMultiplier")
        self.defaultSpeedMultiplier = savedSpeed > 0 ? savedSpeed : AppSettings.defaultSpeed
        
        self.defaultAutoClickEnabled = defaults.bool(forKey: "defaultAutoClickEnabled")
        
        let savedMode = defaults.string(forKey: "defaultLoginMode") ?? "password"
        self.defaultLoginMode = GameAccount.LoginMode(rawValue: savedMode) ?? .password
        
        self.backgroundKeepAlive = defaults.bool(forKey: "backgroundKeepAlive")
        self.showDebugInfo = defaults.bool(forKey: "showDebugInfo")
    }
    
    /// 重置所有设置为默认值
    func resetToDefaults() {
        defaultSpeedMultiplier = AppSettings.defaultSpeed
        defaultAutoClickEnabled = false
        defaultLoginMode = .password
        backgroundKeepAlive = false
        showDebugInfo = false
    }
}
