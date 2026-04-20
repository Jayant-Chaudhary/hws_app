import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firebase_service.dart';
import '../models/user_model.dart';
import '../models/bag_model.dart';

import '../services/auth_service.dart';

final firebaseServiceProvider = Provider((ref) => FirebaseService());
final authServiceProvider = Provider((ref) => AuthService());

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseServiceProvider).authStateChanges;
});

final userModelProvider = StreamProvider<UserModel?>((ref) {
  final authUser = ref.watch(authStateProvider).value;
  if (authUser == null) return Stream.value(null);
  return ref.read(firebaseServiceProvider).streamUserData(authUser.uid);
});

final ownedBagsProvider = StreamProvider<List<BagModel>>((ref) {
  final user = ref.watch(userModelProvider).value;
  if (user == null) return Stream.value([]);
  return ref.read(firebaseServiceProvider).streamOwnedBags(user.uid);
});

final selectedBagProvider = StateProvider<BagModel?>((ref) => null);

final bagStreamProvider = StreamProvider.family<BagModel?, String>((ref, bagId) {
  return ref.read(firebaseServiceProvider).streamBag(bagId);
});
