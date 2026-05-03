import Foundation

// MARK: - ADC 文件加载（副作用）

/// 从默认路径 ~/.config/gcloud/application_default_credentials.json 加载 ADC
/// 文件不存在或解析失败 → nil
func impureLoadADCFromDefaultPath() -> ADCCredential? {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let adcPath = home.appendingPathComponent(".config/gcloud/application_default_credentials.json")

    guard FileManager.default.fileExists(atPath: adcPath.path) else {
        print("[ADC] ADC 文件不存在: \(adcPath.path)")
        return nil
    }

    let data: Data
    do {
        data = try Data(contentsOf: adcPath)
    } catch {
        print("[ADC] 读取 ADC 文件失败: \(error.localizedDescription)")
        return nil
    }

    let json: [String: Any]
    do {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[ADC] ADC JSON 格式错误")
            return nil
        }
        json = dict
    } catch {
        print("[ADC] ADC JSON 解析失败: \(error.localizedDescription)")
        return nil
    }

    do {
        return try parseADC(from: json)
    } catch {
        print("[ADC] ADC 解析失败: \(error)")
        return nil
    }
}
