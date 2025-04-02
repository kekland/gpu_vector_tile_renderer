import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:gpu_vector_tile_renderer/_controller.dart';
import 'package:gpu_vector_tile_renderer/_debug.dart';
import 'package:gpu_vector_tile_renderer/_renderer.dart';
import 'package:gpu_vector_tile_renderer/_shaders.dart';
import 'package:gpu_vector_tile_renderer/_spec.dart' as spec;
import 'package:gpu_vector_tile_renderer/_vector_tile.dart' as vt;
import 'package:gpu_vector_tile_renderer/src/isolates/isolates.dart';
import 'package:gpu_vector_tile_renderer/src/renderer/atlas/atlas.dart';
import 'package:gpu_vector_tile_renderer/src/renderer/atlas/glyph_manager.dart';
import 'package:gpu_vector_tile_renderer/src/utils/flutter_map/tile_scale_calculator.dart';
import 'package:vector_math/vector_math.dart' as vm32;
import 'package:gpu_vector_tile_renderer/_glyphs.dart' as glyphs_pb;

typedef CreateSingleTileLayerRendererFn = SingleTileLayerRenderer? Function(
  ShaderLibraryProvider shaderLibraryProvider,
  VectorTileLayerRenderOrchestrator orchestrator,
  fm.TileCoordinates coordinates,
  TileContainer container,
  spec.Layer specLayer,
  vt.Layer vtLayer,
);

