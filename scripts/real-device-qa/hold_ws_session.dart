import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart hold_ws_session.dart <ws-url>');
    exitCode = 2;
    return;
  }

  final socket = await WebSocket.connect(args.single);
  socket.pingInterval = const Duration(seconds: 10);
  stdout.writeln('CONNECTED');

  final input = stdin.transform(utf8.decoder).transform(const LineSplitter());
  await for (final line in input) {
    if (line.trim().toUpperCase() == 'STOP') break;
  }
  await socket.close(WebSocketStatus.normalClosure, 'qa complete');
}
