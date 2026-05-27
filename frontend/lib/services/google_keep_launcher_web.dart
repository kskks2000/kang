import 'package:web/web.dart' as web;

const _googleKeepUrl = 'https://keep.google.com/';

void openGoogleKeep() {
  web.window.location.assign(_googleKeepUrl);
}
