//
//  GameAccount.swift
//  HuoyingOL
//
//  游戏账号模型
//  每个账号独立管理Cookie、登录状态和游戏配置
//

import Foundation

/// 游戏账号模型
/// 支持最多8个账号，每个账号拥有独立的WebView会话和Cookie存储
struct GameAccount: Identifiable, Codable, Equatable {
    /// 唯一标识符
    let id: UUID
    /// 账号显示名称（用户自定义）
    var name: String
    /// 创建时间
    let createdAt: Date
    /// 最后登录时间
    var lastLoginAt: Date?
    /// QQ昵称（登录后获取）
    var qqNickname: String?
    /// QQ OpenID（用于识别用户身份）
    var qqOpenId: String?
    /// 当前选择的服务器ID
    var serverId: String?
    /// 服务器名称
    var serverName: String?
    /// 是否已登录
    var isLoggedIn: Bool
    /// 序列化的Cookie数据（用于持久化WebView的Cookie）
    var cookieData: Data?
    /// 账号专属设置
    var settings: AccountSettings
    
    /// 账号专属设置
    struct AccountSettings: Codable, Equatable {
        /// 游戏加速倍率（1.0 = 正常速度）
        var speedMultiplier: Double = 1.0
        /// 是否启用自动点击
        var autoClickEnabled: Bool = false
        /// 登录模式：password（密码登录）或 qq（QQ快捷登录）
        var loginMode: LoginMode = .password
    }
    
    /// 登录模式枚举
    enum LoginMode: String, Codable, CaseIterable {
        case password = "password"  // 页内账号密码登录
        case qq = "qq"              // 页内 QQ 扫码，不跳出到手机 QQ
        
        var displayName: String {
            switch self {
            case .password: return "密码登录"
            case .qq: return "扫码登录"
            }
        }
    }
    
    /// 创建新账号
    /// - Parameter name: 账号名称
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.lastLoginAt = nil
        self.qqNickname = nil
        self.qqOpenId = nil
        self.serverId = nil
        self.serverName = nil
        self.isLoggedIn = false
        self.cookieData = nil
        self.settings = AccountSettings()
    }
    
    /// 格式化的创建时间
    var formattedCreatedAt: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: createdAt)
    }
    
    /// 格式化的最后登录时间
    var formattedLastLoginAt: String? {
        guard let lastLoginAt = lastLoginAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: lastLoginAt)
    }
    
    /// 显示标题（优先显示QQ昵称）
    var displayTitle: String {
        if let nickname = qqNickname, !nickname.isEmpty {
            return "\(name) (\(nickname))"
        }
        return name
    }
    
    /// 状态描述文本
    var statusText: String {
        if isLoggedIn {
            if let serverName = serverName {
                return "已登录 - \(serverName)"
            }
            return "已登录"
        }
        return "未登录"
    }
}
