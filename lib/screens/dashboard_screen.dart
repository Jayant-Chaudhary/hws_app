import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../../core/theme.dart';
import '../../providers/app_providers.dart';
import '../../models/bag_model.dart';
import '../../services/background_relay_service.dart';
import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../../core/permissions.dart';
import 'package:permission_handler/permission_handler.dart';
import 'owner/map_screen.dart';
import 'owner/bag_inventory_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isRelayRunning = false;

  @override
  void initState() {
    super.initState();
    _checkRelayStatus();
  }

  Future<void> _checkRelayStatus() async {
    final running = await FlutterBackgroundService().isRunning();
    setState(() => _isRelayRunning = running);
  }

  Future<void> _toggleRelay() async {
    final service = FlutterBackgroundService();
    if (_isRelayRunning) {
      service.invoke('stopService');
    } else {
      bool hasPermissions = await PermissionHelper.requestRelayPermissions();
      if (!hasPermissions) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Permissions required. Please grant them in settings."),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () {
                  openAppSettings();
                },
              ),
            ),
          );
        }
        return;
      }
      await BLEBackgroundService.initialize();
      service.startService();
    }
    setState(() => _isRelayRunning = !_isRelayRunning);
  }

  @override
  Widget build(BuildContext context) {
    final bagsAsync = ref.watch(ownedBagsProvider);
    final userAsync = ref.watch(userModelProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("SMART HUB"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppTheme.accentNeonPurple),
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      body: userAsync.when(
        data: (user) => CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Header Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Welcome back,", style: Theme.of(context).textTheme.bodyMedium),
                    Text(user?.displayName ?? "Explorer", 
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: AppTheme.accentNeonCyan, 
                        fontWeight: FontWeight.bold
                      )
                    ),
                  ],
                ),
              ),
            ),
            
            // Relay Status Indicator
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildRelayStatusCard(),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 30)),

            // Bags Section Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("MY BAGS", style: TextStyle(letterSpacing: 2, fontSize: 12, color: AppTheme.textDim)),
                    TextButton.icon(
                      onPressed: () => _showAddBagDialog(context, ref, user?.uid), 
                      icon: const Icon(Icons.add, size: 16), 
                      label: const Text("ADD NEW", style: TextStyle(fontSize: 10))
                    ),
                  ],
                ),
              ),
            ),

            // Bags List
            bagsAsync.when(
              data: (bags) => bags.isEmpty 
                ? const SliverToBoxAdapter(child: _EmptyBagsView())
                : SliverPadding(
                    padding: const EdgeInsets.all(20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _BagCard(bag: bags[index]),
                        childCount: bags.length,
                      ),
                    ),
                  ),
              loading: () => const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
              error: (err, st) => SliverFillRemaining(child: Center(child: Text("Error: $err"))),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(child: Text("Error: $err")),
      ),
    );
  }

  Widget _buildRelayStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: glassDecoration(opacity: 0.1).copyWith(
        gradient: LinearGradient(
          colors: _isRelayRunning 
            ? [AppTheme.accentNeonCyan.withOpacity(0.1), AppTheme.primarySapphire]
            : [AppTheme.textDim.withOpacity(0.05), AppTheme.primarySapphire],
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isRelayRunning ? FontAwesomeIcons.towerBroadcast : FontAwesomeIcons.towerCell,
            color: _isRelayRunning ? AppTheme.accentNeonCyan : AppTheme.textDim,
            size: 30,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("CROWD RELAY", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(
                  _isRelayRunning ? "Status: ACTIVE" : "Status: PAUSED",
                  style: TextStyle(
                    color: _isRelayRunning ? AppTheme.accentNeonCyan : AppTheme.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _isRelayRunning,
            activeColor: AppTheme.accentNeonCyan,
            onChanged: (val) => _toggleRelay(),
          ),
        ],
      ),
    );
  }

  void _showAddBagDialog(BuildContext context, WidgetRef ref, String? ownerId) {
    if (ownerId == null) return;
    
    showDialog(
      context: context,
      builder: (ctx) => _AddBagDialog(ownerId: ownerId, ref: ref),
    );
  }
}

class _AddBagDialog extends StatefulWidget {
  final String ownerId;
  final WidgetRef ref;
  const _AddBagDialog({required this.ownerId, required this.ref});

  @override
  State<_AddBagDialog> createState() => _AddBagDialogState();
}

