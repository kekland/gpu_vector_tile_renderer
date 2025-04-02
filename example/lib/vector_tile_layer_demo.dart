import 'dart:convert';

import 'package:example/compiled_style/maptiler-streets-v2.gen.dart'
    as maptiler_streets_v2;
import 'package:example/fixtures/style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:gpu_vector_tile_renderer/_shaders.dart';
import 'package:gpu_vector_tile_renderer/gpu_vector_tile_renderer.dart';
import 'package:latlong2/latlong.dart';

class VectorTileLayerDemo extends StatefulWidget {
  const VectorTileLayerDemo({super.key});

  @override
  State<VectorTileLayerDemo> createState() => _DemoPageState();
}

class _DemoPageState extends State<VectorTileLayerDemo> {
  var _showRasterLayer = false;
  var _showVectorLayer = true;
  var _isDebug = false;
  final _layerKey = GlobalKey<FlutterGpuVectorTileLayerState>();
  late final _controller = MapController();
  late final _shaderLibrary = HotReloadableShaderLibraryProvider(
    'lib/compiled_style/${maptiler_streets_v2.shaderBundleName}',
  );

  final _locations = {
    'Zero': (LatLng(0.0, 0.0), 0.0),
    'Europe': (LatLng(51.1657, 10.4515), 4.0),
    'London': (LatLng(51.5074, -0.1278), 13.0),
    'Paris': (LatLng(48.8566, 2.3522), 13.0),
    'Almaty': (LatLng(43.2220, 76.8512), 13.0),
    'New York': (LatLng(40.7128, -74.0060), 13.0),
    'Sydney': (LatLng(-33.8688, 151.2093), 13.0),
    'Tokyo': (LatLng(35.6895, 139.6917), 13.0),
    'Rio de Janeiro': (LatLng(-22.9068, -43.1729), 13.0),
    'Milan': (LatLng(45.4642, 9.1900), 13.0),
    'Cape Town': (LatLng(-33.9249, 18.4241), 13.0),
    'Beijing': (LatLng(39.9042, 116.4074), 13.0),
    'Kuala Lumpur': (LatLng(3.1390, 101.6869), 13.0),
    'Singapore': (LatLng(1.3521, 103.8198), 13.0),
  };

  void _showJumpToLocation() {
    showModalBottomSheet(
      context: context,
      builder:
          (_) => ListView(
            shrinkWrap: true,
            children:
                _locations.entries.map((entry) {
                  return ListTile(
                    title: Text(entry.key),
                    subtitle: Text(
                      '${entry.value.$1.latitude}, ${entry.value.$1.longitude} : ${entry.value.$2}',
                    ),
                    trailing: Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      final location = _locations[entry.key]!;
                      _controller.move(location.$1, location.$2);

                      Navigator.pop(context);
                    },
                  );
                }).toList(),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _controller,
                  options: MapOptions(
                    backgroundColor: theme.colorScheme.surface,
                    interactionOptions: InteractionOptions(
                      flags: InteractiveFlag.all ^ InteractiveFlag.rotate,
                    ),
                    initialZoom: 0.0,
                    initialCenter: const LatLng(0.0, 0.0),
                  ),
                  children: [
                    FlutterGpuVectorTileLayer(
                      key: _layerKey,
                      enableRender: _showVectorLayer,
                      styleProvider: jsonStyleProvider(
                        jsonDecode(maptilerStreetsStyle),
                      ),
                      createSingleTileLayerRenderer:
                          maptiler_streets_v2.createSingleTileLayerRenderer,
                      shaderLibraryProvider: _shaderLibrary,
                    ),
                    if (_showRasterLayer)
                      Opacity(
                        opacity: 0.35,
                        child: TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.app',
                          maxNativeZoom: 19,
                          tileBuilder: (context, child, image) {
                            return Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.black,
                                  width: 0.0,
                                ),
                              ),
                              child: child,
                            );
                          },
                        ),
                      ),
                  ],
                ),

                Positioned(
                  top: 120,
                  left: 16,
                  child: Material(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16.0),
                    clipBehavior: Clip.antiAlias,
                    child: ToggleButtons(
                      isSelected: [
                        _showRasterLayer,
                        _showVectorLayer,
                        _isDebug,
                        false,
                      ],
                      direction: Axis.vertical,
                      onPressed: (index) {
                        if (index == 0) _showRasterLayer = !_showRasterLayer;
                        if (index == 1) _showVectorLayer = !_showVectorLayer;
                        if (index == 2) _isDebug = !_isDebug;
                        if (index == 3) _showJumpToLocation();
                        setState(() {});
                      },
                      children: [
                        Icon(Icons.image_rounded),
                        Icon(Icons.map_rounded),
                        Icon(Icons.bug_report_rounded),
                        Icon(Icons.location_city_rounded),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isDebug)
            SizedBox(
              width: 384.0,
              child: FlutterGpuVectorTileLayerDebugPanel(layerKey: _layerKey),
            ),
        ],
      ),
    );
  }
}
