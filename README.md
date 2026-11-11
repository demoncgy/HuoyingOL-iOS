# 火影OL AIR - iOS 启动器

基于WebView的火影OL（Naruto Online）游戏启动器 iOS版本。

## 功能特性

### 🎮 多账号系统
- 支持最多 **8个** 游戏账号
- 每个账号独立的Cookie存储和WebView会话
- 账号间完全隔离，互不干扰

### 🔐 QQ登录集成
- OAuth2.0 QQ登录（AppID: 1103286479）
- 支持 **密码登录** 和 **QQ快捷登录** 两种模式
- 自动处理跨iframe消息传递（qq-return.js）
- URL Scheme回调处理（huoyingairqq://）

### ⚡ 游戏加速
- 速度倍率控制（0.5x ~ 5.0x）
- 覆写 `Date.now`、`performance.now`、`setTimeout`、`setInterval`、`requestAnimationFrame`
- 实时调整，无需重新加载

### 🖱️ 自动点击
- MutationObserver 监听DOM变化
- 自动点击匹配模式的按钮：`close|btn|button|restPK|autoFight|defaultOk|getOut|confirm|sure|^ok$`
- 防重复点击保护

### 🔋 后台保活
- 静音音频播放保持后台运行
- 后台任务调度
- 防止系统断开WebSocket连接

## 系统要求

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

## 构建步骤

### 1. 克隆项目
```bash
git clone <repository-url>
cd HuoyingOL-iOS
```

### 2. 打开Xcode项目
```bash
open HuoyingOL.xcodeproj
```

### 3. 配置签名
1. 在Xcode中选择 `HuoyingOL` target
2. 进入 **Signing & Capabilities** 标签
3. 选择你的开发团队
4. 确保Bundle Identifier唯一（如 `com.yourname.huoyingol`）

### 4. 构建和运行
1. 选择目标设备（iPhone或模拟器）
2. 按 `Cmd + R` 构建并运行
3. 首次运行时可能需要在设备上信任开发者证书

## 项目结构

```
HuoyingOL-iOS/
├── HuoyingOL/
│   ├── App/
│   │   ├── HuoyingOLApp.swift          # 应用入口，URL Scheme处理
│   │   └── Info.plist                   # 应用配置
│   ├── Models/
│   │   ├── GameAccount.swift            # 游戏账号模型
│   │   └── AppSettings.swift            # 全局设置
│   ├── ViewModels/
│   │   ├── AccountManager.swift         # 账号管理（最多8个）
│   │   └── GameViewModel.swift          # 游戏WebView状态管理
│   ├── Views/
│   │   ├── AccountListView.swift        # 账号列表主界面
│   │   ├── GameWebView.swift            # WKWebView封装（核心）
│   │   ├── GameContainerView.swift      # 全屏游戏+控制面板
│   │   └── SettingsView.swift           # 设置界面
│   ├── Services/
│   │   ├── QQLoginService.swift         # QQ OAuth服务
│   │   ├── SpeedController.swift        # 速度控制JS注入
│   │   ├── AutoClickService.swift       # 自动点击JS注入
│   │   └── BackgroundKeepAlive.swift    # 后台保活
│   └── Resources/
│       ├── qq-return.js                 # QQ登录消息桥接脚本
│       └── Assets.xcassets/             # 资源目录
├── HuoyingOL.xcodeproj/
│   └── project.pbxproj                  # Xcode项目文件
└── README.md                            # 本文件
```

## 关键技术细节

### WebView配置
- **UserAgent**: 在默认UA基础上追加 `HuoyingAIR/0.2`
- **Cookie隔离**: 每个账号使用独立的 `WKWebsiteDataStore.nonPersistent()`
- **脚本注入**: qq-return.js 在 `atDocumentStart` 时机注入到所有frame

### QQ登录流程
1. 打开游戏主页 `https://huoying.qq.com/server/website/`
2. qq-return.js 劫持登录流程
3. 用户选择密码登录或QQ快捷登录
4. QQ OAuth认证完成后通过 `huoyingairqq://login` 回调
5. 应用截获回调，通过 `window.airQqReturn.accept()` 传递给WebView
6. qq-return.js 处理跨iframe消息传递完成登录

### 安全说明
- 所有通信使用HTTPS
- Cookie通过 `NSKeyedArchiver` 序列化后存储在 UserDefaults
- OAuth state参数防止CSRF攻击
- URL Scheme验证防止恶意回调

## 许可证

本项目仅供学习和个人使用。火影OL是腾讯游戏的产品。
