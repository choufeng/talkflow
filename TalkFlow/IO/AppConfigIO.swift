import Foundation

// MARK: - 应用配置持久化（副作用）

/// AppConfig 文件路径（纯函数）
private func configFilePath() -> URL {
    let appSupport = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/TalkFlow")
    try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
    return appSupport.appendingPathComponent("config.json")
}

// MARK: - ⚠️ 持久化

/// 保存配置到磁盘
func impureSaveAppConfig(_ config: AppConfig) {
    let url = configFilePath()
    do {
        let data = try JSONEncoder().encode(config)
        try data.write(to: url, options: .atomic)
        impureMakeLogger().debug(tag: "AppConfig", "已保存: \(url.path)")
    } catch {
        impureMakeLogger().error(tag: "AppConfig", "保存失败: \(error.localizedDescription)")
    }
}

/// 从磁盘加载配置，文件不存在则返回默认
func impureLoadAppConfig() -> AppConfig {
    let url = configFilePath()
    guard FileManager.default.fileExists(atPath: url.path) else {
        impureMakeLogger().info(tag: "AppConfig", "配置文件不存在，使用默认")
        return makeDefaultAppConfig()
    }
    do {
        let data = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        impureMakeLogger().debug(tag: "AppConfig", "已加载: \(url.path)")
        return config
    } catch {
        impureMakeLogger().warning(tag: "AppConfig", "加载失败: \(error.localizedDescription)，使用默认")
        return makeDefaultAppConfig()
    }
}
