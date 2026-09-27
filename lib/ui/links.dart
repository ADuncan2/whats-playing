import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';

/// Opens a web page (booking, TfL, cinema) in the browser or the relevant app.
Future<void> openUrl(BuildContext context, String? url) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = url != null && await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok) messenger.showSnackBar(const SnackBar(content: Text("Couldn't open that link")));
}

/// Opens a page in the browser itself (a Chrome Custom Tab on Android), never in another app.
/// For links such as Letterboxd's export page, which Android would otherwise hand to the Letterboxd
/// app through App Links; a Custom Tab is addressed to the browser, shares its cookies (so a signed-in
/// user stays signed in) and lets it handle downloads. If no Custom Tabs provider is there
/// (url_launcher would fall back to a bare WebView, which can't sign in or download), or opening
/// fails, the link is copied to the clipboard instead and a SnackBar says so.
Future<void> openInBrowser(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final uri = Uri.parse(url);
  var ok = false;
  try {
    if (isWeb) {
      ok = await launchUrl(uri); // already in the browser: a new tab
    } else if (await supportsLaunchMode(LaunchMode.inAppBrowserView)) {
      ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    }
  } catch (_) {
    ok = false;
  }
  if (ok) return;
  await Clipboard.setData(ClipboardData(text: url));
  messenger.showSnackBar(const SnackBar(content: Text('Link copied - paste it into your browser')));
}

/// Copies [text] and says so.
Future<void> copyToClipboard(BuildContext context, String text, {String message = 'Link copied'}) async {
  final messenger = ScaffoldMessenger.of(context);
  await Clipboard.setData(ClipboardData(text: text));
  messenger.showSnackBar(SnackBar(content: Text(message)));
}
