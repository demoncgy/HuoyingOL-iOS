//
//  SpeedController.swift
//  HuoyingOL
//
//  速度控制器
//  通过JavaScript注入覆写时间相关API实现游戏加速
//  覆写: Date.now, performance.now, setTimeout, setInterval, requestAnimationFrame
//

import Foundation
import WebKit

/// 速度控制器
/// 生成JavaScript代码来覆写浏览器时间API，实现游戏速度倍率控制
class SpeedController {
    
    /// 生成速度控制的JavaScript代码
    /// - Parameter multiplier: 速度倍率（1.0 = 正常，2.0 = 两倍速）
    /// - Returns: 用于注入WebView的JavaScript代码
    func generateSpeedScript(multiplier: Double) -> String {
        // 如果倍率为1.0，移除速度控制并恢复原始API
        if abs(multiplier - 1.0) < 0.01 {
            return generateResetScript()
        }
        
        return """
        (function() {
            'use strict';
            
            // ===== 火影OL 速度控制器 =====
            // 速度倍率: \(multiplier)x
            // 通过覆写时间相关API实现游戏加速/减速
            
            // 防止重复初始化，保存原始API引用
            if (!window._huoyingSpeedOriginals) {
                window._huoyingSpeedOriginals = {
                    DateNow: Date.now,
                    perfNow: performance.now.bind(performance),
                    setTimeout: window.setTimeout.bind(window),
                    clearTimeout: window.clearTimeout.bind(window),
                    setInterval: window.setInterval.bind(window),
                    clearInterval: window.clearInterval.bind(window),
                    requestAnimationFrame: window.requestAnimationFrame.bind(window),
                    cancelAnimationFrame: window.cancelAnimationFrame.bind(window),
                    startRealTime: Date.now(),
                    startVirtualTime: Date.now()
                };
            }
            
            var orig = window._huoyingSpeedOriginals;
            var multiplier = \(multiplier);
            
            // 记录新倍率的起始时间点
            var realNow = orig.DateNow();
            var virtualNow = (typeof window._huoyingVirtualTime === 'number')
                ? window._huoyingVirtualTime
                : realNow;
            
            orig.startRealTime = realNow;
            orig.startVirtualTime = virtualNow;
            
            // ---- 覆写 Date.now() ----
            // 返回经过倍率调整的虚拟时间
            Date.now = function() {
                var elapsed = orig.DateNow() - orig.startRealTime;
                var vt = orig.startVirtualTime + elapsed * multiplier;
                window._huoyingVirtualTime = vt;
                return Math.floor(vt);
            };
            
            // ---- 覆写 performance.now() ----
            // 同样应用倍率到高精度计时器
            var perfBase = orig.perfNow();
            var perfVirtualBase = perfBase;
            performance.now = function() {
                var elapsed = orig.perfNow() - perfBase;
                return perfVirtualBase + elapsed * multiplier;
            };
            
            // ---- 覆写 new Date() 构造函数 ----
            // 无参数调用时返回虚拟时间
            var OriginalDate = Date;
            var SpeedDate = function() {
                if (arguments.length === 0) {
                    return new OriginalDate(Date.now());
                }
                // 有参数时使用原始行为
                switch (arguments.length) {
                    case 1: return new OriginalDate(arguments[0]);
                    case 2: return new OriginalDate(arguments[0], arguments[1]);
                    case 3: return new OriginalDate(arguments[0], arguments[1], arguments[2]);
                    case 4: return new OriginalDate(arguments[0], arguments[1], arguments[2], arguments[3]);
                    case 5: return new OriginalDate(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4]);
                    case 6: return new OriginalDate(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5]);
                    default: return new OriginalDate(arguments[0], arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6]);
                }
            };
            SpeedDate.now = Date.now;
            SpeedDate.parse = OriginalDate.parse;
            SpeedDate.UTC = OriginalDate.UTC;
            SpeedDate.prototype = OriginalDate.prototype;
            window.Date = SpeedDate;
            
            // ---- 覆写 setTimeout ----
            // 将延迟时间除以倍率，使定时器更快触发
            window.setTimeout = function(fn, delay) {
                var args = Array.prototype.slice.call(arguments, 2);
                var adjustedDelay = Math.max(0, Math.floor((delay || 0) / multiplier));
                return orig.setTimeout(function() {
                    if (typeof fn === 'function') fn.apply(null, args);
                    else if (typeof fn === 'string') eval(fn);
                }, adjustedDelay);
            };
            
            // ---- 覆写 setInterval ----
            // 将间隔时间除以倍率
            window.setInterval = function(fn, interval) {
                var args = Array.prototype.slice.call(arguments, 2);
                var adjustedInterval = Math.max(1, Math.floor((interval || 0) / multiplier));
                return orig.setInterval(function() {
                    if (typeof fn === 'function') fn.apply(null, args);
                    else if (typeof fn === 'string') eval(fn);
                }, adjustedInterval);
            };
            
            // ---- 覆写 requestAnimationFrame ----
            // 如果加速，通过setTimeout模拟更高帧率
            if (multiplier > 1) {
                var rafId = 0;
                var rafCallbacks = {};
                window.requestAnimationFrame = function(callback) {
                    var id = ++rafId;
                    rafCallbacks[id] = true;
                    orig.setTimeout(function() {
                        if (rafCallbacks[id]) {
                            delete rafCallbacks[id];
                            callback(performance.now());
                        }
                    }, Math.floor(16 / multiplier));
                    return id;
                };
                window.cancelAnimationFrame = function(id) {
                    delete rafCallbacks[id];
                };
            }
            
            // 保留clearTimeout和clearInterval的原始行为
            window.clearTimeout = orig.clearTimeout;
            window.clearInterval = orig.clearInterval;
            
            // 标记当前倍率
            window._huoyingSpeedMultiplier = multiplier;
            
            console.log('[火影OL] 速度控制已设置: ' + multiplier + 'x');
        })();
        """
    }
    
    /// 生成重置速度的JavaScript代码
    /// - Returns: 恢复原始API的JavaScript代码
    func generateResetScript() -> String {
        return """
        (function() {
            'use strict';
            
            // ===== 火影OL 速度控制 - 恢复原始速度 =====
            
            if (window._huoyingSpeedOriginals) {
                var orig = window._huoyingSpeedOriginals;
                Date.now = orig.DateNow;
                performance.now = orig.perfNow;
                window.setTimeout = orig.setTimeout;
                window.clearTimeout = orig.clearTimeout;
                window.setInterval = orig.setInterval;
                window.clearInterval = orig.clearInterval;
                window.requestAnimationFrame = orig.requestAnimationFrame;
                window.cancelAnimationFrame = orig.cancelAnimationFrame;
                
                delete window._huoyingSpeedOriginals;
                delete window._huoyingVirtualTime;
                delete window._huoyingSpeedMultiplier;
                
                console.log('[火影OL] 速度已恢复为1x');
            }
        })();
        """
    }
    
    /// 生成WKUserScript用于页面加载时自动注入
    /// - Parameter multiplier: 速度倍率
    /// - Returns: WKUserScript对象
    func createUserScript(multiplier: Double) -> WKUserScript? {
        guard abs(multiplier - 1.0) >= 0.01 else { return nil }
        
        let source = generateSpeedScript(multiplier: multiplier)
        return WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
    }
}
