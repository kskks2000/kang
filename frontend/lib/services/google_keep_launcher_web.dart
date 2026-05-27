import 'package:web/web.dart' as web;

const _googleKeepUrl = 'https://keep.google.com/';

Future<bool> openGoogleKeep() async {
  web.window.location.assign(_googleKeepUrl);
  return true;
}
