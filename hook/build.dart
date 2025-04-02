// ignore_for_file: avoid_print

import 'package:logging/logging.dart';
import 'package:native_assets_cli/native_assets_cli.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (config, output) async {
    final logger = Logger('hook/build.dart')..onRecord.listen((record) => print(record.message));

    final nativeBuilders = <Builder>[];

    final packageName = config.packageName;
    nativeBuilders.add(
      CBuilder.library(
        name: packageName,
        assetName: 'gpu_vector_tile_renderer',
        sources: ['src/gpu_vector_tile_renderer.cpp'],
        includes: ['src', 'src/include'],
        language: Language.cpp,
        std: 'c++11',
      ),
    );

    for (final builder in nativeBuilders) {
      await builder.run(input: config, output: output, logger: logger);
    }
    
    // TODO: Copy libc++_shared.so from NDK automatically. Currently I just bundled those under jniLibs.
  });
}
