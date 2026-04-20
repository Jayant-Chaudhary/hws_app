import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:geolocator/geolocator.dart';

class OwnerBLEService {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  StreamSubscription<ConnectionStateUpdate>? _connectionStream;
  StreamSubscription<List<int>>? _sensorSubscription;

  // UUIDs defined in ESP32 v3.2 Firmware
  final Uuid serviceUuid = Uuid.parse("c8e9b626-4d0c-48c0-8a1d-72c019d677a2");
  final Uuid charSensorUuid = Uuid.parse("b1f5c3a2-1111-2222-3333-abcdefabcdef");
  final Uuid charInvUuid = Uuid.parse("a2f4e6b8-2222-3333-4444-bcdefabcdef0");
  final Uuid charOwnerSigUuid = Uuid.parse("d3c5b7a9-3333-4444-5555-cdefabcdef01");
  final Uuid charPhoneGpsUuid = Uuid.parse("e4d6c8b0-4444-5555-6666-defabcdef012");

  // Callbacks
  final Function(String) onSensorData;
  final Function(DeviceConnectionState) onConnectionStateChanged;

  OwnerBLEService({
    required this.onSensorData,
    required this.onConnectionStateChanged,
  });

  void connect(String deviceId) {
    // ReactiveBle connectToDevice takes the device MAC or UUID
    _connectionStream = _ble.connectToDevice(
      id: deviceId,
      servicesWithCharacteristicsToDiscover: {
        serviceUuid: [charSensorUuid, charInvUuid, charOwnerSigUuid, charPhoneGpsUuid]
      },
      connectionTimeout: const Duration(seconds: 10),
    ).listen((state) {
      onConnectionStateChanged(state.connectionState);

      if (state.connectionState == DeviceConnectionState.connected) {
        _onConnected(deviceId);
      } else if (state.connectionState == DeviceConnectionState.disconnected) {
        _sensorSubscription?.cancel();
      }
    }, onError: (Object error) {
      debugPrint("BLE Connection Error: $error");
    });
  }

  void _onConnected(String deviceId) async {
    // 1. Send Owner Signature (Write "1" to CHAR_OWNER_SIG_UUID)
    try {
      final ownerSigChar = QualifiedCharacteristic(
        serviceId: serviceUuid,
        characteristicId: charOwnerSigUuid,
        deviceId: deviceId,
      );
      await _ble.writeCharacteristicWithResponse(ownerSigChar, value: "1".codeUnits);
      debugPrint("Sent Owner Signature");
    } catch (e) {
      debugPrint("Failed to write owner sig: $e");
    }

    // 2. Subscribe to Sensor stream
    final sensorChar = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: charSensorUuid,
      deviceId: deviceId,
    );
    _sensorSubscription = _ble.subscribeToCharacteristic(sensorChar).listen((data) {
      String strData = String.fromCharCodes(data);
      onSensorData(strData);
    });

    // 3. Send Phone GPS periodically or once
    _sendPhoneLocation(deviceId);
  }

  Future<void> _sendPhoneLocation(String deviceId) async {
    try {
      Position pos = await Geolocator.getCurrentPosition();
      String gpsStr = "${pos.latitude.toStringAsFixed(6)},${pos.longitude.toStringAsFixed(6)}";

      final phoneGpsChar = QualifiedCharacteristic(
        serviceId: serviceUuid,
        characteristicId: charPhoneGpsUuid,
        deviceId: deviceId,
      );
      
      await _ble.writeCharacteristicWithoutResponse(phoneGpsChar, value: gpsStr.codeUnits);
      debugPrint("Sent Phone GPS: $gpsStr");
    } catch (e) {
      debugPrint("Failed to send phone GPS: $e");
    }
  }

  Future<String> readInventory(String deviceId) async {
    try {
      final invChar = QualifiedCharacteristic(
        serviceId: serviceUuid,
        characteristicId: charInvUuid,
        deviceId: deviceId,
      );
      final response = await _ble.readCharacteristic(invChar);
      return String.fromCharCodes(response);
    } catch (e) {
      debugPrint("Failed to read inventory: $e");
      return "";
    }
  }

  Future<void> writeInventory(String deviceId, String inventory) async {
    try {
      final invChar = QualifiedCharacteristic(
        serviceId: serviceUuid,
        characteristicId: charInvUuid,
        deviceId: deviceId,
      );
      await _ble.writeCharacteristicWithResponse(invChar, value: inventory.codeUnits);
    } catch (e) {
      debugPrint("Failed to write inventory: $e");
    }
  }

  void disconnect() {
    _sensorSubscription?.cancel();
    _connectionStream?.cancel();
  }
}
