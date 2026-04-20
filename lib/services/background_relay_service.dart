import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:typed_data';

class BLEBackgroundService {
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        initialNotificationTitle: 'Smart Bag Relay',
        initialNotificationContent: 'Scanning for nearby bags...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    WidgetsFlutterBinding.ensureInitialized();
    
    // Initialize Firebase in background isolate
    await Firebase.initializeApp();
    final db = FirebaseFirestore.instance;
    final ble = FlutterReactiveBle();
    
    debugPrint("Background Relay Service Started");

    Timer.periodic(const Duration(minutes: 5), (timer) async {
      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          service.setAsForegroundService();
        }
      }

      // First, get all registered Bag UUIDs from Firestore to know what to listen for
      List<String> validBagUuids = [];
      db.collection('bags').snapshots().listen((snapshot) {
        validBagUuids = snapshot.docs.map((doc) => doc.id.toLowerCase()).toList();
      });

      // 1. Scan for BLE devices
      ble.scanForDevices(withServices: [Uuid.parse("c8e9b626-4d0c-48c0-8a1d-72c019d677a2")], scanMode: ScanMode.lowPower).listen((device) async {
        try {
          if (device.manufacturerData.length < 17) return; // Ignore invalid payload

          // Determine if company ID is included (19 bytes) or stripped (17 bytes)
          int offset = device.manufacturerData.length >= 19 ? 2 : 0;
          Uint8List payload = device.manufacturerData;

          // Parse MAC Address (6 bytes)
          String bagMac = "";
          for (int i = 0; i < 6; i++) {
            bagMac += payload[offset + i].toRadixString(16).padLeft(2, '0').toUpperCase();
          }

          if (validBagUuids.contains(bagMac.toLowerCase())) {
            debugPrint("Smart Bag Detected: $bagMac");
            
            // Parse flags
            int flags = payload[offset + 6];
            bool gpsValid = (flags & (1 << 0)) != 0;
            bool sosActive = (flags & (1 << 1)) != 0;
            // bool motion = (flags & (1 << 2)) != 0; // Not actively logged to DB but available
            // bool phoneGPSUsed = (flags & (1 << 3)) != 0;

            // Parse GPS Floats (Little Endian)
            ByteData byteData = ByteData.sublistView(payload, offset + 7, offset + 15);
            double lat = byteData.getFloat32(0, Endian.little);
            double lng = byteData.getFloat32(4, Endian.little);

            GeoPoint reportedLocation;
            if (gpsValid) {
               reportedLocation = GeoPoint(lat, lng);
            } else {
               // Fallback: Relay phone provides its own location
               Position pos = await Geolocator.getCurrentPosition();
               reportedLocation = GeoPoint(pos.latitude, pos.longitude);
            }

            // Report to Firebase
            await db.collection('bags').doc(bagMac.toLowerCase()).update({
              'location': reportedLocation,
              'lastSync': FieldValue.serverTimestamp(),
              if (sosActive) 'isTampered': true, // Directly register tampering if SOS is high
            });

            // Log Alert if SOS is active
            if (sosActive) {
                // To avoid spamming, one could check if it's already tampered before adding an alert,
                // But for now, we just log the incident if caught in this broadcast.
                await db.collection('alerts').add({
                  'bagId': bagMac.toLowerCase(),
                  'type': 'SOS',
                  'message': 'Bag reported SOS / Motion Spike nearby.',
                  'timestamp': FieldValue.serverTimestamp(),
                  'isRead': false,
                });
            }

            debugPrint("Parsed & Updated location for Bag: $bagMac");
          }
        } catch (e) {
          debugPrint("Failed to parse/update location: $e");
        }
      });
    });

    service.on('stopService').listen((event) {
      service.stopSelf();
    });
  }
}

