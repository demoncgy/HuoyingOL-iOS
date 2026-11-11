//
//  SettingsView.swift
//  HuoyingOL
//
//  全局设置视图
//  配置默认速度倍率、自动点击、默认登录方式、后台保活、版本信息及重置选项
//

import SwiftUI
import WebKit

/// 全局设置面板视图
struct SettingsView: View {
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss
    
    @State private var showResetAlert = false
    @State private var showClearCacheAlert = false
    @State private var cacheClearedNotice = false
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - 游戏体验设置
                Section("游戏体验默认配置") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("默认游戏速度", systemImage: "speedometer")
                            Spacer()
                            Text(String(format: "%.1fx", appSettings.defaultSpeedMultiplier))
                                .font(.subheadline.monospaced())
                                .foregroundColor(.orange)
                        }
                        
                        Slider(
                            value: $appSettings.defaultSpeedMultiplier,
                            in: AppSettings.minSpeed...AppSettings.maxSpeed,
                            step: 0.5
                        )
                        .tint(.orange)
                        
                        HStack {
                            Text("0.5x")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Spacer()
                            Text("1.0x (原速)")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Spacer()
                            Text("5.0x")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Toggle(isOn: $appSettings.defaultAutoClickEnabled) {
                        Label("默认开启自动点击", systemImage: "hand.tap.fill")
                    }
                    .tint(.orange)
                    
                    Picker(selection: $appSettings.defaultLoginMode) {
                        ForEach(GameAccount.LoginMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    } label: {
                        Label("默认登录方式", systemImage: "person.badge.key.fill")
                    }
                }
                
                // MARK: - 系统与后台
                Section("系统与保活") {
                    Toggle(isOn: $appSettings.backgroundKeepAlive) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("后台网络保活")
                                .font(.body)
                            Text("切换到后台时保持游戏WebSocket和网络连接")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .tint(.orange)
                    
                    Toggle(isOn: $appSettings.showDebugInfo) {
                        Label("显示调试信息与URL", systemImage: "ant.fill")
                    }
                    .tint(.orange)
                }
                
                // MARK: - 缓存与数据管理
                Section("数据管理") {
                    Button(role: .destructive) {
                        showClearCacheAlert = true
                    } label: {
                        Label("清理网页缓存与临时数据", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                    
                    Button("恢复默认设置") {
                        showResetAlert = true
                    }
                    .foregroundColor(.orange)
                }
                
                // MARK: - 关于与协议
                Section("关于火影OL AIR 启动器") {
                    HStack {
                        Text("版本号")
                        Spacer()
                        Text("2.2.0 (AIR 移植版)")
                            .foregroundColor(.gray)
                    }
                    
                    HStack {
                        Text("QQ互联 AppID")
                        Spacer()
                        Text(AppSettings.qqAppId)
                            .foregroundColor(.gray)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    HStack {
                        Text("User-Agent 标志")
                        Spacer()
                        Text(AppSettings.customUserAgent)
                            .foregroundColor(.gray)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    HStack {
                        Text("支持账号上限")
                        Spacer()
                        Text("\(AppSettings.maxAccounts) 个独立进程/实例")
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                }
            }
            .alert("确认重置所有设置？", isPresented: $showResetAlert) {
                Button("取消", role: .cancel) { }
                Button("重置", role: .destructive) {
                    appSettings.resetToDefaults()
                }
            } message: {
                Text("此操作会将速度倍率、自动点击等全局偏好恢复为初始状态。")
            }
            .alert("确认清理网页缓存？", isPresented: $showClearCacheAlert) {
                Button("取消", role: .cancel) { }
                Button("清理", role: .destructive) {
                    clearWebCache()
                }
            } message: {
                Text("将清除本地存储的所有网页资源和临时缓存文件。")
            }
            .alert("清理完成", isPresented: $cacheClearedNotice) {
                Button("好的", role: .cancel) { }
            } message: {
                Text("网页静态缓存与网络数据已清除。")
            }
        }
    }
    
    /// 清除所有网页缓存与数据
    private func clearWebCache() {
        let websiteDataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let dateFrom = Date(timeIntervalSince1970: 0)
        
        WKWebsiteDataStore.default().removeData(ofTypes: websiteDataTypes, modifiedSince: dateFrom) {
            DispatchQueue.main.async {
                self.cacheClearedNotice = true
            }
        }
    }
}
