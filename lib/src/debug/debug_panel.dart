import 'package:flutter/material.dart';
import 'package:gpu_vector_tile_renderer/_controller.dart';
import 'package:gpu_vector_tile_renderer/_spec.dart' hide Padding;
import 'package:gpu_vector_tile_renderer/_widgets.dart';
import 'package:gpu_vector_tile_renderer/src/debug/debug_attachment.dart';
import 'package:gpu_vector_tile_renderer/src/debug/gpu_texture_debug_sheet.dart';
import 'package:gpu_vector_tile_renderer/src/debug/widgets.dart';
import 'package:gpu_vector_tile_renderer/src/renderer/render_orchestrator.dart';

class FlutterGpuVectorTileLayerDebugPanel extends StatefulWidget {
  const FlutterGpuVectorTileLayerDebugPanel({super.key, required this.layerKey});

  final GlobalKey<FlutterGpuVectorTileLayerState> layerKey;

  @override
  State<FlutterGpuVectorTileLayerDebugPanel> createState() => _FlutterGpuVectorTileLayerDebugPanelState();
}

class _FlutterGpuVectorTileLayerDebugPanelState extends State<FlutterGpuVectorTileLayerDebugPanel> {
  var _isReady = false;
  late VectorTileLayerController controller;
  late VectorTileLayerRenderOrchestrator orchestrator;

  DebugAttachment get debugAttachment => controller.debugAttachment;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      controller = widget.layerKey.currentState!.controller;
      orchestrator = widget.layerKey.currentState!.orchestrator;

      controller.addListener(_onChanged);
      controller.debugAttachment.addListener(_onChanged);

      _isReady = true;
      setState(() {});
    });
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    if (_isReady) {
      controller.removeListener(_onChanged);
      orchestrator.removeListener(_onChanged);
      controller.debugAttachment.removeListener(_onChanged);
    }

    super.dispose();
  }

  Widget _buildPerformanceSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 16.0),
      child: SizedBox(width: double.infinity, height: 192.0, child: PerformanceOverlay.allEnabled()),
    );
  }

  IconData _resolveLayerIcon(BuildContext context, Layer$Type layerType) {
    return switch (layerType) {
      Layer$Type.background => Icons.format_paint_rounded,
      Layer$Type.fill => Icons.format_color_fill_rounded,
      Layer$Type.line => Icons.line_axis_rounded,
      Layer$Type.symbol => Icons.text_fields_rounded,
      Layer$Type.circle => Icons.circle_rounded,
      Layer$Type.fillExtrusion => Icons.height_rounded,
      Layer$Type.raster => Icons.image_rounded,
      Layer$Type.hillshade => Icons.terrain_rounded,
      Layer$Type.heatmap => Icons.whatshot_rounded,
    };
  }

  List<Widget> _buildControllerSection(BuildContext context) {
    return [
      ListTile(title: Text(controller.style.name!), subtitle: Text('Style')),
      DebugExpansionTile(
        title: Text('Layers (${controller.style.layers.length})'),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    onTap: () {
                      debugAttachment.setAllLayerState(true);
                    },
                    title: Text('Enable all'),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    onTap: () {
                      debugAttachment.setAllLayerState(false);
                    },
                    title: Text('Disable all'),
                  ),
                ),
              ],
            ),
            for (final layer in controller.style.layers)
              HoverListenerWidget(
                onHoverChanged: (isHovering) {
                  debugAttachment.setDebugPaintLayer(layer.id, isHovering);
                },
                child: CheckboxListTile(
                  value: debugAttachment.layerState[layer.id],
                  onChanged: (v) {
                    debugAttachment.setLayerState(layer.id, v!);
                  },
                  title: Text(layer.id),
                  subtitle: Text(
                    '${layer.sourceLayer} : ${debugAttachment.layerRendererCount[layer.id]} renderers',
                  ),
                  secondary: Icon(_resolveLayerIcon(context, layer.type)),
                ),
              ),
          ],
        ),
      ),
      DebugExpansionTile(
        title: Text('Sources (${controller.style.sources.length})'),
        child: Column(
          children: [
            for (final source in controller.style.sources.entries)
              ListTile(
                title: Text(source.key.toString()),
                subtitle: Text(source.value.runtimeType.toString()),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildRenderOrchestratorSection(BuildContext context) {
    return [
      DebugExpansionTile(
        title: Text('Glyph Atlas'),
        child: Column(
          children: [
            ListTile(
              title: Text('Glyphs'),
              subtitle: Text('${orchestrator.glyphAtlas.length}'),
            ),
            ListTile(
              onTap: () {
                showGpuTextureDebugSheet(context, texture: orchestrator.glyphAtlas.texture);
              },
              title: Text('Texture'),
              subtitle: Text('${orchestrator.glyphAtlas.textureWidth}x${orchestrator.glyphAtlas.textureHeight}'),
              trailing: Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) return const SizedBox.shrink();

    return Drawer(
      shape: RoundedRectangleBorder(),
      child: SingleChildScrollView(
        child: SectionList(
          children: [
            DebugExpansionTile(
              leading: Icon(Icons.speed_rounded),
              title: Text('Performance'),
              child: _buildPerformanceSection(context),
            ),
            DebugExpansionTile(
              leading: Icon(Icons.layers_rounded),
              title: Text('Controller'),
              child: SectionList(children: _buildControllerSection(context)),
            ),
            DebugExpansionTile(
              leading: Icon(Icons.design_services_rounded),
              title: Text('Render orchestrator'),
              child: SectionList(children: _buildRenderOrchestratorSection(context)),
            ),
          ],
        ),
      ),
    );
  }
}
