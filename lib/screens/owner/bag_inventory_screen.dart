import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../models/inventory_item.dart';
import '../../providers/bag_inventory_provider.dart';

/// A premium NFC-based bag inventory screen.
///
/// Displays items currently "In Bag" and "Recently Removed", with a
/// floating action button to start/stop NFC scanning. Each NFC scan
/// toggles the item's state with haptic feedback.
class BagInventoryScreen extends ConsumerStatefulWidget {
  final String bagId;
  final String bagName;

  const BagInventoryScreen({
    super.key,
    required this.bagId,
    required this.bagName,
  });

  @override
  ConsumerState<BagInventoryScreen> createState() => _BagInventoryScreenState();
}

class _BagInventoryScreenState extends ConsumerState<BagInventoryScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _scanFabController;
  final TextEditingController _manualController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _scanFabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanFabController.dispose();
    _manualController.dispose();
    // Stop NFC session if active
    ref.read(bagInventoryProvider(widget.bagId).notifier).stopNfcScan();
    super.dispose();
  }

  void _onScanToggle() {
    final notifier = ref.read(bagInventoryProvider(widget.bagId).notifier);
    final state = ref.read(bagInventoryProvider(widget.bagId));

    if (state.isScanning) {
      notifier.stopNfcScan();
      _scanFabController.reverse();
    } else {
      notifier.startNfcScan();
      _scanFabController.forward();
    }
  }

  void _showManualAddDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.primarySapphire,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Add Item Manually",
            style: TextStyle(color: AppTheme.accentNeonCyan, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: _manualController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "e.g. Laptop, Wallet, Keys...",
            hintStyle: TextStyle(color: AppTheme.textDim.withOpacity(0.5)),
            filled: true,
            fillColor: AppTheme.secondaryNavy,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            prefixIcon: const Icon(Icons.edit, color: AppTheme.accentNeonCyan, size: 18),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL", style: TextStyle(color: AppTheme.textDim)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentNeonCyan,
              foregroundColor: AppTheme.primarySapphire,
            ),
            onPressed: () {
              if (_manualController.text.trim().isNotEmpty) {
                ref
                    .read(bagInventoryProvider(widget.bagId).notifier)
                    .addItemManually(_manualController.text.trim());
                HapticFeedback.mediumImpact();
                _manualController.clear();
                Navigator.pop(ctx);
              }
            },
            child: const Text("ADD", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventoryState = ref.watch(bagInventoryProvider(widget.bagId));

    // Trigger haptic feedback when lastAction changes
    ref.listen<BagInventoryState>(bagInventoryProvider(widget.bagId),
        (prev, next) {
      if (prev?.lastAction != next.lastAction && next.lastScanned != null) {
        if (next.lastAction == ScanAction.added) {
          HapticFeedback.heavyImpact();
          _pulseController.forward(from: 0);
        } else if (next.lastAction == ScanAction.removed) {
          HapticFeedback.mediumImpact();
          _pulseController.forward(from: 0);
        }
      }
    });

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: const BackButton(color: AppTheme.accentNeonCyan),
        title: Text(
          widget.bagName.toUpperCase(),
          style: const TextStyle(
            color: AppTheme.accentNeonCyan,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: AppTheme.accentNeonCyan),
            onPressed: _showManualAddDialog,
            tooltip: "Add item manually",
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.primarySapphire, Color(0xFF050E1A)],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── NFC Status Banner ─────────────────────────────────────
              SliverToBoxAdapter(
                child: _buildNfcStatusBanner(inventoryState),
              ),

              // ── Last Scanned Card ────────────────────────────────────
              if (inventoryState.lastScanned != null)
                SliverToBoxAdapter(
                  child: _buildLastScannedCard(inventoryState),
                ),

              // ── In Bag Section ────────────────────────────────────────
              SliverToBoxAdapter(
                child: _buildSectionHeader(
                  "IN BAG",
                  FontAwesomeIcons.suitcase,
                  AppTheme.accentNeonCyan,
                  inventoryState.inBagItems.length,
                ),
              ),

              if (inventoryState.inBagItems.isEmpty)
                const SliverToBoxAdapter(
                  child: _EmptyStateWidget(
                    icon: FontAwesomeIcons.boxOpen,
                    message: "No items in bag yet",
                    hint: "Scan an NFC tag or add manually",
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.5,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) =>
                          _buildItemCard(inventoryState.inBagItems[index], true),
                      childCount: inventoryState.inBagItems.length,
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // ── Recently Removed Section ──────────────────────────────
              if (inventoryState.removedItems.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _buildSectionHeader(
                    "RECENTLY REMOVED",
                    FontAwesomeIcons.arrowRightFromBracket,
                    AppTheme.textDim,
                    inventoryState.removedItems.length,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.5,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) =>
                          _buildItemCard(inventoryState.removedItems[index], false),
                      childCount: inventoryState.removedItems.length,
                    ),
                  ),
                ),
              ],

              // Bottom padding for FAB
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),

      // ── Floating Scan Button ────────────────────────────────────────
      floatingActionButton: _buildScanFab(inventoryState),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  WIDGET BUILDERS
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildNfcStatusBanner(BagInventoryState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: glassDecoration(opacity: 0.1).copyWith(
          gradient: LinearGradient(
            colors: state.isNfcAvailable
                ? [AppTheme.accentNeonCyan.withOpacity(0.08), Colors.transparent]
                : [AppTheme.alertRed.withOpacity(0.08), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            Icon(
              state.isNfcAvailable ? Icons.nfc : Icons.nfc_rounded,
              color: state.isNfcAvailable ? AppTheme.accentNeonCyan : AppTheme.alertRed,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.isNfcAvailable ? "NFC READY" : "NFC UNAVAILABLE",
                    style: TextStyle(
                      color: state.isNfcAvailable ? AppTheme.accentNeonCyan : AppTheme.alertRed,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Text(
                    state.isNfcAvailable
                        ? "Tap the scan button to start tracking items"
                        : "This device doesn't support NFC scanning",
                    style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (state.isScanning)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.accentNeonCyan,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastScannedCard(BagInventoryState state) {
    final item = state.lastScanned!;
    final wasAdded = state.lastAction == ScanAction.added;
    final accentColor = wasAdded ? AppTheme.accentNeonCyan : AppTheme.alertRed;
    final actionLabel = wasAdded ? "ADDED TO BAG" : "REMOVED FROM BAG";
    final actionIcon = wasAdded ? FontAwesomeIcons.circleCheck : FontAwesomeIcons.circleXmark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 5, 20, 15),
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.all(18),
            decoration: glassDecoration(opacity: 0.15).copyWith(
              border: Border.all(
                color: accentColor.withOpacity(
                  0.3 + (_pulseController.value * 0.5),
                ),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withOpacity(0.1 * (1 - _pulseController.value)),
                  blurRadius: 20 * _pulseController.value,
                  spreadRadius: 5 * _pulseController.value,
                ),
              ],
            ),
            child: child,
          );
        },
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(actionIcon, color: accentColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      color: AppTheme.textLight,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    actionLabel,
                    style: TextStyle(
                      color: accentColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Scanned at ${DateFormat('hh:mm a').format(item.scannedAt)}",
                    style: const TextStyle(color: AppTheme.textDim, fontSize: 10),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                const Text("NFC ID", style: TextStyle(color: AppTheme.textDim, fontSize: 8, letterSpacing: 1)),
                const SizedBox(height: 2),
                Text(
                  item.nfcId.length > 8 ? '${item.nfcId.substring(0, 8)}...' : item.nfcId,
                  style: TextStyle(
                    color: accentColor.withOpacity(0.7),
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(height: 1, color: color.withOpacity(0.15)),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(InventoryItem item, bool isInBag) {
    final accentColor = isInBag ? AppTheme.accentNeonCyan : AppTheme.textDim;
    final bgOpacity = isInBag ? 0.08 : 0.03;

    return Dismissible(
      key: Key(item.nfcId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.transparent, AppTheme.alertRed.withOpacity(0.3)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_sweep, color: AppTheme.alertRed),
      ),
      confirmDismiss: (_) async {
        return await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.primarySapphire,
            title: const Text("Delete Item?", style: TextStyle(color: Colors.white)),
            content: Text(
              "Permanently remove \"${item.name}\" from inventory?",
              style: const TextStyle(color: AppTheme.textDim),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("CANCEL", style: TextStyle(color: AppTheme.textDim)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("DELETE", style: TextStyle(color: AppTheme.alertRed)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) {
        ref.read(bagInventoryProvider(widget.bagId).notifier).deleteItem(item.nfcId);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: glassDecoration(opacity: bgOpacity).copyWith(
          border: Border.all(color: accentColor.withOpacity(0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    style: TextStyle(
                      color: isInBag ? AppTheme.textLight : AppTheme.textDim,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  isInBag ? Icons.check_circle : Icons.cancel,
                  color: isInBag ? AppTheme.accentNeonCyan : AppTheme.alertRed.withOpacity(0.5),
                  size: 20,
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isInBag ? "IN BAG" : "OUT OF BAG",
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('MMM d, hh:mm a').format(item.scannedAt),
                  style: TextStyle(
                    color: AppTheme.textDim.withOpacity(0.6),
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanFab(BagInventoryState state) {
    final isScanning = state.isScanning;
    final isAvailable = state.isNfcAvailable;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: isScanning ? 200 : 180,
      height: 54,
      child: FloatingActionButton.extended(
        heroTag: "nfc_scan_fab",
        onPressed: isAvailable ? _onScanToggle : null,
        backgroundColor:
            isScanning ? AppTheme.alertRed.withOpacity(0.9) : AppTheme.accentNeonCyan,
        foregroundColor: isScanning ? Colors.white : AppTheme.primarySapphire,
        elevation: isScanning ? 12 : 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Icon(
          isScanning ? Icons.stop_rounded : Icons.nfc_rounded,
          size: 22,
        ),
        label: Text(
          isScanning ? "STOP SCANNING" : "TAP TO SCAN",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
//  HELPER WIDGETS
// ════════════════════════════════════════════════════════════════════════════════

class _EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String message;
  final String hint;

  const _EmptyStateWidget({
    required this.icon,
    required this.message,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 40),
        child: Column(
          children: [
            Icon(icon, size: 40, color: AppTheme.textDim.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(color: AppTheme.textDim, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              hint,
              style: TextStyle(
                color: AppTheme.textDim.withOpacity(0.5),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
