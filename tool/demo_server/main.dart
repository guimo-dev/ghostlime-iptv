import 'dart:async';
import 'dart:io';

import 'demo_server.dart';

/// Starts the demo server: `dart run tool/demo_server/main.dart --port 8899`.
Future<void> main(List<String> args) async {
  final portIndex = args.indexOf('--port');
  final port = portIndex == -1 ? 8899 : int.parse(args[portIndex + 1]);
  final clipPath = Platform.script.resolve('assets/demo.ts').toFilePath();
  // Backstop: a client aborting mid-stream must never take the server down.
  await runZonedGuarded(() async {
    final server = await DemoServer.start(port: port, clipPath: clipPath);
    stdout.writeln('Demo server: ${server.baseUrl} (user demo, password demo)');
  }, (error, stack) => stderr.writeln('Demo server error: $error'));
}
