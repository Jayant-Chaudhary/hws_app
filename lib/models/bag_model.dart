import 'package:cloud_firestore/cloud_firestore.dart';

class BagModel {
  final String id;
  final String ownerId;
  final String name;
  final GeoPoint location;
  final bool isArmed;
  final bool isTampered;
  final Map<String, bool> pocketItems; // Item Name -> Is Present
  final double batteryLevel;
  final DateTime lastSync;

  BagModel({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.location,
    required this.isArmed,
    this.isTampered = false,
    required this.pocketItems,
    this.batteryLevel = 100.0,
    required this.lastSync,
  });

  factory BagModel.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return BagModel(
      id: doc.id,
      ownerId: data['ownerId'] ?? '',
      name: data['name'] ?? 'My Smart Bag',
      location: data['location'] ?? const GeoPoint(0, 0),
      isArmed: data['isArmed'] ?? false,
      isTampered: data['isTampered'] ?? false,
      pocketItems: Map<String, bool>.from(data['pocketItems'] ?? {}),
      batteryLevel: (data['batteryLevel'] ?? 100.0).toDouble(),
      lastSync: (data['lastSync'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ownerId': ownerId,
      'name': name,
      'location': location,
      'isArmed': isArmed,
      'isTampered': isTampered,
      'pocketItems': pocketItems,
      'batteryLevel': batteryLevel,
      'lastSync': Timestamp.fromDate(lastSync),
    };
  }
}
