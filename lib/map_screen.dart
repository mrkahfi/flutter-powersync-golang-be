import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:path_provider/path_provider.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _controllerCompleter = Completer<MapLibreMapController>();
  bool _styleLoaded = false;
  String? _localStyleString;

  static const _initial = CameraPosition(
    target: LatLng(-7.550550, 110.748135),
    zoom: 12,
  );

  @override
  void initState() {
    super.initState();
    _initOfflineMap();
  }

  Future<void> _initOfflineMap() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final mbtilesPath = '${docsDir.path}/tiles.mbtiles';
      final file = File(mbtilesPath);

      // Load asset data
      final data = await rootBundle.load('assets/map/tiles.mbtiles');
      final assetSize = data.lengthInBytes;

      if (assetSize == 0) {
        setState(() => _localStyleString = 'ERROR_EMPTY_MBTILES');
        return;
      }

      // Re-copy if file size differs (picks up asset updates between runs)
      final localSize = await file.exists() ? await file.length() : -1;
      if (localSize != assetSize) {
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await file.writeAsBytes(bytes, flush: true);
      }

      // Load style and inject the local mbtiles path
      final styleJsonString = await rootBundle.loadString('assets/map/style.json');
      final updatedStyle = styleJsonString.replaceAll('{path_to_mbtiles}', mbtilesPath);

      setState(() => _localStyleString = updatedStyle);
    } catch (e) {
      debugPrint('Error initializing offline map: $e');
    }
  }

  Future<void> _zoomIn() async {
    final c = await _controllerCompleter.future;
    await c.animateCamera(CameraUpdate.zoomIn());
  }

  Future<void> _zoomOut() async {
    final c = await _controllerCompleter.future;
    await c.animateCamera(CameraUpdate.zoomOut());
  }

  Future<void> _goHome() async {
    final c = await _controllerCompleter.future;
    await c.animateCamera(CameraUpdate.newCameraPosition(_initial));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offline Map')),
      body: _localStyleString == null
          ? const Center(child: CircularProgressIndicator())
          : _localStyleString == 'ERROR_EMPTY_MBTILES'
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text(
                      'Map cannot load: assets/map/tiles.mbtiles is empty.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.redAccent, fontSize: 16),
                    ),
                  ),
                )
              : Stack(
                  children: [
                    MapLibreMap(
                      styleString: _localStyleString!,
                      initialCameraPosition: _initial,
                      onMapCreated: (c) => _controllerCompleter.complete(c),
                      onStyleLoadedCallback: () => setState(() => _styleLoaded = true),
                      myLocationEnabled: true,
                    ),
                    if (_styleLoaded)
                      Positioned(
                        right: 16,
                        bottom: 100,
                        child: Column(
                          children: [
                            _MapButton(icon: Icons.add, onTap: _zoomIn),
                            const SizedBox(height: 8),
                            _MapButton(icon: Icons.remove, onTap: _zoomOut),
                            const SizedBox(height: 8),
                            _MapButton(icon: Icons.explore_rounded, onTap: _goHome),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 22, color: Colors.black87),
        ),
      ),
    );
  }
}
