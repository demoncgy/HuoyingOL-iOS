//
//  GameContainerView.swift
//  HuoyingOL
//
//  游戏容器视图
//  全屏游戏界面，包含WebView和浮动控制工具栏
//  提供速度滑块、自动点击开关、账号切换等功能
//

import SwiftUI

/// 游戏容器视图
/// 包装GameWebView并提供浮动控制面板
struct GameContainerView: View {
    let account: GameAccount
    
    @EnvironmentObject var accountManager: AccountManager
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss
    
    /// 游戏视图模型
    @StateObject private var viewModel: GameViewModel
    
    /// 是否显示控制面板
    @State private var showControls = false
    /// 是否显示登录模式选择
    @State private var showLoginModeSelector = false
    /// 控制面板拖拽偏移量
    @State private var controlPanelOffset: CGSize = .zero
    /// 浮动按钮位置
    @State private var floatingButtonPosition: CGPoint = CGPoint(x: 50, y: 50)
    
    init(account: GameAccount) {
        self.account = account
        _viewModel = StateObject(wrappedValue: GameViewModel(account: account))
    }
    
    var body: some View {
        GeometryReader { proxy in
        ZStack {
            Color.black
            // 游戏WebView（贴边，含刘海/灵动岛区域）
            GameWebView(viewModel: viewModel)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .ignoresSafeArea()
            
            // 加载进度条
            if viewModel.isLoading {
                VStack {
                    ProgressView(value: viewModel.loadingProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .orange))
                        .frame(height: 3)
                    Spacer()
                }
            }
            
            // 错误提示
            if let error = viewModel.errorMessage {
                VStack {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.white)
                        Button(action: { viewModel.errorMessage = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.8))
                    )
                    .padding(.top, 8)
                    Spacer()
                }
            }
            
            // 浮动控制按钮（避开刘海，网页本身仍然贴边）
            floatingButton
                .padding(.top, proxy.safeAreaInsets.top)
                .padding(.trailing, proxy.safeAreaInsets.trailing)
                .padding(.leading, proxy.safeAreaInsets.leading)
            
            // 控制面板
            if showControls {
                controlPanel
                    .padding(.top, proxy.safeAreaInsets.top)
                    .padding(.trailing, proxy.safeAreaInsets.trailing)
                    .padding(.leading, proxy.safeAreaInsets.leading)
            }
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            viewModel.accountManager = accountManager
            if appSettings.backgroundKeepAlive {
                viewModel.enableBackgroundKeepAlive()
            }
        }
        .onDisappear {
            viewModel.saveCookies()
            viewModel.disableBackgroundKeepAlive()
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
    }
    
    // MARK: - 浮动按钮
    
    /// 浮动控制按钮（可拖拽）
    private var floatingButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: { withAnimation(.spring()) { showControls.toggle() } }) {
                    Image(systemName: showControls ? "xmark.circle.fill" : "gamecontroller.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Color.orange.opacity(0.8))
                                .shadow(color: .black.opacity(0.3), radius: 4)
                        )
                }
                .padding(.trailing, 16)
                .padding(.top, 16)
            }
            Spacer()
        }
    }
    
    // MARK: - 控制面板
    
    /// 浮动控制面板
    private var controlPanel: some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    // 标题栏
                    HStack {
                        Text("控制面板")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Text(account.name)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    Divider().background(Color.white.opacity(0.3))
                    
                    // 速度控制
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "speedometer")
                                .foregroundColor(.yellow)
                            Text("游戏速度")
                                .font(.subheadline)
                                .foregroundColor(.white)
                            Spacer()
                            Text(String(format: "%.1fx", viewModel.speedMultiplier))
                                .font(.subheadline.monospaced())
                                .foregroundColor(.orange)
                        }
                        
                        Slider(
                            value: $viewModel.speedMultiplier,
                            in: AppSettings.minSpeed...AppSettings.maxSpeed,
                            step: 0.5
                        )
                        .tint(.orange)
                        
                        // 快捷速度按钮
                        HStack(spacing: 8) {
                            ForEach([1.0, 1.5, 2.0, 3.0, 5.0], id: \.self) { speed in
                                Button(action: { viewModel.speedMultiplier = speed }) {
                                    Text("\(speed, specifier: "%.1f")x")
                                        .font(.caption2)
                                        .foregroundColor(
                                            abs(viewModel.speedMultiplier - speed) < 0.01
                                                ? .black : .white
                                        )
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(
                                                    abs(viewModel.speedMultiplier - speed) < 0.01
                                                        ? Color.orange : Color.white.opacity(0.15)
                                                )
                                        )
                                }
                            }
                        }
                    }
                    
                    Divider().background(Color.white.opacity(0.3))
                    
                    // 自动点击开关
                    HStack {
                        Image(systemName: "hand.tap.fill")
                            .foregroundColor(.green)
                        Text("自动点击")
                            .font(.subheadline)
                            .foregroundColor(.white)
                        Spacer()
                        Toggle("", isOn: $viewModel.autoClickEnabled)
                            .tint(.green)
                            .labelsHidden()
                    }
                    
                    Divider().background(Color.white.opacity(0.3))
                    
                    // 登录模式选择
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "person.crop.circle")
                                .foregroundColor(.blue)
                            Text("登录方式")
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        
                        HStack(spacing: 8) {
                            ForEach(GameAccount.LoginMode.allCases, id: \.rawValue) { mode in
                                Button(action: {
                                    viewModel.startQQLogin(mode: mode)
                                }) {
                                    Text(mode.displayName)
                                        .font(.caption)
                                        .foregroundColor(
                                            viewModel.loginMode == mode ? .black : .white
                                        )
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(
                                                    viewModel.loginMode == mode
                                                        ? Color.blue : Color.white.opacity(0.15)
                                                )
                                        )
                                }
                            }
                        }
                    }
                    
                    Divider().background(Color.white.opacity(0.3))
                    
                    // 操作按钮
                    HStack(spacing: 12) {
                        // 刷新
                        Button(action: { viewModel.reload() }) {
                            Label("刷新", systemImage: "arrow.clockwise")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.15))
                                )
                        }
                        
                        // 返回
                        Button(action: { viewModel.goBack() }) {
                            Label("返回", systemImage: "chevron.left")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.15))
                                )
                        }
                        
                        Spacer()
                        
                        // 退出游戏
                        Button(action: { dismiss() }) {
                            Label("退出", systemImage: "xmark.circle")
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.red.opacity(0.15))
                                )
                        }
                    }
                    
                    // 调试信息
                    if appSettings.showDebugInfo {
                        Divider().background(Color.white.opacity(0.3))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("URL: \(viewModel.currentURL)")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                            Text("标题: \(viewModel.pageTitle)")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(16)
                .frame(width: 320)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
                .padding(.trailing, 16)
                .padding(.top, 70)
            }
            Spacer()
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}

#Preview {
    GameContainerView(account: GameAccount(name: "测试账号"))
        .environmentObject(AccountManager())
        .environmentObject(AppSettings())
}
