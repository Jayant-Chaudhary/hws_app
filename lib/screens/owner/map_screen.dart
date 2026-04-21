import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/theme.dart';
import '../../models/bag_model.dart';
import '../../providers/app_providers.dart';
import '../../services/owner_ble_service.dart';
import 'bag_inventory_screen.dart';

class MapScreen extends ConsumerStatefulWidget {
  final BagModel bag;
  const MapScreen({super.key, required this.bag});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  GoogleMapController? _mapController;
  OwnerBLEService? _bleService;
  DeviceConnectionState _connectionState = DeviceConnectionState.disconnected;
  String _liveSensorData = "Waiting for data...";
  bool _isSosActive = false;
  bool _isMotionActive = false;
  
  // Custom Dark Map Style
  static const String _mapStyle = '''
[
  { "elementType": "geometry", "stylers": [ { "color": "#242f3e" } ] },
  { "elementType": "labels.text.fill", "stylers": [ { "color": "#746855" } ] },
  { "elementType": "labels.text.stroke", "stylers": [ { "color": "#242f3e" } ] },
  { "featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [ { "color": "#d59563" } ] },
  { "featureType": "poi", "elementType": "labels.text.fill", "stylers": [ { "color": "#d59563" } ] },
  { "featureType": "road", "elementType": "geometry", "stylers": [ { "color": "#38414e" } ] },
  { "featureType": "road", "elementType": "geometry.stroke", "stylers": [ { "color": "#212a37" } ] },
  { "featureType": "water", "elementType": "geometry", "stylers": [ { "color": "#17263c" } ] }
]
''';

  @override
  void initState() {
    super.initState();
    _bleService = OwnerBLEService(
      onSensorData: _handleSensorData,
      onConnectionStateChanged: (state) async {
        if (mounted) setState(() => _connectionState = state);
        if (state == DeviceConnectionState.connected) {
           try {
             // Because Owner is physically next to the bag when connected to BLE,
             // force update Firebase with the Owner's Phone GPS so the map immediately updates
             Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
             await ref.read(firebaseServiceProvider).updateBagLocation(widget.bag.id, GeoPoint(pos.latitude, pos.longitude));
           } catch(e) {
             debugPrint("Map Screen location sync error: $e");
           }
        }
      },
    );
  }

  void _handleSensorData(String data) {
    if (mounted) {
      setState(() {
        _liveSensorData = data;
        // Basic parsing: MOTION:1|GPS:40.7,-74.0|NFC:0|SOS:0
        _isSosActive = data.contains("SOS:1");
        _isMotionActive = data.contains("MOTION:1");
      });
    }
  }

  @override
  void dispose() {
    _bleService?.disconnect();
    super.dispose();
  }

  void _toggleConnection() {
    if (_connectionState == DeviceConnectionState.connected || _connectionState == DeviceConnectionState.connecting) {
      _bleService?.disconnect();
    } else {
      // Assuming widget.bag.id is the MAC address stored as Hex string format.
      // Need to format it back to XX:XX:XX:XX:XX:XX for Android Reactive BLE
      String parsedMac = widget.bag.id.toUpperCase();
      
      // Safety catch: If user manually typed BAG_ prefixes etc.
      if (parsedMac.startsWith("BAG_")) {
        parsedMac = parsedMac.substring(4);
      }
      
      if (parsedMac.length == 12 && !parsedMac.contains(':')) {
         parsedMac = parsedMac.replaceAllMapped(RegExp(r".{2}"), (match) => "${match.group(0)}:");
         parsedMac = parsedMac.substring(0, parsedMac.length - 1);
      }
      
      _bleService?.connect(parsedMac);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to real-time updates for this specific bag
    final bagStream = ref.watch(bagStreamProvider(widget.bag.id));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: const BackButton(color: AppTheme.accentNeonCyan),
        title: Text(widget.bag.name.toUpperCase()),
        actions: [
          if (_connectionState == DeviceConnectionState.connected)
            IconButton(
              icon: const Icon(Icons.backpack, color: AppTheme.accentNeonCyan),
              onPressed: _showInventorySheet,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 15.0),
            child: IconButton(
              icon: Icon(
                _connectionState == DeviceConnectionState.connected ? Icons.bluetooth_connected : Icons.bluetooth,
                color: _connectionState == DeviceConnectionState.connected ? AppTheme.accentNeonCyan : Colors.grey,
              ),
              onPressed: _toggleConnection,
            ),
          )
        ],
      ),
      body: bagStream.when(
        data: (bag) {
          if (bag == null) return const Center(child: Text("Bag data unavailable"));

          final latLng = LatLng(bag.location.latitude, bag.location.longitude);
          
          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(target: latLng, zoom: 15),
                onMapCreated: (controller) {
                  _mapController = controller;
                  _mapController?.setMapStyle(_mapStyle);
                },
                markers: {
                  if (latLng.latitude != 0 && latLng.longitude != 0)
                    Marker(
                      markerId: MarkerId(bag.id),
                      position: latLng,
                      infoWindow: InfoWindow(title: bag.name, snippet: "Last seen: Just now"),
                      icon: _isSosActive 
                         ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)
                         : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
                    ),
                },
              ),

