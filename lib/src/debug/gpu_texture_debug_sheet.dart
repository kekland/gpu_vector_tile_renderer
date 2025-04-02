import 'package:flutter/material.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

Future<void> showGpuTextureDebugSheet(
  BuildContext context, {
  required gpu.Texture texture,
}) async {
  await showDialog(
    context: context,
    builder: (context) => Dialog.fullscreen(child: _GpuTextureDebugSheet(texture: texture)),
  );
}

class _GpuTextureDebugSheet extends StatelessWidget {
  const _GpuTextureDebugSheet({required this.texture});

  final gpu.Texture texture;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      maxScale: 100.0,
      child: AspectRatio(
        aspectRatio: texture.width / texture.height,
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: texture.width.toDouble(),
            height: texture.height.toDouble(),
            child: Stack(
              children: [
                CustomPaint(
                  painter: _GpuTextureDebugPainter(texture: texture),
                  child: SizedBox.expand(),
                ),
                Positioned.fill(
                  child: GridPaper(
                    color: Colors.blue.withAlpha(36),
                    divisions: 100,
                    subdivisions: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
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
    canvas.drawImage(image, Offset.zero, Paint());
  }

  @override
  bool shouldRepaint(_GpuTextureDebugPainter oldDelegate) => texture != oldDelegate.texture;
}
