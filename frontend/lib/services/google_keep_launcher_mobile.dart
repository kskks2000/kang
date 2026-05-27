import 'package:flutter/services.dart';

const _channel = MethodChannel('kr.ai.kang.kang/google_keep');

Future<bool> openGoogleKeep() async {
  try {
    return await _channel.invokeMethod<bool>('open') ?? false;
  } on PlatformException {
    return false;
  }
}
