//
//  BackgroundKeepAlive.swift
//  HuoyingOL
//
//  后台保活服务
//  通过音频会话和后台任务保持游戏连接活跃
//  防止iOS系统在应用进入后台时断开WebSocket连接
//

import Foundation
import AVFoundation
import UIKit

/// 后台保活服务
/// 使用静音音频播放保持应用在后台持续运行
/// 配合BGTaskScheduler进行后台刷新
class BackgroundKeepAlive {
    // MARK: - 属性
    
    /// 音频播放器（播放静音音频以保持后台运行）
    private var audioPlayer: AVAudioPlayer?
    
    /// 音频会话
    private var audioSession: AVAudioSession { AVAudioSession.sharedInstance() }
    
    /// 是否正在运行
    private(set) var isRunning = false
    
    /// 后台任务标识符
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    
    /// 保活定时器
    private var keepAliveTimer: Timer?
    
    // MARK: - 公共方法
    
    /// 启动后台保活
    func start() {
        guard !isRunning else {
            print("⚠️ 后台保活已在运行")
            return
        }
        
        isRunning = true
        
        // 配置音频会话
        configureAudioSession()
        
        // 开始播放静音音频
        startSilentAudio()
        
        // 注册应用生命周期通知
        registerLifecycleNotifications()
        
        print("🔋 后台保活服务已启动")
    }
    
    /// 停止后台保活
    func stop() {
        guard isRunning else { return }
        
        isRunning = false
        
        // 停止音频播放
        audioPlayer?.stop()
        audioPlayer = nil
        
        // 取消定时器
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        
        // 结束后台任务
        endBackgroundTask()
        
        // 移除通知监听
        NotificationCenter.default.removeObserver(self)
        
        print("🔋 后台保活服务已停止")
    }
    
    deinit {
        stop()
    }
    
    // MARK: - 音频会话配置
    
    /// 配置AVAudioSession以支持后台播放
    private func configureAudioSession() {
        do {
            // 设置音频类别为playback，允许后台播放
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers] // 与其他音频混合，不打断音乐等
            )
            try audioSession.setActive(true)
        } catch {
            print("❌ 音频会话配置失败: \(error.localizedDescription)")
        }
    }
    
    /// 开始播放静音音频
    /// 生成一段极短的静音PCM数据并循环播放
    private func startSilentAudio() {
        // 生成1秒的静音WAV数据
        let silentData = generateSilentWAVData(durationSeconds: 1.0, sampleRate: 8000)
        
        do {
            audioPlayer = try AVAudioPlayer(data: silentData)
            audioPlayer?.numberOfLoops = -1  // 无限循环
            audioPlayer?.volume = 0.0        // 静音
            audioPlayer?.play()
        } catch {
            print("❌ 静音音频播放失败: \(error.localizedDescription)")
        }
    }
    
    /// 生成静音WAV格式的音频数据
    /// - Parameters:
    ///   - durationSeconds: 时长（秒）
    ///   - sampleRate: 采样率
    /// - Returns: WAV格式的Data
    private func generateSilentWAVData(durationSeconds: Double, sampleRate: Int) -> Data {
        let numSamples = Int(Double(sampleRate) * durationSeconds)
        let bitsPerSample: Int = 16
        let numChannels: Int = 1
        let byteRate = sampleRate * numChannels * bitsPerSample / 8
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize = numSamples * blockAlign
        let fileSize = 36 + dataSize
        
        var data = Data()
        
        // RIFF头
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        data.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Array($0) })
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        
        // fmt子块
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // 子块大小
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // PCM格式
        data.append(contentsOf: withUnsafeBytes(of: UInt16(numChannels).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })
        
        // data子块
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
        
        // 静音PCM数据（全零）
        data.append(Data(count: dataSize))
        
        return data
    }
    
    // MARK: - 后台任务
    
    /// 注册应用生命周期通知
    private func registerLifecycleNotifications() {
        // 应用进入后台时开始后台任务
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        // 应用回到前台时结束后台任务
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    /// 应用进入后台
    @objc private func appDidEnterBackground() {
        guard isRunning else { return }
        
        // 开始后台任务，获取额外的执行时间
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "HuoyingKeepAlive") {
            // 后台时间即将耗尽，结束任务
            self.endBackgroundTask()
        }
        
        // 确保音频继续播放
        if audioPlayer?.isPlaying != true {
            startSilentAudio()
        }
        
        print("🔋 应用进入后台，保活任务已启动")
    }
    
    /// 应用回到前台
    @objc private func appWillEnterForeground() {
        endBackgroundTask()
        print("🔋 应用回到前台")
    }
    
    /// 结束后台任务
    private func endBackgroundTask() {
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }
    }
}
