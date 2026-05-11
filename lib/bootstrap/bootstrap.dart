import 'bootstrap_stub.dart'
    if (dart.library.html) 'bootstrap_web.dart'
    if (dart.library.io) 'bootstrap_native.dart' as bootstrap;

Future<void> bootstrapApp() => bootstrap.bootstrapApp();
