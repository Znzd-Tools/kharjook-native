// Native stand-in for the web "download a Blob" helpers: write to a temp file
// and open the system share sheet (save to Files, Drive, Telegram, ...).

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareTextFile(String filename, String content, {String mime = 'text/csv', bool bom = true}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(utf8.encode('${bom ? '﻿' : ''}$content'));
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: mime)], fileNameOverrides: [filename]));
}
