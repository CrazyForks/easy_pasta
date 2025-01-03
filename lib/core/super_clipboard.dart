import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:easy_pasta/model/pasteboard_model.dart';
import 'package:easy_pasta/model/clipboard_type.dart';
import 'package:easy_pasta/core/html_processor.dart';

/// A singleton class that manages system clipboard operations and monitoring
class SuperClipboard {
  // Singleton implementation
  static final SuperClipboard _instance = SuperClipboard._internal();
  static SuperClipboard get instance => _instance;

  final SystemClipboard? _clipboard = SystemClipboard.instance;
  ValueChanged<ClipboardItemModel?>? _onClipboardChanged;
  ClipboardItemModel? _lastContent;
  Timer? _pollingTimer;

  static const Duration _pollingInterval = Duration(seconds: 1);

  // Private constructor
  SuperClipboard._internal() {
    _startPollingTimer();
  }

  /// Starts monitoring clipboard changes
  void _startPollingTimer() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(_pollingInterval, (_) => _pollClipboard());
  }

  /// Polls clipboard content for changes
  Future<void> _pollClipboard() async {
    try {
      final reader = await _clipboard?.read();
      if (reader == null) return;

      await _processClipboardContent(reader);
    } catch (e) {
      debugPrint('Clipboard polling error: $e');
    }
  }

  /// Processes different types of clipboard content
  Future<void> _processClipboardContent(ClipboardReader reader) async {
    if (await _processHtmlContent(reader)) return;
    if (await _processFileContent(reader)) return;
    if (await _processTextContent(reader)) return;
    if (await _processImageContent(reader)) return;
  }

  /// Processes HTML content from clipboard
  Future<bool> _processHtmlContent(ClipboardReader reader) async {
    if (!reader.canProvide(Formats.htmlText)) return false;

    final html = await reader.readValue(Formats.htmlText);
    final htmlPlainText = await reader.readValue(Formats.plainText);

    if (html != null) {
      final processedHtml = HtmlProcessor.processHtml(html.toString());
      _handleContentChange(htmlPlainText.toString(), ClipboardType.html,
          bytes: Uint8List.fromList(utf8.encode(processedHtml)));
      return true;
    }
    return false;
  }

  /// Processes file URI content from clipboard
  Future<bool> _processFileContent(ClipboardReader reader) async {
    if (!reader.canProvide(Formats.fileUri)) return false;

    final fileUri = await reader.readValue(Formats.fileUri);
    final fileUriString = await reader.readValue(Formats.plainText);

    if (fileUri != null) {
      _handleContentChange(fileUriString.toString(), ClipboardType.file,
          bytes: Uint8List.fromList(utf8.encode(fileUri.toString())));
      return true;
    }
    return false;
  }

  /// Processes plain text content from clipboard
  Future<bool> _processTextContent(ClipboardReader reader) async {
    if (!reader.canProvide(Formats.plainText)) return false;

    final text = await reader.readValue(Formats.plainText);
    if (text != null) {
      _handleContentChange(text.toString(), ClipboardType.text);
      return true;
    }
    return false;
  }

  /// Processes image content from clipboard
  Future<bool> _processImageContent(ClipboardReader reader) async {
    if (!reader.canProvide(Formats.png)) return false;

    try {
      final completer = Completer<bool>();

      reader.getFile(Formats.png, (file) async {
        try {
          final stream = file.getStream();
          final bytes = await stream.toList();
          final imageData = bytes.expand((x) => x).toList();
          _handleContentChange('', ClipboardType.image,
              bytes: Uint8List.fromList(imageData));
          completer.complete(true);
        } catch (e) {
          debugPrint('Error processing image: $e');
          completer.complete(false);
        }
      });

      return await completer.future;
    } catch (e) {
      debugPrint('Error accessing image file: $e');
      return false;
    }
  }

  /// Handles content changes and notifies listeners
  void _handleContentChange(String content, ClipboardType? type,
      {Uint8List? bytes}) {
    final contentModel = _createContentModel(content, type, bytes);

    if (contentModel != _lastContent) {
      _lastContent = contentModel;
      _onClipboardChanged?.call(contentModel);
    }
  }

  /// Creates a content model based on the clipboard type
  ClipboardItemModel _createContentModel(
      String content, ClipboardType? type, Uint8List? bytes) {
    return ClipboardItemModel(
      ptype: type,
      pvalue: content,
      bytes: type == ClipboardType.text ? null : bytes,
    );
  }

  /// Sets clipboard change listener
  void setClipboardListener(ValueChanged<ClipboardItemModel?> listener) {
    _onClipboardChanged = listener;
  }

  /// Writes content to clipboard
  Future<void> setPasteboardItem(ClipboardItemModel model) => setContent(model);

  /// Writes content to clipboard with proper format
  Future<void> setContent(ClipboardItemModel model) async {
    final item = DataWriterItem();

    switch (model.ptype) {
      case ClipboardType.html:
        item.add(Formats.plainText(model.pvalue));
        item.add(
            Formats.htmlText(model.bytesToString(model.bytes ?? Uint8List(0))));
        break;
      case ClipboardType.file:
        item.add(Formats.plainText(model.pvalue));
        item.add(Formats.fileUri(
            Uri.parse(model.bytesToString(model.bytes ?? Uint8List(0)))));
        break;
      case ClipboardType.text:
        item.add(Formats.plainText(model.pvalue));
        break;
      case ClipboardType.image:
        item.add(
            Formats.png(Uint8List.fromList(model.imageBytes ?? Uint8List(0))));
        break;
      default:
        throw ArgumentError('Unsupported clipboard type: ${model.ptype}');
    }

    try {
      await _clipboard?.write([item]);
    } catch (e) {
      debugPrint('Failed to write to clipboard: $e');
      rethrow;
    }
  }

  /// Cleans up resources
  void dispose() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _onClipboardChanged = null;
    _lastContent = null;
  }
}
