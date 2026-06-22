// Conditional import — selects web implementation on browser, stub elsewhere.
export 'web_notification_stub.dart'
    if (dart.library.html) 'web_notification_web.dart';
