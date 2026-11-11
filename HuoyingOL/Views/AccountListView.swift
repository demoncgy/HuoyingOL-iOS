//
//  AccountListView.swift
//  HuoyingOL
//
//  账号列表视图
//  主界面，显示所有游戏账号，支持添加/删除/启动游戏
//

import SwiftUI

/// 账号列表视图
/// 应用启动后的主界面，展示所有已添加的游戏账号
struct AccountListView: View {
    @EnvironmentObject var accountManager: AccountManager
    @EnvironmentObject var appSettings: AppSettings
    
    /// 是否显示添加账号对话框
    @State private var showingAddAccount = false
    /// 新账号名称输入
    @State private var newAccountName = ""
    /// 是否显示设置页面
    @State private var showingSettings = false
    /// 当前选中启动的账号（用于全屏游戏导航）
    @State private var launchingAccount: GameAccount?
    /// 是否显示删除确认
    @State private var accountToDelete: GameAccount?
    /// 是否显示重命名对话框
    @State private var accountToRename: GameAccount?
    @State private var renameText = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景渐变
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.15),
                        Color(red: 0.1, green: 0.05, blue: 0.2)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // 顶部标题栏
                    headerView
                    
                    if accountManager.accounts.isEmpty {
                        // 空状态提示
                        emptyStateView
                    } else {
                        // 账号列表
                        accountListContent
                    }
                }
            }
            .navigationBarHidden(true)
            .fullScreenCover(item: $launchingAccount) { account in
                GameContainerView(account: account)
                    .ignoresSafeArea()
                    .environmentObject(accountManager)
                    .environmentObject(appSettings)
            }
            .alert("添加账号", isPresented: $showingAddAccount) {
                TextField("账号名称（如：主号、小号）", text: $newAccountName)
                Button("取消", role: .cancel) {
                    newAccountName = ""
                }
                Button("添加") {
                    addAccount()
                }
            } message: {
                Text("最多支持\(AppSettings.maxAccounts)个账号")
            }
            .alert("重命名账号", isPresented: Binding(
                get: { accountToRename != nil },
                set: { if !$0 { accountToRename = nil } }
            )) {
                TextField("新名称", text: $renameText)
                Button("取消", role: .cancel) {
                    accountToRename = nil
                    renameText = ""
                }
                Button("确定") {
                    if let account = accountToRename {
                        accountManager.renameAccount(id: account.id, newName: renameText)
                    }
                    accountToRename = nil
                    renameText = ""
                }
            }
            .alert("确认删除", isPresented: Binding(
                get: { accountToDelete != nil },
                set: { if !$0 { accountToDelete = nil } }
            )) {
                Button("取消", role: .cancel) {
                    accountToDelete = nil
                }
                Button("删除", role: .destructive) {
                    if let account = accountToDelete {
                        accountManager.removeAccount(id: account.id)
                    }
                    accountToDelete = nil
                }
            } message: {
                Text("删除账号「\(accountToDelete?.name ?? "")」？此操作不可撤销。")
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(appSettings)
            }
        }
    }
    
    // MARK: - 子视图
    
    /// 顶部标题栏
    private var headerView: some View {
        HStack {
            // 应用标题
            VStack(alignment: .leading, spacing: 2) {
                Text("火影OL")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text("AIR 启动器")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // 账号计数
            Text("\(accountManager.accounts.count)/\(AppSettings.maxAccounts)")
                .font(.subheadline)
                .foregroundColor(.gray)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                )
            
            // 添加账号按钮
            Button(action: {
                newAccountName = "账号\(accountManager.accounts.count + 1)"
                showingAddAccount = true
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(accountManager.isAtMaxCapacity ? .gray : .orange)
            }
            .disabled(accountManager.isAtMaxCapacity)
            
            // 设置按钮
            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.3))
    }
    
    /// 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.orange.opacity(0.5))
            Text("还没有游戏账号")
                .font(.title2)
                .foregroundColor(.white)
            Text("点击右上角 + 添加一个账号开始游戏")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            Button(action: {
                newAccountName = "账号1"
                showingAddAccount = true
            }) {
                HStack {
                    Image(systemName: "plus")
                    Text("添加第一个账号")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange)
                )
            }
            Spacer()
        }
    }
    
    /// 账号列表内容
    private var accountListContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(accountManager.accounts) { account in
                    accountCard(for: account)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(maxHeight: .infinity)
    }
    
    /// 单个账号卡片
    private func accountCard(for account: GameAccount) -> some View {
        VStack(spacing: 12) {
            // 头像区域
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 70, height: 70)
                
                Text(String(account.name.prefix(1)))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                // 在线状态指示器
                if account.isLoggedIn {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle().stroke(Color.black, lineWidth: 2)
                        )
                        .offset(x: 25, y: 25)
                }
            }
            
            // 账号名称
            Text(account.displayTitle)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
            
            // 状态信息
            Text(account.statusText)
                .font(.caption)
                .foregroundColor(account.isLoggedIn ? .green : .gray)
            
            // 上次登录时间
            if let lastLogin = account.formattedLastLoginAt {
                Text("上次: \(lastLogin)")
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.7))
            }
            
            Spacer()
            
            // 操作按钮
            VStack(spacing: 8) {
                // 启动游戏按钮
                Button(action: {
                    launchingAccount = account
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("启动")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange)
                    )
                }
                
                // 管理按钮行
                HStack(spacing: 8) {
                    // 重命名
                    Button(action: {
                        renameText = account.name
                        accountToRename = account
                    }) {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.1))
                            )
                    }
                    
                    // 删除
                    Button(action: {
                        accountToDelete = account
                    }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.red.opacity(0.1))
                            )
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 180, height: 300)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            accountManager.activeAccountId == account.id
                                ? Color.orange.opacity(0.5)
                                : Color.white.opacity(0.1),
                            lineWidth: 1
                        )
                )
        )
    }
    
    // MARK: - 操作方法
    
    /// 添加新账号
    private func addAccount() {
        let name = newAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        accountManager.addAccount(name: name)
        newAccountName = ""
    }
}

#Preview {
    AccountListView()
        .environmentObject(AccountManager())
        .environmentObject(AppSettings())
}
