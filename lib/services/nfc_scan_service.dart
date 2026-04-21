import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';

/// Service that wraps [NfcManager] to provide NFC tag scanning
/// with built-in debounce protection against double-scans.
///
/// Usage:
/// ```dart
/// final nfcService = NfcScanService();
/// if (await nfcService.isNfcAvailable()) {
///   nfcService.startSession(onTagScanned: (nfcId, tagData) { ... });
/// }
/// ```
class NfcScanService {
  /// Minimum interval between two accepted scans (prevents double-tap).
  static const Duration debounceDuration = Duration(milliseconds: 500);

  DateTime? _lastScanTime;
  bool _isSessionActive = false;

  /// Whether NFC hardware is available on this device.
  Future<bool> isNfcAvailable() async {
    try {
      return await NfcManager.instance.isAvailable();
    } catch (e) {
      debugPrint("NFC availability check failed: $e");
      return false;
    }
  }

  /// Whether a scan session is currently running.
  bool get isSessionActive => _isSessionActive;

  /// Start a continuous NFC scan session.
  ///
  /// [onTagScanned] fires with the NFC tag UID (hex string) and any
  /// NDEF text records found on the tag as a map.
  ///
  /// The session automatically applies a 500ms debounce — rapid re-scans
  /// of the same or different tags within the window are silently ignored.
  ///
  /// [onError] is called if the NFC session encounters an error.
  void startSession({
    required Function(String nfcId, Map<String, String> tagData) onTagScanned,
    Function(String error)? onError,
  }) {
    _isSessionActive = true;

    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        // ── Debounce guard ──────────────────────────────────────────────
        final now = DateTime.now();
        if (_lastScanTime != null &&
            now.difference(_lastScanTime!) < debounceDuration) {
          debugPrint("NFC scan debounced — ignoring rapid re-scan");
          return;
        }
        _lastScanTime = now;

        // ── Extract NFC UID ─────────────────────────────────────────────
        String nfcId = _extractTagId(tag);
        if (nfcId.isEmpty) {
          debugPrint("NFC tag has no readable identifier");
          return;
        }

        // ── Read NDEF records for item metadata ─────────────────────────
        Map<String, String> tagData = _extractNdefData(tag);

        debugPrint("NFC Tag Scanned — ID: $nfcId, Data: $tagData");
        onTagScanned(nfcId, tagData);
      },
      onError: (error) async {
        debugPrint("NFC Session Error: $error");
        onError?.call(error.toString());
      },
    );
  }

  /// Stop the current NFC scan session.
  void stopSession() {
    _isSessionActive = false;
    try {
      NfcManager.instance.stopSession();
    } catch (e) {
      debugPrint("NFC stop session error: $e");
    }
  }

  /// Extract the unique tag identifier from the NFC tag.
  ///
  /// Tries NfcA (Android), then MiFare/ISO (iOS), and falls back to
  /// Ndef tag identifier bytes.
  String _extractTagId(NfcTag tag) {
    // Try NfcA (most common Android NFC tags)
    final nfcA = NfcA.from(tag);
    if (nfcA != null) {
      return _bytesToHex(nfcA.identifier);
    }

    // Try MiFare (common on iOS)
    final miFare = MiFare.from(tag);
    if (miFare != null) {
      return _bytesToHex(miFare.identifier);
    }

    // Try ISO 15693
    final iso15693 = Iso15693.from(tag);
    if (iso15693 != null) {
      return _bytesToHex(iso15693.identifier);
    }

    // Try ISO 7816 (smart cards)
    final iso7816 = Iso7816.from(tag);
    if (iso7816 != null) {
      return _bytesToHex(iso7816.identifier);
    }

    // Fallback: try NDEF
    final ndef = Ndef.from(tag);
    if (ndef != null) {
      // Use the tag's data hash as a pseudo-ID
      return tag.data.hashCode.toRadixString(16).toUpperCase();
    }

    return '';
  }

  /// Read NDEF text records from the tag.
  ///
  /// Returns a map with keys like 'name', 'sku', etc. from the NDEF
  /// payload. If the tag has a single text record, it's returned as 'name'.
  Map<String, String> _extractNdefData(NfcTag tag) {
    Map<String, String> data = {};

    final ndef = Ndef.from(tag);
    if (ndef == null || ndef.cachedMessage == null) return data;

    for (final record in ndef.cachedMessage!.records) {
      // Only process text (T) records
      if (record.typeNameFormat == NdefTypeNameFormat.nfcWellknown) {
        try {
          // NDEF Text Record: first byte = status (encoding + language length)
          // then language code, then the actual text
          if (record.payload.isNotEmpty) {
            int langLen = record.payload[0] & 0x3F;
            String text = String.fromCharCodes(
              record.payload.sublist(1 + langLen),
            );

            // If text contains key:value format, parse it
            if (text.contains(':')) {
              List<String> parts = text.split(':');
              data[parts[0].trim().toLowerCase()] = parts.sublist(1).join(':').trim();
            } else {
              // Use as item name
              data['name'] = text.trim();
            }
          }
        } catch (e) {
          debugPrint("Failed to parse NDEF record: $e");
        }
      }
    }

    return data;
  }

  /// Convert bytes to uppercase hex string (e.g., [0xA4, 0xB2] → "A4B2").
  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');
  }
}
