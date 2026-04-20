import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/bag_model.dart';
import '../models/user_model.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // --- Auth & User ---
  
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Stream<UserModel?> streamUserData(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists) {
        return UserModel.fromMap(doc.data()!, uid);
      }
      return null;
    });
  }

  Future<void> saveUser(UserModel user) async {
    await _db.collection('users').doc(user.uid).set(user.toMap(), SetOptions(merge: true));
  }

  // --- Bag Operations ---

  Stream<BagModel?> streamBag(String bagId) {
    return _db.collection('bags').doc(bagId).snapshots().map((doc) {
      if (doc.exists) return BagModel.fromFirestore(doc);
      return null;
    });
  }

  Stream<List<BagModel>> streamOwnedBags(String ownerId) {
    return _db
        .collection('bags')
        .where('ownerId', isEqualTo: ownerId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => BagModel.fromFirestore(doc)).toList());
  }

  Future<void> addBag(String bagId, String ownerId, String name) async {
    await _db.collection('bags').doc(bagId).set({
      'ownerId': ownerId,
      'name': name,
      'location': const GeoPoint(0, 0),
      'isArmed': false,
      'isTampered': false,
      'pocketItems': {},
      'batteryLevel': 100.0,
      'lastSync': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeBag(String bagId) async {
    await _db.collection('bags').doc(bagId).delete();
  }

  Future<void> updateBagLocation(String bagId, GeoPoint location) async {
    await _db.collection('bags').doc(bagId).update({
      'location': location,
      'lastSync': FieldValue.serverTimestamp(),
    });
    
    // Also log to history
    await _db.collection('locationHistory').add({
      'bagId': bagId,
      'location': location,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> toggleArmState(String bagId, bool isArmed) async {
    await _db.collection('bags').doc(bagId).update({'isArmed': isArmed});
  }

  // --- Alerts ---

  Future<void> reportAlert(String bagId, String type, String message) async {
    await _db.collection('alerts').add({
      'bagId': bagId,
      'type': type,
      'message': message,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
    });
  }
}
