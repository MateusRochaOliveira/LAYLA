import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../services/ble_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final BleService _bleService = BleService();
  final List<DiscoveredDevice> _devices = [];
  bool _isScanning = false;
  bool _isConnected = false;

  void _toggleScan() {
    if (_isScanning) {
      _bleService.stopScan();
      setState(() => _isScanning = false);
    } else {
      setState(() {
        _devices.clear();
        _isScanning = true;
      });
      _bleService.startScan((device) {
        if (!_devices.any((d) => d.id == device.id)) {
          setState(() => _devices.add(device));
        }
      });
    }
  }

  void _connectToDevice(String id) {
    _bleService.connect(id, (connected) {
      setState(() {
        _isConnected = connected;
        _isScanning = false;
      });
    });
  }

  @override
  void dispose() {
    _bleService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LAYLA'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Connection Status Indicator
            Card(
              color: _isConnected ? Colors.green.shade100 : Colors.red.shade100,
              child: ListTile(
                leading: Icon(
                  _isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: _isConnected ? Colors.green : Colors.red,
                ),
                title: Text(_isConnected ? 'LAYLA Connected' : 'Disconnected'),
              ),
            ),
            const SizedBox(height: 20),
            
            // Scan Trigger Button
            ElevatedButton.icon(
              onPressed: _toggleScan,
              icon: Icon(_isScanning ? Icons.stop : Icons.search),
              label: Text(_isScanning ? 'Stop Scan' : 'Scan for LAYLA'),
            ),
            const SizedBox(height: 20),

            // Discovered Devices List
            Expanded(
              child: ListView.builder(
                itemCount: _devices.length,
                itemBuilder: (context, index) {
                  final device = _devices[index];
                  return ListTile(
                    title: Text(device.name.isEmpty ? 'Unnamed Device' : device.name),
                    subtitle: Text(device.id),
                    trailing: ElevatedButton(
                      onPressed: () => _connectToDevice(device.id),
                      child: const Text('Connect'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}