class _AddBagDialogState extends State<_AddBagDialog> {
  final TextEditingController nameController = TextEditingController();
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  StreamSubscription? _scanSub;
  List<DiscoveredDevice> _discoveredBags = [];
  String? _selectedMac;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  void _startScan() async {
    // 1. You cannot scan for BLE without requesting Android runtime permissions first!
    bool hasPerms = await PermissionHelper.requestRelayPermissions();
    if (!hasPerms || !mounted) return;

    // 2. Start scanning broadly, and manually filter. Android hardware filters often fail 
    // when the Service UUID is inside the secondary ScanResponse payload instead of primary AdvData.
    _scanSub = _ble.scanForDevices(
      withServices: [],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      if (mounted) {
        // Look for our specific ESP32 firmware identifiers
        if (device.name.startsWith("BAG_") || 
            device.serviceUuids.contains(Uuid.parse("c8e9b626-4d0c-48c0-8a1d-72c019d677a2"))) {
          
          setState(() {
            int index = _discoveredBags.indexWhere((d) => d.id == device.id);
            if (index >= 0) {
              _discoveredBags[index] = device;
            } else {
              _discoveredBags.add(device);
            }
          });
        }
      }
    }, onError: (Object err) {
      debugPrint("BLE Scan Error: $err");
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    nameController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (nameController.text.isNotEmpty && _selectedMac != null) {
      // Clean up colons if they exist (Android uses MAC format like CC:11:22...)
      String cleanMac = _selectedMac!.replaceAll(':', '').toLowerCase();

      await widget.ref.read(firebaseServiceProvider).addBag(
        cleanMac,
        widget.ownerId,
        nameController.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.primarySapphire,
      title: const Text("Add Smart Bag", style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Bag Name",
                labelStyle: TextStyle(color: AppTheme.textDim),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.textDim)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.accentNeonCyan)),
              ),
            ),
            const SizedBox(height: 20),
            const Text("Scanning for nearby bags...", style: TextStyle(color: AppTheme.accentNeonCyan, fontSize: 12)),
            const SizedBox(height: 10),
            if (_discoveredBags.isEmpty)
               const Center(child: Padding(
                 padding: EdgeInsets.all(20.0),
                 child: CircularProgressIndicator(color: AppTheme.accentNeonCyan),
               ))
            else
               ConstrainedBox(
                 constraints: const BoxConstraints(maxHeight: 150),
                 child: ListView.builder(
                   shrinkWrap: true,
                   itemCount: _discoveredBags.length,
                   itemBuilder: (ctx, index) {
                     final device = _discoveredBags[index];
                     bool isSelected = _selectedMac == device.id;
                     return ListTile(
                       title: Text(device.name.isEmpty ? "Smart Bag" : device.name, style: const TextStyle(color: Colors.white)),
                       subtitle: Text("ID: ${device.id}", style: const TextStyle(color: AppTheme.textDim, fontSize: 10)),
                       trailing: isSelected ? const Icon(Icons.check_circle, color: AppTheme.accentNeonCyan) : null,
                       tileColor: isSelected ? AppTheme.accentNeonCyan.withOpacity(0.1) : null,
                       onTap: () {
                         setState(() {
                           _selectedMac = device.id;
                         });
                       },
                     );
                   },
                 ),
               ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("CANCEL", style: TextStyle(color: AppTheme.textDim)),
        ),
        ElevatedButton(
          onPressed: _selectedMac != null ? _submit : null,
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentNeonCyan),
          child: const Text("ADD BAG", style: TextStyle(color: Colors.black)),
        ),
      ],
    );
  }
}


class _BagCard extends ConsumerWidget {
  final BagModel bag;
  const _BagCard({required this.bag});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MapScreen(bag: bag))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(20),
        decoration: glassDecoration(opacity: 0.05),
        child: Row(
          children: [
            Stack(
              children: [
                const Icon(FontAwesomeIcons.suitcase, size: 40, color: AppTheme.textLight),
                if (bag.isArmed)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(color: AppTheme.accentNeonCyan, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bag.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Text(
                    bag.isArmed ? "Armed & Secure" : "System Disarmed",
                    style: TextStyle(color: bag.isArmed ? AppTheme.accentNeonCyan : AppTheme.textDim, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.backpack_outlined, color: AppTheme.accentNeonCyan),
              tooltip: 'Bag Inventory',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BagInventoryScreen(bagId: bag.id, bagName: bag.name),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.grey),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppTheme.primarySapphire,
                    title: const Text("Remove Bag?", style: TextStyle(color: Colors.white)),
                    content: const Text("This will permanently detach this bag from your account.", style: TextStyle(color: AppTheme.textDim)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: AppTheme.textDim))),
                      TextButton(
                        onPressed: () {
                           ref.read(firebaseServiceProvider).removeBag(bag.id);
                           Navigator.pop(ctx);
                        },
                        child: const Text("REMOVE", style: TextStyle(color: Colors.red)),
                      )
                    ],
                  )
                );
              },
            ),
            const Icon(Icons.chevron_right, color: AppTheme.textDim),
          ],
        ),
      ),
    );
  }
}

class _EmptyBagsView extends StatelessWidget {
  const _EmptyBagsView();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(FontAwesomeIcons.circleExclamation, size: 40, color: AppTheme.textDim.withOpacity(0.5)),
            const SizedBox(height: 15),
            const Text("Ready to secure your luggage?", style: TextStyle(color: AppTheme.textDim)),
          ],
        ),
      ),
    );
  }
}
