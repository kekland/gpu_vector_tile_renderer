import 'package:gpu_vector_tile_renderer/_glyphs.dart' as glyphs_pb;
import 'package:gpu_vector_tile_renderer/_utils.dart';

/// Function signature for a glyph resolver function.
typedef GlyphResolverFn = Future<glyphs_pb.glyphs> Function(String glyphsUrl, String fontstack, int rangeFrom);

/// A default glyph resolver function.
Future<glyphs_pb.glyphs> defaultGlyphResolver(String glyphsUrl, String fontstack, int rangeFrom) async {
  assert(rangeFrom % 256 == 0, 'rangeFrom must be a multiple of 256');
  final rangeTo = rangeFrom + 255;

  final url = glyphsUrl.replaceFirst('{fontstack}', fontstack).replaceFirst('{range}', '$rangeFrom-$rangeTo');
  final response = await zonedHttpGet(Uri.parse(url));
  return glyphs_pb.glyphs.fromBuffer(response.bodyBytes);
}
