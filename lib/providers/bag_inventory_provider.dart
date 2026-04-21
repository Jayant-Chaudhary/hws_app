import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import '../models/inventory_item.dart';
import '../services/nfc_scan_service.dart';
import '../services/firebase_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  STATE
// ══════════════════════════════════════════════════════════════════════════════

/// Represents the outcome of the most recent NFC scan action.
enum ScanAction { added, removed }

/// Immutable state for the bag inventory feature.
class BagInventoryState {
  /// All tracked inventory items (both in-bag and removed).
  final List<InventoryItem> items;

  /// The most recently scanned item (null if no scan has occurred yet).
  final InventoryItem? lastScanned;

  /// Whether the last scan added or removed an item.
  final ScanAction? lastAction;

  /// Whether NFC hardware is available on this device.
  final bool isNfcAvailable;

  /// Whether an NFC scan session is currently active.
  final bool isScanning;

  const BagInventoryState({
    this.items = const [],
    this.lastScanned,
    this.lastAction,
    this.isNfcAvailable = false,
    this.isScanning = false,
  });

  /// Items currently in the bag.
  List<InventoryItem> get inBagItems =>
      items.where((item) => item.isInBag).toList();

  /// Items recently removed from the bag.
  List<InventoryItem> get removedItems =>
      items.where((item) => !item.isInBag).toList();

  BagInventoryState copyWith({
    List<InventoryItem>? items,
    InventoryItem? lastScanned,
    ScanAction? lastAction,
    bool? isNfcAvailable,
    bool? isScanning,
  }) {
    return BagInventoryState(
      items: items ?? this.items,
      lastScanned: lastScanned ?? this.lastScanned,
      lastAction: lastAction ?? this.lastAction,
      isNfcAvailable: isNfcAvailable ?? this.isNfcAvailable,
      isScanning: isScanning ?? this.isScanning,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  NOTIFIER
// ══════════════════════════════════════════════════════════════════════════════

/// Manages bag inventory state with NFC scan → toggle logic.
///
/// Core toggle formula:
///   newInventory = exists ? inventory.filter(id) : [...inventory, newItem]
class BagInventoryNotifier extends StateNotifier<BagInventoryState> {
  final String bagId;
  final FirebaseService _firebaseService;
  final NfcScanService _nfcScanService = NfcScanService();

  BagInventoryNotifier({
    required this.bagId,
    required FirebaseService firebaseService,
  })  : _firebaseService = firebaseService,
        super(const BagInventoryState()) {
    _initialize();
  }

  /// Initialize: check NFC availability and load existing inventory from Firestore.
  Future<void> _initialize() async {
    final nfcAvailable = await _nfcScanService.isNfcAvailable();
    state = state.copyWith(isNfcAvailable: nfcAvailable);

    // Load existing pocketItems from Firestore and convert to InventoryItems
    _loadFromFirestore();
  }

  Future<void> _loadFromFirestore() async {
    try {
      final bagData = await _firebaseService.getBagInventoryData(bagId);
      if (bagData != null) {
        final List<InventoryItem> items = [];
        bagData.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            items.add(InventoryItem.fromMap(value));
          } else {
            // Legacy format: pocketItems { "Laptop": true, "Keys": false }
            items.add(InventoryItem(
              nfcId: key.hashCode.toRadixString(16).toUpperCase(),
              name: key,
              scannedAt: DateTime.now(),
              isInBag: value == true,
            ));
          }
        });
        state = state.copyWith(items: items);
      }
    } catch (e) {
      debugPrint("Failed to load inventory from Firestore: $e");
    }
  }

