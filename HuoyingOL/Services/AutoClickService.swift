//
//  AutoClickService.swift
//  HuoyingOL
//
//  自动点击服务
//  通过JavaScript注入MutationObserver自动检测并点击游戏中的对话框按钮
//  匹配模式: close|btn|button|restPK|autoFight|defaultOk|getOut|confirm|sure|^ok$
//

import Foundation
import WebKit

/// 自动点击服务
/// 注入JavaScript代码，使用MutationObserver监听DOM变化
/// 自动点击匹配特定模式的按钮元素
class AutoClickService {
    
    /// 需要自动点击的按钮名称/ID匹配模式
    /// 来自Android APK中SWF的按钮匹配规则
    static let buttonPatterns = [
        "close",        // 关闭按钮
        "btn",          // 通用按钮
        "button",       // 通用按钮
        "restPK",       // 休息PK按钮
        "autoFight",    // 自动战斗
        "defaultOk",    // 默认确认
        "getOut",       // 退出按钮
        "confirm",      // 确认按钮
        "sure",         // 确定按钮
        "^ok$"          // 精确匹配ok
    ]
    
    /// 生成自动点击的JavaScript代码
    /// 使用MutationObserver监听DOM变化，检测新出现的对话框并自动点击匹配按钮
    /// - Returns: JavaScript代码字符串
    func generateAutoClickScript() -> String {
        return """
        (function() {
            'use strict';
            
            // ===== 火影OL 自动点击服务 =====
            // 使用MutationObserver监听DOM变化
            // 自动点击匹配模式的按钮: close|btn|button|restPK|autoFight|defaultOk|getOut|confirm|sure|^ok$
            
            // 防止重复初始化
            if (window._huoyingAutoClick) {
                console.log('[火影OL] 自动点击已运行，跳过重复初始化');
                return;
            }
            
            // 按钮匹配正则表达式
            var buttonPattern = /close|btn|button|restPK|autoFight|defaultOk|getOut|confirm|sure|^ok$/i;
            
            // 点击延迟（毫秒），避免过快点击导致问题
            var clickDelay = 300;
            
            // 最近点击记录，防止重复点击同一个按钮
            var recentClicks = new Map();
            var recentClickExpiry = 2000; // 2秒内不重复点击同一按钮
            
            // 检查元素是否为可见的可点击按钮
            function isClickableAndVisible(el) {
                if (!el || !el.offsetParent && el.style.display !== 'fixed') return false;
                var rect = el.getBoundingClientRect();
                if (rect.width <= 0 || rect.height <= 0) return false;
                var style = window.getComputedStyle(el);
                if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') return false;
                return true;
            }
            
            // 生成元素的唯一标识
            function getElementKey(el) {
                return (el.id || '') + '|' + (el.className || '') + '|' + (el.name || '') + '|' + (el.textContent || '').trim().substring(0, 20);
            }
            
            // 尝试点击匹配的按钮
            function tryClickButton(el) {
                var key = getElementKey(el);
                var now = Date.now();
                
                // 检查是否最近已点击过
                if (recentClicks.has(key) && now - recentClicks.get(key) < recentClickExpiry) {
                    return;
                }
                
                // 检查元素的各种属性是否匹配模式
                var matchTarget = [
                    el.id || '',
                    el.name || '',
                    el.className || '',
                    el.getAttribute('data-name') || '',
                    el.getAttribute('data-action') || ''
                ].join(' ');
                
                if (buttonPattern.test(matchTarget)) {
                    if (isClickableAndVisible(el)) {
                        recentClicks.set(key, now);
                        setTimeout(function() {
                            try {
                                el.click();
                                console.log('[火影OL] 自动点击: ' + (el.id || el.className || el.tagName));
                            } catch(e) {
                                console.warn('[火影OL] 点击失败:', e);
                            }
                        }, clickDelay);
                    }
                }
            }
            
            // 扫描节点及其子节点中的按钮
            function scanForButtons(root) {
                if (!root || root.nodeType !== 1) return;
                
                // 检查根元素本身
                tryClickButton(root);
                
                // 检查所有子元素
                var elements = root.querySelectorAll('*');
                for (var i = 0; i < elements.length; i++) {
                    tryClickButton(elements[i]);
                }
            }
            
            // 定期清理过期的点击记录
            setInterval(function() {
                var now = Date.now();
                recentClicks.forEach(function(time, key) {
                    if (now - time > recentClickExpiry) {
                        recentClicks.delete(key);
                    }
                });
            }, 5000);
            
            // ---- 创建MutationObserver ----
            // 监听DOM树的变化，检测新添加的元素
            var observer = new MutationObserver(function(mutations) {
                for (var i = 0; i < mutations.length; i++) {
                    var mutation = mutations[i];
                    
                    // 处理新增节点
                    if (mutation.type === 'childList') {
                        for (var j = 0; j < mutation.addedNodes.length; j++) {
                            var node = mutation.addedNodes[j];
                            if (node.nodeType === 1) {
                                // 延迟扫描，等待元素完全渲染
                                (function(n) {
                                    setTimeout(function() { scanForButtons(n); }, 100);
                                })(node);
                            }
                        }
                    }
                    
                    // 处理属性变化（如display从none变为block）
                    if (mutation.type === 'attributes') {
                        var target = mutation.target;
                        if (target.nodeType === 1) {
                            var style = window.getComputedStyle(target);
                            if (style.display !== 'none' && style.visibility !== 'hidden') {
                                setTimeout(function() { scanForButtons(target); }, 100);
                            }
                        }
                    }
                }
            });
            
            // 观察整个文档的DOM变化
            observer.observe(document.documentElement || document.body, {
                childList: true,      // 监听子节点增删
                subtree: true,        // 监听所有后代节点
                attributes: true,     // 监听属性变化
                attributeFilter: ['style', 'class', 'hidden'] // 只关注样式相关属性
            });
            
            // 初始扫描页面上已有的元素
            scanForButtons(document.body);
            
            // 保存引用以便后续停止
            window._huoyingAutoClick = {
                observer: observer,
                active: true
            };
            
            console.log('[火影OL] 自动点击服务已启动');
        })();
        """
    }
    
    /// 生成禁用自动点击的JavaScript代码
    /// - Returns: JavaScript代码字符串
    func generateDisableScript() -> String {
        return """
        (function() {
            'use strict';
            if (window._huoyingAutoClick) {
                if (window._huoyingAutoClick.observer) {
                    window._huoyingAutoClick.observer.disconnect();
                }
                window._huoyingAutoClick.active = false;
                delete window._huoyingAutoClick;
                console.log('[火影OL] 自动点击服务已停止');
            }
        })();
        """
    }
    
    /// 创建WKUserScript用于页面加载时自动注入
    /// - Returns: WKUserScript对象
    func createUserScript() -> WKUserScript {
        let source = generateAutoClickScript()
        return WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
    }
}
