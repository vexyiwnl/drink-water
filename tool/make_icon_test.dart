// Renders the app icon PNGs into assets/icon/. Run after changing the design:
//   flutter test tool/make_icon_test.dart && dart run flutter_launcher_icons
import 'dart:io';
import 'dart:ui';

import 'package:drinkwater/theme.dart';
import 'package:flutter_test/flutter_test.dart';

const size = 1024.0;

/// Water drop in a 24×24 box (same shape as the Android notification icon).
Path drop() => Path()
  ..moveTo(12, 2.5)
  ..cubicTo(12, 2.5, 5, 10.2, 5, 15)
  ..arcToPoint(const Offset(19, 15), radius: const Radius.circular(7), clockwise: false)
  ..cubicTo(19, 10.2, 12, 2.5, 12, 2.5)
  ..close();

/// Drop scaled so its 24-unit box spans [box] px, centred.
void paintDrop(Canvas c, double box, {bool mono = false}) {
  c.save();
  c.translate((size - box) / 2, (size - box) / 2);
  c.scale(box / 24);
  final shape = drop();
  c.drawPath(
    shape,
    Paint()
      ..color = const Color(0xFFFFFFFF)
      ..shader = mono ? null : Gradient.linear(const Offset(12, 2), const Offset(12, 22), [aqua, aquaDeep]),
  );
  if (!mono) {
    // Soft highlight on the upper left of the drop.
    c.drawPath(
      Path()
        ..moveTo(8.2, 13.2)
        ..quadraticBezierTo(8.4, 10.6, 10.6, 7.6),
      Paint()
        ..color = const Color(0x8CFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round,
    );
  }
  c.restore();
}

Future<void> save(String name, void Function(Canvas) paint) async {
  final rec = PictureRecorder();
  paint(Canvas(rec));
  final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
  final png = await img.toByteData(format: ImageByteFormat.png);
  File('assets/icon/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  test('render icons', () async {
    await TestWidgetsFlutterBinding.ensureInitialized().runAsync(() async {
      // Full icon (Windows, legacy Android): navy rounded square + drop.
      await save('icon', (c) {
        final r = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, size, size), const Radius.circular(220));
        c.drawRRect(
          r,
          Paint()..shader = Gradient.linear(Offset.zero, const Offset(0, size), [const Color(0xFF12315A), navy]),
        );
        paintDrop(c, 760);
      });
      // Android adaptive foreground: drop inside the 66% safe zone, transparent around.
      await save('foreground', (c) => paintDrop(c, 560));
      // Android 13+ themed (monochrome) icon.
      await save('monochrome', (c) => paintDrop(c, 560, mono: true));
    });
  });
}
