import 'package:flutter/material.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

Future<void> showGpuTextureDebugSheet(
  BuildContext context, {
  required gpu.Texture texture,
}) async {
  await showModalBottomSheet(
    context: context,
    builder: (context) => _GpuTextureDebugSheet(texture: texture),
  );
}

class _GpuTextureDebugSheet extends StatelessWidget {
  const _GpuTextureDebugSheet({required this.texture});

  final gpu.Texture texture;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: texture.width / texture.height,
      child: CustomPaint(
        painter: _GpuTextureDebugPainter(texture: texture),
        child: SizedBox.expand(),
      ),
    );
  }
}

class _GpuTextureDebugPainter extends CustomPainter {
  _GpuTextureDebugPainter({required this.texture});

  final gpu.Texture texture;

  @override
  void paint(Canvas canvas, Size size) {
    final image = texture.asImage();

    final scale = size.width / image.width;

    canvas.scale(scale);
    canvas.drawImage(image, Offset.zero, Paint());
  }

  @override
  bool shouldRepaint(_GpuTextureDebugPainter oldDelegate) => texture != oldDelegate.texture;
}
