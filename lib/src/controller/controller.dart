import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:gpu_vector_tile_renderer/_controller.dart';
import 'package:gpu_vector_tile_renderer/_renderer.dart';
import 'package:gpu_vector_tile_renderer/_spec.dart' as spec;
import 'package:gpu_vector_tile_renderer/_glyphs.dart' as glyphs_pb;
import 'package:gpu_vector_tile_renderer/src/debug/debug_attachment.dart';
import 'package:gpu_vector_tile_renderer/src/utils/flutter_map/tile_bounds/tile_bounds.dart';
import 'package:gpu_vector_tile_renderer/src/utils/flutter_map/tile_range_calculator.dart';
import 'package:logging/logging.dart';

final _logger = Logger('MapController');

class VectorTileLayerController with ChangeNotifier {
  VectorTileLayerController({
    required this.styleProvider,
    required this.tickerProvider,
    this.sourceResolver = defaultSourceResolver,
    this.vectorTileResolver = defaultVectorTileResolver,
    this.spriteSourceResolver = defaultSpriteSourceResolver,
    this.glyphResolver = defaultGlyphResolver,
  }) : debugAttachment = DebugAttachment();

  /// A provider for the style.
  final StyleProviderFn styleProvider;

  /// A resolver for sources.
  ///
  /// See [defaultSourceResolver] for an example.
  final SourceResolverFn sourceResolver;

  /// A resolver for vector tiles.
  ///
  /// See [defaultVectorTileResolver] for an example.
  final VectorTileResolverFn vectorTileResolver;

  /// A resolver for sprites.
  ///
  /// See [defaultSpriteSourceResolver] for an example.
  final SpriteSourceResolverFn spriteSourceResolver;

  /// A resolver for glyphs.
  ///
  /// See [defaultGlyphResolver] for an example.
  final GlyphResolverFn glyphResolver;

  /// A ticker provider for internal animations.
  final TickerProvider tickerProvider;

  /// A render orchestrator for this controller.
  VectorTileLayerRenderOrchestrator? _renderOrchestrator;
  VectorTileLayerRenderOrchestrator get renderOrchestrator => _renderOrchestrator!;

  /// The debug attachment for this controller. This is used by the debug panel.
  final DebugAttachment debugAttachment;

  void setRenderOrchestrator(VectorTileLayerRenderOrchestrator orchestrator) {
    _renderOrchestrator = orchestrator;
  }

  spec.Style? _style;
  spec.Style get style => _style!;
  bool get isLoaded => _style != null;

  /// Loads the style and any other resources from [styleProvider].
  Future<void> load() async {
    if (isLoaded) return;
    _logger.info('Loading style');

    try {
      _style = await styleProvider();
      await Future.wait([_loadSources()]);

      _logger.info('Style loaded: ${style.name}, ${style.sources.length} sources, ${style.layers.length} layers');
      notifyListeners();

      debugAttachment.setup(this);

      renderOrchestrator.loadGlyphs(spec.Formatted.fromJson('Hello, world!'), 'Open Sans');

      // Trigger camera changed to set the initial visible tiles
      if (_lastCamera != null) onCameraChanged(_lastCamera!, _lastTileSize!);
    } catch (e) {
      _logger.severe('Failed to load style', e);
      rethrow;
    }
  }

  /// Loads sources from the style. Called internally from [load]
  Future<void> _loadSources() async {
    _logger.info('Loading sources');

    final resolvedSources = <Object, spec.Source>{};

    await Future.wait(
      style.sources.entries.map((entry) async {
        final source = await sourceResolver(entry.value);
        resolvedSources[entry.key] = source;

        _logger.info('Resolved source: ${entry.key}');
      }),
    );

    _style = _style!.copyWith(sources: resolvedSources);
  }

  /// Loads glyphs for a given string.
  Future<glyphs_pb.glyphs> loadGlyphs(String fontstack, int blockStartFrom) async {
    return glyphResolver(style.glyphs!, fontstack, blockStartFrom);
  }

  fm.MapCamera? _lastCamera;
  double? _lastTileSize;
  TileRangeCalculator? _tileRangeCalculator;
  Map<Object, TileBounds>? _tileBoundsForSources;

