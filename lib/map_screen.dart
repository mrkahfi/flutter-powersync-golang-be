import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:path_provider/path_provider.dart';

import 'package:archive/archive.dart';

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
    zoom: 16,
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
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        await file.writeAsBytes(bytes, flush: true);
      }

      // Extract map assets zip to local storage
      final zipDir = Directory('${docsDir.path}/map_assets');
      if (!await zipDir.exists()) {
        final zipData = await rootBundle.load('assets/map/map_assets.zip');
        final bytes = zipData.buffer.asUint8List();
        final archive = ZipDecoder().decodeBytes(bytes);
        for (final file in archive) {
          final filename = file.name;
          if (file.isFile) {
            final data = file.content as List<int>;
            final outFile = File('${zipDir.path}/$filename');
            await outFile.create(recursive: true);
            await outFile.writeAsBytes(data);
          } else {
            await Directory('${zipDir.path}/$filename').create(recursive: true);
          }
        }
      }

      // Load style and inject the local mbtiles path
      final styleJsonString = await rootBundle.loadString(
        'assets/map/style.json',
      );
      final updatedStyle = styleJsonString
          .replaceAll('{path_to_mbtiles}', mbtilesPath)
          .replaceAll('{path_to_assets}', zipDir.path);

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

  static const _jakartaPos = CameraPosition(
    target: LatLng(-6.2088, 106.8456),
    zoom: 12,
  );

  static const _surabayaPos = CameraPosition(
    target: LatLng(-7.2575, 112.7521),
    zoom: 12,
  );

  Future<void> _goToSolo() async {
    final c = await _controllerCompleter.future;
    await c.animateCamera(CameraUpdate.newCameraPosition(_initial));
  }

  Future<void> _goToSurabaya() async {
    final c = await _controllerCompleter.future;
    await c.animateCamera(CameraUpdate.newCameraPosition(_surabayaPos));
  }

  Future<void> _goToJakarta() async {
    final c = await _controllerCompleter.future;
    await c.animateCamera(CameraUpdate.newCameraPosition(_jakartaPos));
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
                  onStyleLoadedCallback: () =>
                      setState(() => _styleLoaded = true),
                  myLocationEnabled: true,
                ),
                if (_styleLoaded) ...[
                  Positioned(
                    top: 16,
                    left: 24,
                    right: 24,
                    child: SafeArea(
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextButton.icon(
                                onPressed: _goToJakarta,
                                icon: const Icon(
                                  Icons.location_city,
                                  color: Colors.black87,
                                ),
                                label: const Text(
                                  'Jakarta',
                                  style: TextStyle(color: Colors.black87),
                                ),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 24,
                              color: Colors.grey.shade300,
                            ),
                            Expanded(
                              child: TextButton.icon(
                                onPressed: _goToSolo,
                                icon: const Icon(
                                  Icons.home,
                                  color: Colors.black87,
                                ),
                                label: const Text(
                                  'Solo',
                                  style: TextStyle(color: Colors.black87),
                                ),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 24,
                              color: Colors.grey.shade300,
                            ),
                            Expanded(
                              child: TextButton.icon(
                                onPressed: _goToSurabaya,
                                icon: const Icon(
                                  Icons.home,
                                  color: Colors.black87,
                                ),
                                label: const Text(
                                  'Surabaya',
                                  style: TextStyle(color: Colors.black87),
                                ),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 100,
                    child: Column(
                      children: [
                        _MapButton(icon: Icons.add, onTap: _zoomIn),
                        const SizedBox(height: 8),
                        _MapButton(icon: Icons.remove, onTap: _zoomOut),
                      ],
                    ),
                  ),
                ],
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
