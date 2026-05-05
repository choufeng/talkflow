# Token 缓存优化设计

日期: 2026-05-06

## 背景

当前每次 LLM 请求（润色/翻译）都重新获取 access_token：
- JWT 签名（RSA-256，Security framework）+ Google OAuth2 HTTP 交换
- 耗时 0.5-1.5s，占总延迟 30-50%
- 日志实测：润色请求总耗时 ~3s

## 目标

在 app 存活期内缓存 token，后续请求省去 token 获取开销。

非目标：磁盘持久化、token 预刷新、跨进程共享。

## 方案

### 装饰器模式：`CachedTokenProvider`

新建 `IO/CachedTokenProvider.swift`，包装任意 `TokenProviderIO` 实现：

```
actor CachedTokenProvider: TokenProviderIO {
    private let inner: any TokenProviderIO
    private var cachedToken: String?
    private var expiresAt: Date
    private let ttl: TimeInterval  // 默认 3300s

    func getAccessToken() async throws -> String
}
```

**actor** 保证线程安全，天然适配 async/await。

**TTL** 保守值 55 分钟（token 有效期 1 小时），不依赖 Google 响应中的 `expires_in` 字段。

### AppDelegate 改动

抽取共享的 `CachedTokenProvider`，润色和翻译复用同一实例：

- 首次触发 → 创建 `JWTTokenProvider`/`RefreshTokenProviderIO` + 包 `CachedTokenProvider` + 取 token
- 后续触发 → 缓存命中，直接使用

## 改动清单

| 文件 | 操作 | 内容 |
|------|------|------|
| `TalkFlow/IO/CachedTokenProvider.swift` | 新增 | actor + 缓存逻辑 |
| `TalkFlow/AppDelegate.swift` | 修改 | 抽取共享 CachedTokenProvider |

## 数据流

```
热键触发
  → sharedCachedTokenProvider()
  → provider.send()
      → getAccessToken()
          → 缓存命中？直接返回
          → 未命中？inner.getAccessToken() → 缓存 → 返回
  → LLM API
```

## 收益预估

| 场景 | 当前 | 优化后 |
|------|------|--------|
| 首次调用 | ~3s | ~3s（冷启动） |
| 后续调用 | ~3s | ~1-1.5s |
