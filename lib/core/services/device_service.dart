// 文件用途：封装 DeviceService 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 DeviceService 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'package:universal_io/io.dart';
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// 关键声明：device service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
/// 提供安装级设备标识和面向用户展示的设备信息。
///
/// 设备 ID 用于区分登录设备，不是硬件指纹，也不能作为认证凭证。读取失败时
/// 生成的兜底 ID 只保证当前进程内稳定，持久化恢复后后续进程可能得到不同 ID。
class DeviceService {
  static const String _deviceIdKey = 'app_device_id';
  static const String _iosInstallationIdKey = 'ios_installation_id_v1';
  static const FlutterSecureStorage _iosSecureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static String? _cachedDeviceId;
  static String? _cachedDeviceName;
  static String? _cachedDeviceType;

  /// 获取当前安装的稳定设备 ID，并在进程内缓存结果。
  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    try {
      if (!kIsWeb && Platform.isIOS) {
        final deviceId = await _getIOSDeviceId();
        _cachedDeviceId = deviceId;
        return deviceId;
      }

      final prefs = await SharedPreferences.getInstance();
      String? deviceId = prefs.getString(_deviceIdKey);

      if (deviceId == null || deviceId.isEmpty) {
        // 首次安装，生成新的设备ID。写入失败不应阻断本次登录。
        deviceId = const Uuid().v4();
        final saved = await prefs.setString(_deviceIdKey, deviceId);
        if (!saved) {
          debugPrint('[Device] Device ID persistence was rejected');
        }
      }

      _cachedDeviceId = deviceId;
      return deviceId;
    } catch (e) {
      // 首次启动时 Keychain/SharedPreferences 可能尚未就绪。
      // 使用进程内稳定 ID 允许用户直接登录，无需重启 App。
      debugPrint('[Device] Failed to initialize persistent device ID: $e');
      final fallback = 'install:${const Uuid().v4().toLowerCase()}';
      _cachedDeviceId = fallback;
      return fallback;
    }
  }

  static Future<String> _getIOSDeviceId() async {
    // iOS 优先使用供应商标识；不可用时才使用 Keychain 保存的安装标识。
    try {
      final iosInfo = await DeviceInfoPlugin().iosInfo;
      final idfv = iosInfo.identifierForVendor?.trim().toLowerCase() ?? '';
      if (idfv.isNotEmpty) {
        return 'ios:idfv:$idfv';
      }
    } catch (e) {
      debugPrint('[Device] Failed to read identifierForVendor: $e');
    }

    var installationId =
        (await _iosSecureStorage.read(key: _iosInstallationIdKey))
                ?.trim()
                .toLowerCase() ??
            '';
    if (installationId.isEmpty) {
      installationId = const Uuid().v4().toLowerCase();
      await _iosSecureStorage.write(
        key: _iosInstallationIdKey,
        value: installationId,
      );
    }
    return 'ios:install:$installationId';
  }

  /// 获取供服务端设备列表使用的规范化平台类型。
  static String getDeviceType() {
    if (_cachedDeviceType != null) return _cachedDeviceType!;
    if (kIsWeb) {
      _cachedDeviceType = 'web';
      return _cachedDeviceType!;
    }
    if (Platform.isAndroid) {
      _cachedDeviceType = 'android';
    } else if (Platform.isIOS) {
      _cachedDeviceType = 'ios';
    } else if (Platform.isMacOS) {
      _cachedDeviceType = 'macos';
    } else if (Platform.isWindows) {
      _cachedDeviceType = 'windows';
    } else if (Platform.isLinux) {
      _cachedDeviceType = 'linux';
    } else {
      _cachedDeviceType = 'unknown';
    }

    return _cachedDeviceType!;
  }

  /// 获取供设备管理界面展示的名称（包含可用时的平台型号）。
  static Future<String> getDeviceName() async {
    if (_cachedDeviceName != null) return _cachedDeviceName!;

    try {
      if (kIsWeb) {
        _cachedDeviceName = 'Web Browser';
        return _cachedDeviceName!;
      }

      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _cachedDeviceName = iosInfo.name;
        if (_cachedDeviceName == null || _cachedDeviceName!.isEmpty) {
          _cachedDeviceName = _formatIOSModel(iosInfo.utsname.machine);
        }
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        final brand = androidInfo.brand;
        final model = androidInfo.model;
        _cachedDeviceName = '$brand $model';
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        _cachedDeviceName = macInfo.computerName;
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        _cachedDeviceName = windowsInfo.computerName;
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        _cachedDeviceName = linuxInfo.prettyName;
      } else {
        _cachedDeviceName = 'Unknown Device';
      }
    } catch (e) {
      // 设备信息插件不可用时退回通用名称，不影响登录和设备登记。
      _cachedDeviceName = _getDefaultDeviceName();
    }

    return _cachedDeviceName ?? _getDefaultDeviceName();
  }

  static String _getDefaultDeviceName() {
    if (kIsWeb) return 'Web Browser';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isWindows) return 'Windows PC';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown Device';
  }

  /// 格式化 iOS 机型代码为可读名称
  static String _formatIOSModel(String machineCode) {
    // 简单的机型映射
    final modelMap = {
      'iPhone16,2': 'iPhone 15 Pro Max',
      'iPhone16,1': 'iPhone 15 Pro',
      'iPhone15,5': 'iPhone 15 Plus',
      'iPhone15,4': 'iPhone 15',
      'iPhone15,3': 'iPhone 14 Pro Max',
      'iPhone15,2': 'iPhone 14 Pro',
      'iPhone14,8': 'iPhone 14 Plus',
      'iPhone14,7': 'iPhone 14',
      'iPhone14,3': 'iPhone 13 Pro Max',
      'iPhone14,2': 'iPhone 13 Pro',
      'iPhone14,5': 'iPhone 13',
      'iPhone14,4': 'iPhone 13 mini',
      'iPhone17,1': 'iPhone 16 Pro',
      'iPhone17,2': 'iPhone 16 Pro Max',
      'iPhone17,3': 'iPhone 16',
      'iPhone17,4': 'iPhone 16 Plus',
      'iPhone17,5': 'iPhone 17 Pro',
      'iPhone17,6': 'iPhone 17 Pro Max',
    };

    return modelMap[machineCode] ?? machineCode;
  }
}
