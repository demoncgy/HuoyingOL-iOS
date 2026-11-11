//
//  AccountManager.swift
//  HuoyingOL
//
//  账号管理器
//  管理最多8个游戏账号，使用UserDefaults持久化
//

import Foundation
import Combine

/// 账号管理器
/// 负责账号的增删改查和持久化存储
class AccountManager: ObservableObject {
    // MARK: - 属性
    
    /// 所有游戏账号列表
    @Published var accounts: [GameAccount] = []
    
    /// 当前活跃的账号ID
    @Published var activeAccountId: UUID?
    
    /// UserDefaults存储键
    private let accountsKey = "gameAccounts"
    private let activeAccountKey = "activeAccountId"
    
    /// 是否已达到最大账号数
    var isAtMaxCapacity: Bool {
        accounts.count >= AppSettings.maxAccounts
    }
    
    /// 当前活跃账号
    var activeAccount: GameAccount? {
        guard let id = activeAccountId else { return nil }
        return accounts.first { $0.id == id }
    }
    
    // MARK: - 初始化
    
    init() {
        loadAccounts()
    }
    
    // MARK: - 账号操作
    
    /// 添加新账号
    /// - Parameter name: 账号名称
    /// - Returns: 新创建的账号，如果已满则返回nil
    @discardableResult
    func addAccount(name: String) -> GameAccount? {
        guard !isAtMaxCapacity else {
            print("⚠️ 已达到最大账号数量限制(\(AppSettings.maxAccounts))")
            return nil
        }
        
        var account = GameAccount(name: name)
        // 如果是第一个账号，自动设为活跃账号
        if accounts.isEmpty {
            activeAccountId = account.id
        }
        
        accounts.append(account)
        saveAccounts()
        return account
    }
    
    /// 删除账号
    /// - Parameter id: 要删除的账号ID
    func removeAccount(id: UUID) {
        accounts.removeAll { $0.id == id }
        
        // 如果删除的是活跃账号，切换到第一个账号
        if activeAccountId == id {
            activeAccountId = accounts.first?.id
        }
        
        saveAccounts()
    }
    
    /// 更新账号信息
    /// - Parameter account: 更新后的账号对象
    func updateAccount(_ account: GameAccount) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        saveAccounts()
    }
    
    /// 设置活跃账号
    /// - Parameter id: 账号ID
    func setActiveAccount(id: UUID) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        activeAccountId = id
        UserDefaults.standard.set(id.uuidString, forKey: activeAccountKey)
    }
    
    /// 重命名账号
    /// - Parameters:
    ///   - id: 账号ID
    ///   - newName: 新名称
    func renameAccount(id: UUID, newName: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].name = newName
        saveAccounts()
    }
    
    /// 更新账号登录状态
    /// - Parameters:
    ///   - id: 账号ID
    ///   - isLoggedIn: 是否已登录
    ///   - qqNickname: QQ昵称
    ///   - qqOpenId: QQ OpenID
    func updateLoginStatus(id: UUID, isLoggedIn: Bool, qqNickname: String? = nil, qqOpenId: String? = nil) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].isLoggedIn = isLoggedIn
        accounts[index].lastLoginAt = isLoggedIn ? Date() : accounts[index].lastLoginAt
        if let nickname = qqNickname {
            accounts[index].qqNickname = nickname
        }
        if let openId = qqOpenId {
            accounts[index].qqOpenId = openId
        }
        saveAccounts()
    }
    
    /// 保存账号的Cookie数据
    /// - Parameters:
    ///   - id: 账号ID
    ///   - cookieData: 序列化的Cookie数据
    func saveCookieData(id: UUID, cookieData: Data?) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].cookieData = cookieData
        saveAccounts()
    }
    
    /// 更新账号的速度设置
    /// - Parameters:
    ///   - id: 账号ID
    ///   - speed: 速度倍率
    func updateSpeed(id: UUID, speed: Double) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].settings.speedMultiplier = speed
        saveAccounts()
    }
    
    /// 更新账号的自动点击设置
    /// - Parameters:
    ///   - id: 账号ID
    ///   - enabled: 是否启用
    func updateAutoClick(id: UUID, enabled: Bool) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].settings.autoClickEnabled = enabled
        saveAccounts()
    }
    
    // MARK: - 持久化
    
    /// 从UserDefaults加载账号数据
    private func loadAccounts() {
        guard let data = UserDefaults.standard.data(forKey: accountsKey) else {
            accounts = []
            return
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            accounts = try decoder.decode([GameAccount].self, from: data)
        } catch {
            print("❌ 加载账号数据失败: \(error.localizedDescription)")
            accounts = []
        }
        
        // 恢复活跃账号
        if let activeIdString = UserDefaults.standard.string(forKey: activeAccountKey),
           let activeId = UUID(uuidString: activeIdString),
           accounts.contains(where: { $0.id == activeId }) {
            activeAccountId = activeId
        } else {
            activeAccountId = accounts.first?.id
        }
    }
    
    /// 保存账号数据到UserDefaults
    private func saveAccounts() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(accounts)
            UserDefaults.standard.set(data, forKey: accountsKey)
        } catch {
            print("❌ 保存账号数据失败: \(error.localizedDescription)")
        }
    }
}
