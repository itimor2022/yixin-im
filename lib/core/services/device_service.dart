import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 设备信息服务
class DeviceService {
  static const String _deviceIdKey = 'app_device_id';
  static String? _cachedDeviceId;
  static String? _cachedDeviceName;
  static String? _cachedDeviceType;
  
  /// 获取持久化的设备ID
  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);
    
    if (deviceId == null || deviceId.isEmpty) {
      // 首次安装，生成新的设备ID
      deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, deviceId);
    }
    
    _cachedDeviceId = deviceId;
    return deviceId;
  }
  
  /// 获取设备类型
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
  
  /// 获取设备名称（包含型号）
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
