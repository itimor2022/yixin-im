import 'dart:io';

import 'package:qr/qr.dart';

void main(List<String> args) {
  if (args.isEmpty || args.first.trim().isEmpty) {
    stderr.writeln('Usage: dart run scripts/generate_qr_svg.dart <payload>');
    exitCode = 64;
    return;
  }

  final data = args.join(' ').trim();
  final qrCode = QrCode.fromData(
    data: data,
    errorCorrectLevel: QrErrorCorrectLevel.M,
  );
  final qrImage = QrImage(qrCode);
  const quietZone = 4;
  const moduleSize = 10;
  final moduleCount = qrImage.moduleCount;
  final size = (moduleCount + quietZone * 2) * moduleSize;

  final buffer = StringBuffer()
    ..write(
      '<svg xmlns="http://www.w3.org/2000/svg" '
      'width="$size" height="$size" viewBox="0 0 $size $size" '
      'shape-rendering="crispEdges">',
    )
    ..write('<rect width="100%" height="100%" fill="#fff"/>');

  for (var row = 0; row < moduleCount; row += 1) {
    for (var col = 0; col < moduleCount; col += 1) {
      if (!qrImage.isDark(row, col)) continue;
      final x = (col + quietZone) * moduleSize;
      final y = (row + quietZone) * moduleSize;
      buffer.write(
        '<rect x="$x" y="$y" width="$moduleSize" '
        'height="$moduleSize" fill="#000"/>',
      );
    }
  }

  buffer.write('</svg>');
  stdout.write(buffer.toString());
}