class VectorTileLayerRenderOrchestrator with ChangeNotifier {
  VectorTileLayerRenderOrchestrator({
    required this.controller,
    required this.shaderLibraryProvider,
    required CreateSingleTileLayerRendererFn createSingleTileLayerRenderer,
  }) : _createSingleTileLayerRenderer = createSingleTileLayerRenderer {
    Isolates.instance.spawn();

    controller.setRenderOrchestrator(this);
    controller.addListener(_onControllerChanged);
    controller.addTileUpdateListener(_onTilesChanged);
    controller.debugAttachment.addListener(_onDebugAttachmentChanged);

    glyphManager = GlyphManager(width: 2048, height: 2048);

    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      _reportDebugInfo();
    });
  }

  /// The controller that this renderer is attached to.
  final VectorTileLayerController controller;

  /// Shader library provider to use
  final ShaderLibraryProvider shaderLibraryProvider;

  /// The function that creates a single tile layer renderer. Should be created by `compile_style.dart` executable.
  final CreateSingleTileLayerRendererFn _createSingleTileLayerRenderer;

  /// Current glyph atlas.
  late final GlyphManager glyphManager;

  final _inProgressMissingGlyphFutures = <(String fontStack, int blockStart), Future<void>>{};

  Future<void> _loadMissingGlyphs(Set<(String fontStack, int blockStart)> missingGlyphs) async {
    final toLoad = missingGlyphs.difference(_inProgressMissingGlyphFutures.keys.toSet());

    // Check for new glyphs to load and start loading them.
    for (final key in toLoad) {
      final future = controller.loadGlyphs(key.$1, key.$2).then((glyphs) {
        glyphManager.addGlyphs(key.$1, glyphs);
        glyphManager.flushTexture();
      }).whenComplete(() {
        _inProgressMissingGlyphFutures.remove(key);
      });

      _inProgressMissingGlyphFutures[key] = future;
    }

    final futures = <Future<void>>[];

    for (final key in missingGlyphs) {
      futures.add(_inProgressMissingGlyphFutures[key]!);
    }

    await futures.wait;
  }

  FutureOr<List<GlyphData>> loadGlyphs(spec.Formatted formatted, String font) {
    final missingGlyphs = <(String fontStack, int blockStart)>{};

    for (final section in formatted.sections) {
      if (section.text == null) continue;

      final text = section.text!;
      final fontStack = section.fontStack ?? font;

      for (final rune in text.runes) {
        if (!glyphManager.hasKey((fontStack, rune))) missingGlyphs.add((fontStack, (rune ~/ 256) * 256));
      }
    }

    List<(glyphs_pb.glyph, AtlasUv)> construct() {
      final result = <(glyphs_pb.glyph, AtlasUv)>[];
      for (final section in formatted.sections) {
        if (section.text == null) continue;

        final text = section.text!;
        final fontStack = section.fontStack ?? font;

        for (final rune in text.runes) {
          result.add(glyphManager.get((fontStack, rune)));
        }
      }

      return result;
    }

    if (missingGlyphs.isNotEmpty) {
      return _loadMissingGlyphs(missingGlyphs).then((_) => construct());
    }

    return construct();
  }

  SingleTileLayerRenderer? createSingleTileLayerRenderer(
    fm.TileCoordinates coordinates,
    TileContainer container,
    spec.Layer specLayer,
    vt.Layer vtLayer,
  ) {
    return _createSingleTileLayerRenderer(shaderLibraryProvider, this, coordinates, container, specLayer, vtLayer);
  }

  List<LayerRenderer>? _layers;

  void _onControllerChanged() {
    if (_layers != null) return;

    // Convert the style layers to layer renderers.
    _layers = createLayerRenderers(this, controller.style);

    for (final layer in _layers!) {
      layer.prepare(PrepareContext(eval: spec.EvaluationContext.empty()));
    }
  }

  void _onDebugAttachmentChanged() {
    notifyListeners();
  }

  void _onTilesChanged() {
    notifyListeners();
  }

  void _reportDebugInfo() {
    if (_layers == null) return;

    for (final layer in _layers!) {
      final count =
          controller.tiles.where((v) => v.isReadyToDisplay).map((v) => v.renderers[layer.specLayer.id]).nonNulls.length;
      controller.debugAttachment.setLayerRendererCount(layer.specLayer.id, count);
    }
  }

  fm.MapCamera? _lastCamera;
  double? _lastTileSize;
  TileScaleCalculator? _tileScaleCalculator;

  void onCameraChanged(fm.MapCamera camera, double tileSize) {
    if (_tileScaleCalculator == null || tileSize != _lastTileSize) {
      _tileScaleCalculator = TileScaleCalculator(crs: camera.crs, tileSize: tileSize);
    }

    if (_lastCamera?.zoom.floor() != camera.zoom.floor()) {
      if (_layers != null) {
        // Re-prepare the layers if the zoom level has changed.
        for (final layer in _layers!) {
          SchedulerBinding.instance.scheduleTask(() async {
            layer.prepare(
              PrepareContext(eval: spec.EvaluationContext.empty().copyWithZoom(camera.zoom.floorToDouble())),
            );
          }, Priority.idle - 1);
        }
      }
    }

    _lastCamera = camera;
    _lastTileSize = tileSize;
    _tileScaleCalculator!.clearCacheUnlessZoomMatches(camera.zoom);
  }

  gpu.Texture? _texture;
  gpu.Texture? _resolveTexture;

  void _setupTextures(ui.Size size, double pixelRatio) {
    final width = (size.width * pixelRatio).ceil();
    final height = (size.height * pixelRatio).ceil();

    if (_texture != null && _texture!.width == width && _texture!.height == height) return;

    if (gpu.gpuContext.doesSupportOffscreenMSAA) {
      // if (false) {
      _texture = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        width,
        height,
        sampleCount: 4,
        format: gpu.PixelFormat.r8g8b8a8UNormIntSRGB,
      );

      _resolveTexture = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        width,
        height,
        sampleCount: 1,
        format: gpu.PixelFormat.r8g8b8a8UNormIntSRGB,
      );
    } else {
      _texture = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        width,
        height,
        format: gpu.PixelFormat.r8g8b8a8UNormIntSRGB,
      );

      _resolveTexture = null;
    }
  }

  ui.Image? draw({
    required ui.Size size,
    required double pixelRatio,
    required fm.MapCamera camera,
    required double tileSize,
  }) {
    if (_layers == null) return null;
    _setupTextures(size, pixelRatio);

    final commandBuffer = gpu.gpuContext.createCommandBuffer();

    final renderTarget = gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(
        texture: _texture!,
        resolveTexture: _resolveTexture,
        clearValue: vm32.Vector4(0, 0, 0, 0),
        storeAction: _resolveTexture != null ? gpu.StoreAction.storeAndMultisampleResolve : gpu.StoreAction.store,
        loadAction: gpu.LoadAction.clear,
      ),
    );

    final pass = commandBuffer.createRenderPass(renderTarget);
    pass.setColorBlendEnable(true);
    pass.setColorBlendEquation(
      gpu.ColorBlendEquation(
        colorBlendOperation: gpu.BlendOperation.add,
        sourceColorBlendFactor: gpu.BlendFactor.one,
        destinationColorBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
        alphaBlendOperation: gpu.BlendOperation.add,
        sourceAlphaBlendFactor: gpu.BlendFactor.one,
        destinationAlphaBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
      ),
    );

    pass.setCullMode(gpu.CullMode.none);

    final renderContext = RenderContext(
      pass: pass,
      size: size,
      pixelRatio: pixelRatio,
      camera: camera,
      unscaledTileSize: tileSize,
      tileScaleCalculator: _tileScaleCalculator!,
      eval: spec.EvaluationContext(geometryType: '', zoom: camera.zoom, locale: spec.Locale(languageCode: 'en')),
    );

    final zoom = camera.zoom;
    for (final layer in _layers!) {
      final specLayer = layer.specLayer;

      if (specLayer.minzoom != null && zoom < specLayer.minzoom!) continue;
      if (specLayer.maxzoom != null && zoom > specLayer.maxzoom!) continue;
      if (controller.debugAttachment.layerState[layer.specLayer.id] == false) continue;

      layer.draw(renderContext);
    }

    commandBuffer.submit();
    return (_resolveTexture ?? _texture)!.asImage();
  }

  void debugDraw(
    Canvas canvas,
    Size size, {
    required fm.MapCamera camera,
    required double tileSize,
  }) {
    debugPaint(
      canvas,
      size,
      controller: controller,
      camera: camera,
      tileSize: tileSize,
    );
  }
}
