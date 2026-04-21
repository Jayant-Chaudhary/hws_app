/// Model representing an NFC-tagged item in the bag inventory.
///
/// Each item is uniquely identified by its [nfcId] (the NFC tag UID).
/// The [isInBag] flag indicates whether the item is currently physically
/// inside the bag — toggled on each NFC scan.
class InventoryItem {
  final String nfcId;
  final String name;
  final DateTime scannedAt;
  final bool isInBag;

  const InventoryItem({
    required this.nfcId,
    required this.name,
    required this.scannedAt,
    this.isInBag = true,
  });

  InventoryItem copyWith({
    String? nfcId,
    String? name,
    DateTime? scannedAt,
    bool? isInBag,
  }) {
    return InventoryItem(
      nfcId: nfcId ?? this.nfcId,
      name: name ?? this.name,
      scannedAt: scannedAt ?? this.scannedAt,
      isInBag: isInBag ?? this.isInBag,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nfcId': nfcId,
      'name': name,
      'scannedAt': scannedAt.toIso8601String(),
      'isInBag': isInBag,
    };
  }

  factory InventoryItem.fromMap(Map<String, dynamic> data) {
    return InventoryItem(
      nfcId: data['nfcId'] ?? '',
      name: data['name'] ?? 'Unknown Item',
      scannedAt: DateTime.tryParse(data['scannedAt'] ?? '') ?? DateTime.now(),
      isInBag: data['isInBag'] ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryItem &&
          runtimeType == other.runtimeType &&
          nfcId == other.nfcId;

  @override
  int get hashCode => nfcId.hashCode;

  @override
  String toString() => 'InventoryItem(nfcId: $nfcId, name: $name, isInBag: $isInBag)';
}
