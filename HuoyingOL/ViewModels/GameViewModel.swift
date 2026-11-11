//
//  GameViewModel.swift
//  HuoyingOL
//
//  游戏视图模型
//  管理单个账号的WebView状态、QQ登录流程、速度控制和自动点击
//

import Foundation
import WebKit
import Combine

/// 游戏视图模型
/// 每个账号对应一个GameViewModel实例，管理WebView的完整生命周期
class GameViewModel: ObservableObject {
    // MARK: - 属性
    
    /// 关联的游戏账号
    @Published var account: GameAccount
    /// 页面加载进度 (0.0 - 1.0)
    @Published var loadingProgress: Double = 0.0
    /// 是否正在加载
    @Published var isLoading: Bool = false
    /// 当前页面标题
    @Published var pageTitle: String = ""
    /// 当前URL
    @Published var currentURL: String = ""
    /// 错误信息
    @Published var errorMessage: String?
    /// 是否显示登录页面
    @Published var isShowingLogin: Bool = false
    /// 速度倍率
    @Published var speedMultiplier: Double = 1.0 {
        didSet {
            account.settings.speedMultiplier = speedMultiplier
            applySpeedControl()
        }
    }
    /// 自动点击开关
    @Published var autoClickEnabled: Bool = false {
        didSet {
            account.settings.autoClickEnabled = autoClickEnabled
            applyAutoClick()
        }
    }
    /// 当前登录模式
    @Published var loginMode: GameAccount.LoginMode = .password
    
    /// WebView引用（由GameWebView设置）
    weak var webView: WKWebView?
    
    /// 账号管理器引用
    weak var accountManager: AccountManager?
    
    /// QQ登录服务
    let qqLoginService = QQLoginService()
    
    /// 速度控制服务
    let speedController = SpeedController()
    
    /// 自动点击服务
    let autoClickService = AutoClickService()
    
    /// 后台保活服务
    let backgroundKeepAlive = BackgroundKeepAlive()
    
    /// 取消订阅集合
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 初始化
    
    init(account: GameAccount) {
        self.account = account
        self.speedMultiplier = account.settings.speedMultiplier
        self.autoClickEnabled = account.settings.autoClickEnabled
        self.loginMode = account.settings.loginMode
        
        setupNotifications()
    }
    
    deinit {
        cancellables.forEach { $0.cancel() }
    }
    
    // MARK: - 通知处理
    
