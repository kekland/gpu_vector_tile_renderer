import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:gpu_vector_tile_renderer/src/renderer/atlas/atlas.dart';
import 'package:gpu_vector_tile_renderer/_glyphs.dart' as glyphs;

typedef GlyphAtlasKey = (String fontStacks, int codePoint);

// TODO: Support for different fontstacks.
class GlyphAtlas extends Atlas<GlyphAtlasKey, glyphs.glyph> {
  GlyphAtlas({
    int width = 1024,
    int height = 1024,
  })  : _textureWidth = width,
        _textureHeight = height {
    _createTexture();
  }

  // ignore: prefer_final_fields | Will enable texture resizing in the future
  int _textureWidth;
  int get textureWidth => _textureWidth;

  // ignore: prefer_final_fields | Will enable texture resizing in the future
  int _textureHeight;
  int get textureHeight => _textureHeight;

  gpu.Texture? _texture;
  ByteData? _textureData;

  int get length => _glyphs.length;

  final _glyphs = <GlyphAtlasKey, glyphs.glyph>{};
  final _positions = <GlyphAtlasKey, (int, int)>{};

  void _createTexture() {
    _texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      _textureWidth,
      _textureHeight,
      format: gpu.PixelFormat.r8UNormInt, // Glyphs are 8-bit SDFs
    );

    _textureData = ByteData(_textureWidth * _textureHeight);
  }

  T? _iterateFontStacks<T>(String fontStacks, T? Function(String stack) callback) {
    // The key can contain multiple font stacks. We should check each in order.
    for (final stack in fontStacks.split(',')) {
      final result = callback(stack.trim());
      if (result != null) return result;
    }

    return null;
  }

  @override
  bool hasKey(GlyphAtlasKey key) {
    return _iterateFontStacks(key.$1, (stack) => _glyphs.containsKey((stack, key.$2))) ?? false;
  }

  @override
  glyphs.glyph getMetrics(GlyphAtlasKey key) {
    return _iterateFontStacks(key.$1, (stack) => _glyphs[(stack, key.$2)])!;
  }

  @override
  (int x, int y) getPosition(GlyphAtlasKey key) {
    return _iterateFontStacks(key.$1, (stack) => _positions[(stack, key.$2)])!;
  }

  @override
  gpu.Texture get texture => _texture!;

  var _cursor = (0, 0);
  var _rowHeight = 0;

  void addGlyphs(String fontStacks, glyphs.glyphs glyphs) {
    for (final stack in glyphs.stacks) {
      addStack(fontStacks, stack);
    }
  }

  void addStack(String fontStacks, glyphs.fontstack stack) {
    final _fontStacks = fontStacks.split(',').map((v) => v.trim());

    for (final glyph in stack.glyphs) {
      addGlyph(_fontStacks, glyph);
    }
  }

  void addGlyph(Iterable<String> fontStacks, glyphs.glyph glyph) {
    final width = glyph.width;
    final height = glyph.height;
    final bitmap = glyph.bitmap;

    // Go to next row if glyph doesn't fit
    if (_cursor.$1 + width > _textureWidth) {
      _cursor = (0, _cursor.$2 + _rowHeight);
      _rowHeight = 0;
    }

    // Set texture data
    for (var i = 0; i < bitmap.length; i++) {
      final x = _cursor.$1 + i % width;
      final y = _cursor.$2 + i ~/ width;

      final index = x + y * _textureWidth;
      _textureData!.setUint8(index, bitmap[i]);
    }

    // Update row height
    _rowHeight = max(_rowHeight, height);
    _cursor = (_cursor.$1 + width, _cursor.$2);

    for (final stack in fontStacks) {
      final key = (stack, glyph.id);
      _glyphs[key] = glyph;
      _positions[key] = _cursor;
    }
  }

  void flushTexture() {
    _texture!.overwrite(_textureData!);
  }
}