  /// Called when the ancestor [FlutterMap] camera changes.
  ///
  /// Will trigger updates to the visible tiles.
  ///
  /// If the style hasn't been loaded yet, it will trigger updates once it's loaded, using the latest state of the
  /// camera passed to this method.
  void onCameraChanged(fm.MapCamera camera, double tileSize) {
    _lastCamera = camera;
    _lastTileSize = tileSize;
    if (!isLoaded) return;

    final crs = camera.crs;

    // Check if we need to update the tile range calculator
    if (_tileRangeCalculator?.tileSize != tileSize) _tileRangeCalculator = TileRangeCalculator(tileSize: tileSize);

    // Check if we need to update the tile bounds for sources
    _tileBoundsForSources ??= {};
    for (final entry in style.sources.entries) {
      final key = entry.key;
      final source = entry.value;

      final existingBounds = _tileBoundsForSources![key];
      if (existingBounds != null && !existingBounds.shouldReplace(crs, tileSize, null)) continue;

      if (source is spec.SourceVector && source.tiles != null) {
        final bounds = fm.LatLngBounds.unsafe(
          north: source.bounds[3].toDouble(),
          east: source.bounds[2].toDouble(),
          south: source.bounds[1].toDouble(),
          west: source.bounds[0].toDouble(),
        );

        _tileBoundsForSources![key] = TileBounds(crs: crs, tileSize: tileSize, latLngBounds: bounds);
      }
    }

    final zoom = camera.zoom;
    final tileZoom = (zoom.round() - 1.0).clamp(0, double.infinity).toInt();

    // Contains the map of now visible tiles with the containing sources
    final visibleTiles = <fm.TileCoordinates, List<Object>>{};

    // Calculate the visible tiles
    for (final entry in _tileBoundsForSources!.entries) {
      final sourceKey = entry.key;
      final source = style.sources[sourceKey]! as spec.SourceVector;
      final bounds = entry.value;

      // todo: clean this up
      final zoomForSource = tileZoom.clamp(source.minzoom, source.maxzoom).toInt();
      final boundsAtZoom = bounds.atZoom(zoomForSource);
      final tileRange = _tileRangeCalculator!.calculate(camera: camera, tileZoom: zoomForSource);
      final coordinates = boundsAtZoom.validCoordinatesIn(tileRange).map(boundsAtZoom.wrap).toSet();

      for (final coordinate in coordinates) {
        visibleTiles.putIfAbsent(coordinate, () => []).add(sourceKey);
      }
    }

    // Currently active tiles
    final currentTileCoordinates = _tiles.keys.toSet();

    // Remove tiles that are no longer visible
    final visibleTileCoordinates = visibleTiles.keys.toSet();
    final tilesToRemove = currentTileCoordinates.difference(visibleTileCoordinates);
    for (final tile in tilesToRemove) {
      _tiles[tile]!.animatedDispose().then((_) {
        _tiles.remove(tile);
        _onTilesUpdated();
      });
    }

    // Add new tiles
    final tilesToAdd = visibleTileCoordinates.difference(currentTileCoordinates);
    for (final tile in tilesToAdd) {
      final container = TileContainer(controller: this, coordinates: tile, sourceKeys: visibleTiles[tile]!);
      _tiles[tile] = container;

      // When the tile is updated, notify the listeners
      container.addListener(_onTilesUpdated);
    }

    if (tilesToRemove.isNotEmpty || tilesToAdd.isNotEmpty) {
      _logger.info('Tiles: ${_tiles.length}, removed: ${tilesToRemove.length}, added: ${tilesToAdd.length}');
    }

    _onTilesUpdated();
  }

  /// Called then a hot-reload is triggered.
  void onReassemble() {
    _logger.info('Reassembling');
    for (final tile in _tiles.values) tile.dispose();
    _tiles.clear();

    onCameraChanged(_lastCamera!, _lastTileSize!);
  }

  /// Currently active tiles.
  ///
  /// Tiles stored here are **visible** on the screen, but not necessarily loaded/prepared.
  final _tiles = <fm.TileCoordinates, TileContainer>{};

  /// All currently active tiles.
  Iterable<TileContainer> get tiles => _tiles.values;

  /// List of listeners that will be called when any tile is updated, or added/removed.
  final _tileUpdateListeners = <VoidCallback>{};

  void _onTilesUpdated() {
    for (final listener in _tileUpdateListeners) {
      listener();
    }
  }

  /// Adds a listener that will be called when any tile is added, updated, or removed.
  void addTileUpdateListener(VoidCallback listener) {
    _tileUpdateListeners.add(listener);
  }

  /// Removes a listener that was added with [addTileUpdateListener].
  void removeTileUpdateListener(VoidCallback listener) {
    _tileUpdateListeners.remove(listener);
  }

  @override
  void dispose() {
    for (final tile in _tiles.values) {
      tile.dispose();
    }

    _tileUpdateListeners.clear();
    debugAttachment.dispose();
    super.dispose();
  }
}