    /// 设置通知监听
    private func setupNotifications() {
        // 监听QQ登录回调
        NotificationCenter.default.publisher(for: .qqLoginCallback)
            .sink { [weak self] notification in
                guard let url = notification.userInfo?["url"] as? URL else { return }
                self?.handleQQCallback(url: url)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 页面加载
    
    /// 加载游戏主页
    func loadGamePage() {
        guard let url = URL(string: AppSettings.gameHomeURL) else { return }
        let request = URLRequest(url: url)
        webView?.load(request)
    }
    
    /// 重新加载当前页面
    func reload() {
        webView?.reload()
    }
    
    /// 返回上一页
    func goBack() {
        webView?.goBack()
    }
    
    // MARK: - QQ登录
    
    /// 开始QQ登录流程
    /// - Parameter mode: 登录模式（密码或QQ快捷登录）
    func startQQLogin(mode: GameAccount.LoginMode) {
        loginMode = mode
        account.settings.loginMode = mode
        // 只在拉起登录页之前换成桌面 UA，让 graph/ptlogin 走页内 PC 登录。
        // 进游戏的主框架导航会在决策回调里改回手机 UA。
        webView?.customUserAgent = AppSettings.desktopWebUserAgent
        
        // 通过JavaScript调用qq-return.js的mode方法
        let modeString = mode.rawValue
        let js = "window.airQqReturn && window.airQqReturn.mode('\(modeString)');"
        webView?.evaluateJavaScript(js) { [weak self] _, error in
            if let error = error {
                print("❌ 设置登录模式失败: \(error.localizedDescription)")
            } else {
                print("✅ 已设置登录模式: \(modeString)")
            }
        }
    }
    
    /// 处理 QQ 回到本应用后的 URL，把 ptlogin jump 交回登录 iframe 完成 OAuth。
    func handleQQCallback(url: URL) {
        print("📱 收到QQ回调: \(url.absoluteString)")

        guard let jumpURL = qqLoginService.jumpURL(from: url) else {
            errorMessage = "QQ 已返回，但没有可继续的登录地址。请再试一次快捷登录。"
            return
        }

        let literal = Self.jsQuoted(jumpURL.absoluteString)
        let js = #"""
        (function(){
          var url = \#(literal);
          if (window.airQqReturn && typeof window.airQqReturn.accept === 'function') {
            window.airQqReturn.accept(url);
            return;
          }
          if (/ptlogin2\.qq\.com$/.test(location.hostname)) location.replace(url);
        })();
        """#
        webView?.evaluateJavaScript(js) { _, error in
            if let error = error {
                print("❌ 传递QQ回调失败: \(error.localizedDescription)")
            }
        }
    }

    private static func jsQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        return "'\(escaped)'"
    }
    
    // MARK: - 速度控制
    
    /// 应用速度控制到WebView
    func applySpeedControl() {
        guard let webView = webView else { return }
        let js = speedController.generateSpeedScript(multiplier: speedMultiplier)
        webView.evaluateJavaScript(js) { _, error in
            if let error = error {
                print("❌ 应用速度控制失败: \(error.localizedDescription)")
            } else {
                print("⚡ 速度已设置为 \(self.speedMultiplier)x")
            }
        }
        
        // 同步到账号管理器
        accountManager?.updateSpeed(id: account.id, speed: speedMultiplier)
    }
    
    // MARK: - 自动点击
    
    /// 应用自动点击到WebView
    func applyAutoClick() {
        guard let webView = webView else { return }
        
        if autoClickEnabled {
            let js = autoClickService.generateAutoClickScript()
            webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    print("❌ 启用自动点击失败: \(error.localizedDescription)")
                } else {
                    print("🖱️ 自动点击已启用")
                }
            }
        } else {
            let js = autoClickService.generateDisableScript()
            webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    print("❌ 禁用自动点击失败: \(error.localizedDescription)")
                } else {
                    print("🖱️ 自动点击已禁用")
                }
            }
        }
        
        // 同步到账号管理器
        accountManager?.updateAutoClick(id: account.id, enabled: autoClickEnabled)
    }
    
    // MARK: - 后台保活
    
    /// 启用后台保活
    func enableBackgroundKeepAlive() {
        backgroundKeepAlive.start()
    }
    
    /// 禁用后台保活
    func disableBackgroundKeepAlive() {
        backgroundKeepAlive.stop()
    }
    
    // MARK: - Cookie管理
    
    /// 保存当前WebView的Cookie
    func saveCookies() {
        guard let webView = webView else { return }
        let dataStore = webView.configuration.websiteDataStore
        
        dataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            
            // 将Cookie序列化为Data
            let cookieProperties = cookies.compactMap { $0.properties }
            do {
                let data = try NSKeyedArchiver.archivedData(
                    withRootObject: cookieProperties,
                    requiringSecureCoding: false
                )
                self.accountManager?.saveCookieData(id: self.account.id, cookieData: data)
                print("🍪 已保存 \(cookies.count) 个Cookie")
            } catch {
                print("❌ 序列化Cookie失败: \(error.localizedDescription)")
            }
        }
    }
    
    /// 恢复Cookie到WebView
    func restoreCookies() {
        guard let webView = webView,
              let cookieData = account.cookieData else { return }
        
        do {
            guard let cookieProperties = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSArray.self,
                from: cookieData
            ) as? [[HTTPCookiePropertyKey: Any]] else { return }
            
            let cookies = cookieProperties.compactMap { HTTPCookie(properties: $0) }
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            
            for cookie in cookies {
                cookieStore.setCookie(cookie)
            }
            print("🍪 已恢复 \(cookies.count) 个Cookie")
        } catch {
            print("❌ 反序列化Cookie失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 页面状态更新
    
    /// 更新加载进度
    func updateProgress(_ progress: Double) {
        loadingProgress = progress
    }
    
    /// 更新加载状态
    func updateLoadingState(_ isLoading: Bool) {
        self.isLoading = isLoading
    }
    
    /// 更新页面标题
    func updateTitle(_ title: String?) {
        pageTitle = title ?? ""
    }
    
    /// 更新当前URL
    func updateURL(_ url: URL?) {
        currentURL = url?.absoluteString ?? ""
        
        // 检测是否在登录页面
        if let urlString = url?.absoluteString {
            isShowingLogin = urlString.contains("ptlogin2.qq.com") ||
                            urlString.contains("graph.qq.com/oauth2.0")
        }
    }
    
    /// 页面加载完成后的处理
    func onPageFinishLoad() {
        // 如果启用了速度控制，重新注入
        if speedMultiplier != 1.0 {
            applySpeedControl()
        }
        
        // 如果启用了自动点击，重新注入
        if autoClickEnabled {
            applyAutoClick()
        }
        
        // 保存Cookie
        saveCookies()
    }
}
