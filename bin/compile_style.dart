// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flat_buffers/flat_buffers.dart';
import 'package:flutter_gpu_shaders/environment.dart';
import 'package:gpu_vector_tile_renderer/_spec.dart';
import 'package:gpu_vector_tile_renderer/src/shaders/serializer/parsed_shader.dart';
import 'package:gpu_vector_tile_renderer/src/shaders/serializer/shader_writer.dart';
import 'package:gpu_vector_tile_renderer/src/shaders/shader_bundle/shader_bundle_impeller.fb.shaderbundle_generated.dart';
import 'package:gpu_vector_tile_renderer/src/style_precompiler/style_precompiler.dart';

import '../tool/shaders/generate_shaders.dart';

Future<void> main(List<String> args) async {
  generateShaders(isCallingFromExec: true);

  // Args: `compile_style.dart <style_file_path> <out_directory_path>`
  // For now, those are hardcoded.
  final styleFilePath = 'scratchpad/maptiler-streets-v2.json';
  final outDirectoryPath = 'example/lib/compiled_style';

  // Suffix used for shader hot-reload.
  final hotReloadSuffix = Random().nextInt(1000000).toRadixString(16);

  final styleFileName = styleFilePath.split('/').last.split('.').first;

  print('Compiling style: $styleFilePath, output: $outDirectoryPath, using hot reload suffix: $hotReloadSuffix');

  final tempDir = Directory.systemTemp.createTempSync('gpu_vector_tile_renderer');
  print('- Created temp directory: ${tempDir.absolute.path}');

  final styleFile = File(styleFilePath);
  final outDirectory = Directory(outDirectoryPath);

  final style = Style.fromJson(jsonDecode(styleFile.readAsStringSync()));
  print('- Read style file: ${style.name}, layers: ${style.layers.length}');

  var (shaders, rendererCode, shaderBundleCode) = precompileStyle(
    styleFileName,
    style,
    hotReloadSuffix: hotReloadSuffix,
  );

  print('- Precompiled style: ${shaders.length} shaders');

  for (final shader in shaders) {
    final File file;

    if (shader is ParsedShaderVertex) {
      file = File('${tempDir.path}/${shader.name}.vert');
    } else {
      file = File('${tempDir.path}/${shader.name}.frag');
    }

    file.writeAsStringSync(writeShader(shader));
  }

  print('- Wrote shaders to temp directory');

  final impellercExec = await findImpellerC();
  final tempShaderbundleOutFile = File('${tempDir.path}/$styleFileName.shaderbundle');
  final shaderbundleOutFile = File('${outDirectory.path}/$styleFileName.shaderbundle');
  final shaderbundleHashOutFile = File('${outDirectory.path}/$styleFileName.shaderbundle.hash');

  ShaderBundle? oldShaderBundle;
  final shadersToIgnore = <String>[];

  if (shaderbundleOutFile.existsSync() && shaderbundleHashOutFile.existsSync()) {
    print('- Existing shaderbundle found. Proceeding with incremental compilation.');
    oldShaderBundle = ShaderBundle(shaderbundleOutFile.readAsBytesSync());
    final shaderHashes = shaderbundleHashOutFile.readAsStringSync().split('\n');

    if (shaderHashes.length != shaders.length) {
      print('Shader count mismatch: ${shaderHashes.length} != ${shaders.length}. Proceeding with full compilation.');
    } else {
      for (final shader in shaders) {
        final oldHash = shaderHashes.firstWhereOrNull(
          (element) => element.startsWith('${shader.name}${shader.type.fileExtension}:'),
        );

        if (oldHash == null) {
          print('Shader ${shader.name} not found in old hash list. Proceeding with full compilation.');
          shadersToIgnore.clear();
          break;
        }

        final newHash = '${shader.name}${shader.type.fileExtension}:${writeShader(shader).hashCode}';
        if (oldHash == newHash) {
          final ext = shader.type == ShaderType.vertex ? 'vert' : 'frag';
          shadersToIgnore.add('${shader.name}_$ext');
        }
      }
    }

    if (shadersToIgnore.isEmpty) {
      oldShaderBundle = null;
    } else {
      print('Ignoring shaders: ${shadersToIgnore.length}');

      final shaderBundleJson = jsonDecode(shaderBundleCode) as Map<String, dynamic>;
      shaderBundleJson.removeWhere((key, _) {
        for (final ignore in shadersToIgnore) {
          if (key.startsWith(ignore)) return true;
        }

        return false;
      });

      shaderBundleCode = jsonEncode(shaderBundleJson);
    }
  }

  final impellercArgs = [
    '--sl=${tempShaderbundleOutFile.absolute.path}',
    '--shader-bundle=$shaderBundleCode',
  ];

  print('- Starting shader compilation, impellerc: ${impellercExec.toFilePath()}');
  final impellerc = Process.runSync(impellercExec.toFilePath(), impellercArgs, workingDirectory: tempDir.path);
  if (impellerc.exitCode != 0) {
    throw Exception('Failed to build shader bundle: ${impellerc.stderr}\n${impellerc.stdout}');
  }

  print('- Shader compilation complete, shaderbundle written to ${tempShaderbundleOutFile.absolute.path}');

  if (oldShaderBundle != null) {
    print('- Merging with old shaderbundle');
    final newShaderBundle =
        shadersToIgnore.length == shaders.length ? null : ShaderBundle(tempShaderbundleOutFile.readAsBytesSync());

    final fbShaders = <ShaderT>[];

    for (final oldShaders in oldShaderBundle.shaders!) {
      final t = oldShaders.unpack();
      final rawName = t.name!.split('#').first;

      if (shadersToIgnore.contains(rawName)) {
        // Update hot reload suffix
        t.name = '${t.name!.split('#').first}#$hotReloadSuffix';
        fbShaders.add(t);
      } else {
        // Use new shader
        final newShader = newShaderBundle!.shaders!.firstWhere((e) => e.name!.startsWith(rawName));
        fbShaders.add(newShader.unpack());
      }
    }

    print('- Merged ${fbShaders.length} shaders');

    final t = ShaderBundleT();
    final fbb = Builder();

    t.shaders = fbShaders;
    fbb.finish(t.pack(fbb));

    shaderbundleOutFile.writeAsBytesSync(fbb.buffer);
    print('- Merged shaderbundle written to ${shaderbundleOutFile.absolute.path}');
  } else {
    tempShaderbundleOutFile.copySync(shaderbundleOutFile.path);
    print('- Shaderbundle written to ${shaderbundleOutFile.absolute.path}');
  }

  print('- Writing shader hashes');
  final shaderbundleHashOut = <String>[];
  for (final shader in shaders) {
    shaderbundleHashOut.add('${shader.name}${shader.type.fileExtension}:${writeShader(shader).hashCode}');
  }
  shaderbundleHashOutFile.writeAsStringSync(shaderbundleHashOut.join('\n'));
  print('- Shader hashes written to ${shaderbundleHashOutFile.absolute.path}');

  final dartRenderersOutFile = File('${outDirectory.path}/$styleFileName.gen.dart');
  dartRenderersOutFile.writeAsStringSync(rendererCode, flush: true);
  print('- Wrote Dart renderers to ${dartRenderersOutFile.absolute.path}');

  print('- Formatting');
  final dartfmt = Process.runSync('dart', ['format', dartRenderersOutFile.absolute.path]);
  if (dartfmt.exitCode != 0) {
    throw Exception('Failed to format Dart renderers: ${dartfmt.stderr}\n${dartfmt.stdout}');
  }
}
