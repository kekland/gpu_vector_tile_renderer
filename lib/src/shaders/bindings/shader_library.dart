import 'dart:developer';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:gpu_vector_tile_renderer/_shaders.dart';

/// A class that provides a [gpu.ShaderLibrary] instance.
abstract class ShaderLibraryProvider {
  /// The underlying [gpu.ShaderLibrary] instance.
  gpu.ShaderLibrary get shaderLibrary;

  /// Resolves a shader by its name.
  gpu.Shader? operator [](String name) => shaderLibrary[name];
}

/// A class that provides a static [gpu.ShaderLibrary] instance from an asset.
class AssetShaderLibraryProvider extends ShaderLibraryProvider {
  AssetShaderLibraryProvider(String assetName) : shaderLibrary = gpu.ShaderLibrary.fromAsset(assetName)!;

  @override
  final gpu.ShaderLibrary shaderLibrary;
}

/// A class that provides a hot-reloadable [gpu.ShaderLibrary] instance.
///
/// See [HotReloadableShaderLibraryBindings] for more information.
class HotReloadableShaderLibraryProvider extends ShaderLibraryProvider {
  HotReloadableShaderLibraryProvider(this.assetName) {
    HotReloadableShaderLibraryBindings.instance._attachProvider(assetName, _onShaderLibraryReloaded);
    _finalizer.attach(this, assetName);
  }

  final String assetName;

  static final _finalizer = Finalizer<String>((assetName) {
    HotReloadableShaderLibraryBindings.instance._detachProvider(assetName);
  });

  gpu.ShaderLibrary? _shaderLibrary;

  @override
  gpu.ShaderLibrary get shaderLibrary {
    if (_shaderLibrary == null) {
      _shaderLibrary = gpu.ShaderLibrary.fromAsset(assetName);
      _shaderLibrary!.shaders_.clear();
    }

    return _shaderLibrary!;
  }

  @override
  gpu.Shader? operator [](String name) {
    final suffix = _hotReloadSuffixes[assetName];
    if (suffix == null) return shaderLibrary[name];

    return shaderLibrary['$name#$suffix'];
  }

  void _onShaderLibraryReloaded() {
    if (kDebugMode) print('[#$hashCode] Re-creating shader library for $assetName');
    _shaderLibrary = null;
  }
}

Map<String, String> _hotReloadSuffixes = {};

/// A WidgetsBinding that provides hot-reloadable shader libraries.
///
/// This class works by reading the asset manifest and checking for shaderbundles. The shaderbundles produced by
/// `bin/compile_style.dart` contain a hot-reload suffix that is used to identify the shaderbundle that should be
/// reloaded. This suffix is then used to identify the shader that should be reloaded.
///
/// Instances of [HotReloadableShaderLibraryProvider] can use this class to provide hot-reloadable shader libraries.
class HotReloadableShaderLibraryBindings extends WidgetsFlutterBinding {
  HotReloadableShaderLibraryBindings._() : super() {
    _instance = this;
  }

  static HotReloadableShaderLibraryBindings? _instance;
  static HotReloadableShaderLibraryBindings get instance => _instance!;

  static Future<WidgetsBinding> ensureInitialized() async {
    if (HotReloadableShaderLibraryBindings._instance == null) {
      final instance = HotReloadableShaderLibraryBindings._();
      await instance._prepareShaderBundles();
    }

    return HotReloadableShaderLibraryBindings.instance;
  }

  final _providerCallbacks = <String, VoidCallback>{};
  void _attachProvider(String assetName, VoidCallback callback) {
    _providerCallbacks[assetName] = callback;
  }

  void _detachProvider(String assetName) {
    _providerCallbacks.remove(assetName);
  }

  Future<void> _prepareShaderBundles() async {
    // Get the asset manifest and the list of all shaderbundles.
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final shaderbundleAssets = manifest.listAssets().where((v) => v.endsWith('.shaderbundle'));

    // Read shaderbundles
    for (final key in shaderbundleAssets) {
      rootBundle.evict(key);

      final bytes = await rootBundle.load(key);
      final buffer = ShaderBundle(bytes.buffer.asUint8List());

      // Check for a hot-reload suffix.
      final suffixSet = buffer.shaders?.map((v) => v.name?.split('#').last).toSet();
      if (suffixSet == null) continue;
      if (suffixSet.length != 1) continue;
      if (suffixSet.first == null) continue;

      final suffix = suffixSet.first;
      if (kDebugMode) print('- Hot-reload suffix for $key (${buffer.shaders?.length}): $suffix');

      if (_hotReloadSuffixes[key] != suffix) {
        if (kDebugMode) print('- HOT RELOAD: $key');
      }

      _hotReloadSuffixes[key] = suffix!;
    }

    for (final callback in _providerCallbacks.values) {
      callback();
    }
  }

  @override
  Future<void> performReassemble() async {
    // Check the current libraries and reload them if necessary.
    if (kDebugMode) {
      print('Reassembling shader libraries');
    }

    await _prepareShaderBundles();
    await super.performReassemble();
  }
}
