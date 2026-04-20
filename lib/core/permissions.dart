import 'package:permission_handler/permission_handler.dart';

class PermissionHelper {
  static Future<bool> requestRelayPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.notification,
    ].request();

    bool hasErrors = false;
    statuses.forEach((permission, status) {
      if (!status.isGranted && !status.isLimited) {
        print("Permission denied: $permission (status: $status)");
        hasErrors = true;
      }
    });

    return !hasErrors;
  }

}