              if (latLng.latitude == 0 && latLng.longitude == 0)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    decoration: glassDecoration(opacity: 0.8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.satellite_alt, color: Colors.grey, size: 40),
                        SizedBox(height: 10),
                        Text("WAITING FOR GPS FIX", style: TextStyle(color: AppTheme.accentNeonCyan, fontWeight: FontWeight.bold)),
                        Text("No location data available yet.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              
              // Telemetry Overlay
              if (_connectionState == DeviceConnectionState.connected)
                Positioned(
                  top: 100,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: glassDecoration(opacity: 0.85).copyWith(
                       border: Border.all(color: _isSosActive ? Colors.red : AppTheme.accentNeonCyan)
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.sensors, color: AppTheme.accentNeonCyan, size: 16),
                            const SizedBox(width: 8),
                            const Text("LIVE TELEMETRY", style: TextStyle(color: AppTheme.accentNeonCyan, fontWeight: FontWeight.bold, fontSize: 12)),
                            const Spacer(),
                            if (_isMotionActive)
                               const Icon(Icons.directions_run, color: Colors.orange, size: 16),
                            if (_isSosActive)
                               const Icon(Icons.warning, color: Colors.red, size: 16),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _liveSensorData,
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ),

              // Floating Overlay Info
              Positioned(
                bottom: 40,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: glassDecoration(opacity: 0.9),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: AppTheme.accentNeonCyan,
                        child: Icon(Icons.location_on, color: AppTheme.primarySapphire),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text("LAST KNOWN LOCATION", style: TextStyle(fontSize: 10, color: AppTheme.textDim, fontWeight: FontWeight.bold)),
                            Text(
                              "${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}",
                              style: const TextStyle(color: AppTheme.textLight, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _connectionState.name.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                color: _connectionState == DeviceConnectionState.connected ? Colors.green : Colors.grey,
                              ),
                            )
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.my_location, color: AppTheme.accentNeonCyan),
                        onPressed: () {
                          _mapController?.animateCamera(CameraUpdate.newLatLng(latLng));
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text("Map Error: $err")),
      ),
    );
  }

  void _showInventorySheet() async {
    // Navigate to the full NFC Bag Inventory screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BagInventoryScreen(
          bagId: widget.bag.id,
          bagName: widget.bag.name,
        ),
      ),
    );
  }

  /// Legacy: Show the old text-based BLE inventory sheet.
  /// Retained for direct BLE hardware memory sync when connected.
  void _showLegacyInventorySheet() async {
    if (_bleService == null) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _InventorySheet(bleService: _bleService!, bagId: widget.bag.id),
    );
  }
}

class _InventorySheet extends StatefulWidget {
  final OwnerBLEService bleService;
  final String bagId;
  const _InventorySheet({required this.bleService, required this.bagId});

  @override
  State<_InventorySheet> createState() => _InventorySheetState();
}

class _InventorySheetState extends State<_InventorySheet> {
  bool _isLoading = true;
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    // ReactiveBle requires mac address with colons, or without, we must parse safely
    // Because owner ble service connect() takes pure parsed mac, let's format it back
    String parsedMac = widget.bagId.toUpperCase();
    if (parsedMac.startsWith("BAG_")) parsedMac = parsedMac.substring(4);
    if (parsedMac.length == 12 && !parsedMac.contains(':')) {
       parsedMac = parsedMac.replaceAllMapped(RegExp(r".{2}"), (match) => "${match.group(0)}:");
       parsedMac = parsedMac.substring(0, parsedMac.length - 1);
    }
    
    String inv = await widget.bleService.readInventory(parsedMac);
    if (mounted) {
      setState(() {
         _controller.text = inv == "EMPTY" ? "" : inv;
         _isLoading = false;
      });
    }
  }

  void _saveInventory() async {
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    
    String parsedMac = widget.bagId.toUpperCase();
    if (parsedMac.startsWith("BAG_")) parsedMac = parsedMac.substring(4);
    if (parsedMac.length == 12 && !parsedMac.contains(':')) {
       parsedMac = parsedMac.replaceAllMapped(RegExp(r".{2}"), (match) => "${match.group(0)}:");
       parsedMac = parsedMac.substring(0, parsedMac.length - 1);
    }

    String newData = _controller.text.trim().isEmpty ? "EMPTY" : _controller.text.trim();
    await widget.bleService.writeInventory(parsedMac, newData);
    
    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Inventory Saved to Bag!")));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20, right: 20, top: 20
      ),
      decoration: BoxDecoration(
        color: AppTheme.primarySapphire.withOpacity(0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("NFC INVENTORY KEEPER", style: TextStyle(color: AppTheme.accentNeonCyan, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 10),
          const Text(
            "Enter your physical items separated by commas (e.g. Laptop, Keys, Wallet). This list is saved permanently into the bag's hardware memory.",
            style: TextStyle(color: AppTheme.textDim, fontSize: 12),
          ),
          const SizedBox(height: 20),
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: AppTheme.accentNeonCyan)))
          else
            TextField(
              controller: _controller,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.black12,
                hintText: "Enter items here...",
                hintStyle: const TextStyle(color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentNeonCyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: _isLoading ? null : _saveInventory,
              child: const Text("HWS SYNC TO BAG", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}


