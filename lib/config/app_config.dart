/// Rescue Mesh 统一环境配置
///
/// 通过 `flutter run --dart-define=API_BASE_URL=http://xxx:3000` 指定后端地址。
///
/// 用法:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.100:3000
library;

class AppConfig {
  AppConfig._();

  /// 后端 API 基础地址
  /// 默认: http://101.35.52.133:3000
  /// 可通过 --dart-define=API_BASE_URL=xxx 覆盖
  static String get apiBaseUrl {
    const customUrl = String.fromEnvironment('API_BASE_URL');
    if (customUrl.isNotEmpty) {
      return customUrl;
    }
    return 'http://101.35.52.133:3000';
  }

  /// 完整的 SOS 同步端点
  static Uri get sosSyncEndpoint => Uri.parse('$apiBaseUrl/api/sos/sync');
}