  /// Toggle an item's in-bag status based on NFC scan.
  ///
  /// If the item (by [nfcId]) is currently in the bag → remove it.
  /// If it's not in the bag (or never seen) → add it.
  void toggleItem(String nfcId, String itemName) {
    final now = DateTime.now();
    final existingIndex = state.items.indexWhere(
      (item) => item.nfcId == nfcId && item.isInBag,
    );

    List<InventoryItem> newItems;
    ScanAction action;
    InventoryItem scannedItem;

    if (existingIndex >= 0) {
      // ── REMOVE: Item is in the bag → mark as out ──────────────────────
      newItems = state.items.map((item) {
        if (item.nfcId == nfcId) {
          return item.copyWith(isInBag: false, scannedAt: now);
        }
        return item;
      }).toList();
      action = ScanAction.removed;
      scannedItem = InventoryItem(
        nfcId: nfcId,
        name: itemName,
        scannedAt: now,
        isInBag: false,
      );
    } else {
      // ── ADD: Item is not in the bag → add or re-add ───────────────────
      // Remove any existing entry for this nfcId first, then add fresh
      newItems = [
        ...state.items.where((item) => item.nfcId != nfcId),
        InventoryItem(
          nfcId: nfcId,
          name: itemName,
          scannedAt: now,
          isInBag: true,
        ),
      ];
      action = ScanAction.added;
      scannedItem = InventoryItem(
        nfcId: nfcId,
        name: itemName,
        scannedAt: now,
        isInBag: true,
      );
    }

    state = state.copyWith(
      items: newItems,
      lastScanned: scannedItem,
      lastAction: action,
    );

    // Sync to Firestore
    _syncToFirestore();
  }

  /// Manually add an item without NFC (for testing or manual entry).
  void addItemManually(String name) {
    final nfcId = 'MANUAL_${name.hashCode.toRadixString(16).toUpperCase()}';
    toggleItem(nfcId, name);
  }

  /// Remove an item entirely from the inventory (permanent delete).
  void deleteItem(String nfcId) {
    final newItems = state.items.where((item) => item.nfcId != nfcId).toList();
    state = state.copyWith(items: newItems);
    _syncToFirestore();
  }

  /// Start NFC scanning session.
  void startNfcScan() {
    if (!state.isNfcAvailable) return;

    state = state.copyWith(isScanning: true);

    _nfcScanService.startSession(
      onTagScanned: (nfcId, tagData) {
        // Extract item name from NFC tag data, or use a default
        String itemName = tagData['name'] ??
            tagData['sku'] ??
            'Item ${nfcId.substring(0, (nfcId.length < 6) ? nfcId.length : 6)}';
        
        toggleItem(nfcId, itemName);
      },
      onError: (error) {
        debugPrint("NFC scan error in provider: $error");
        state = state.copyWith(isScanning: false);
      },
    );
  }

  /// Stop NFC scanning session.
  void stopNfcScan() {
    _nfcScanService.stopSession();
    state = state.copyWith(isScanning: false);
  }

  /// Persist current inventory state to Firestore.
  Future<void> _syncToFirestore() async {
    try {
      // Convert to Firestore-compatible map
      Map<String, dynamic> inventoryData = {};
      for (final item in state.items) {
        inventoryData[item.nfcId] = item.toMap();
      }

      // Also update the legacy pocketItems format for backward compatibility
      Map<String, bool> pocketItems = {};
      for (final item in state.items) {
        pocketItems[item.name] = item.isInBag;
      }

      await _firebaseService.updateBagInventory(bagId, inventoryData, pocketItems);
    } catch (e) {
      debugPrint("Failed to sync inventory to Firestore: $e");
    }
  }

  @override
  void dispose() {
    _nfcScanService.stopSession();
    super.dispose();
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  PROVIDERS
// ══════════════════════════════════════════════════════════════════════════════

/// Provider for the NFC scan service (singleton).
final nfcScanServiceProvider = Provider<NfcScanService>((ref) {
  return NfcScanService();
});

/// Provider for bag inventory state, scoped by bag ID.
///
/// Usage: `ref.watch(bagInventoryProvider(bagId))`
final bagInventoryProvider = StateNotifierProvider.family<
    BagInventoryNotifier, BagInventoryState, String>(
  (ref, bagId) {
    return BagInventoryNotifier(
      bagId: bagId,
      firebaseService: FirebaseService(),
    );
  },
);
