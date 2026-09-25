import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nocterm/nocterm.dart';
// Nocterm does not currently export TerminalCanvas, which a custom render
// object needs in order to preserve image placeholder cells between frames.
// ignore: implementation_imports
import 'package:nocterm/src/framework/terminal_canvas.dart';

class ITermPngAsset {
  const ITermPngAsset._(this.bytes, this.pixelWidth, this.pixelHeight);

  final Uint8List bytes;
  final int pixelWidth;
  final int pixelHeight;

  static ITermPngAsset? load(File file) {
    try {
      final bytes = file.readAsBytesSync();
      if (bytes.length < 24 ||
          bytes[0] != 0x89 ||
          bytes[1] != 0x50 ||
          bytes[2] != 0x4e ||
          bytes[3] != 0x47) {
        return null;
      }
      final header = ByteData.sublistView(bytes);
      final width = header.getUint32(16);
      final height = header.getUint32(20);
      if (width == 0 || height == 0) return null;
      return ITermPngAsset._(bytes, width, height);
    } on FileSystemException {
      return null;
    }
  }
}

/// Draws a local PNG through iTerm's inline image protocol once, then keeps
/// image placeholder cells in later Nocterm frames without resending the PNG.
class ITermPngImage extends SingleChildRenderObjectComponent {
  const ITermPngImage({
    required this.asset,
    required this.height,
    super.key,
  });

  final ITermPngAsset asset;
  final int height;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderITermPngImage(
        asset: asset,
        requestedHeight: height,
      );

  @override
  void updateRenderObject(
      BuildContext context, _RenderITermPngImage renderObject) {
    renderObject
      ..asset = asset
      ..requestedHeight = height;
  }
}

class _RenderITermPngImage extends RenderObject {
  _RenderITermPngImage({
    required ITermPngAsset asset,
    required int requestedHeight,
  })  : _asset = asset,
        _requestedHeight = requestedHeight;

  ITermPngAsset _asset;
  set asset(ITermPngAsset value) {
    if (identical(_asset, value)) return;
    _asset = value;
    _lastPlacement = null;
    _encoded = null;
    markNeedsLayout();
  }

  int _requestedHeight;
  set requestedHeight(int value) {
    if (_requestedHeight == value) return;
    _requestedHeight = value;
    _lastPlacement = null;
    _encoded = null;
    markNeedsLayout();
  }

  int? _lastPlacement;
  String? _encoded;
  int? _encodedWidth;
  int? _encodedHeight;

  @override
  void performLayout() {
    // Terminal cells are approximately twice as tall as they are wide.
    final cellAspect = (_asset.pixelWidth * 2) / _asset.pixelHeight;
    var targetHeight = _requestedHeight.toDouble();
    var targetWidth = targetHeight * cellAspect;

    if (constraints.maxWidth.isFinite && targetWidth > constraints.maxWidth) {
      targetWidth = constraints.maxWidth;
      targetHeight = targetWidth / cellAspect;
    }
    if (constraints.maxHeight.isFinite &&
        targetHeight > constraints.maxHeight) {
      targetHeight = constraints.maxHeight;
      targetWidth = targetHeight * cellAspect;
    }
    size = constraints.constrain(Size(targetWidth, targetHeight));
  }

  @override
  void paint(TerminalCanvas canvas, Offset offset) {
    super.paint(canvas, offset);
    final width = size.width.floor();
    final height = size.height.floor();
    if (width <= 0 || height <= 0) return;

    final x = offset.dx.round();
    final y = offset.dy.round();
    final placement =
        Object.hash(x, y, width, height, identityHashCode(_asset));
    var payload = '';
    if (_lastPlacement != placement) {
      if (_encoded == null ||
          _encodedWidth != width ||
          _encodedHeight != height) {
        _encoded = _encode(width, height);
        _encodedWidth = width;
        _encodedHeight = height;
      }
      payload = _encoded!;
      _lastPlacement = placement;
    }

    // An empty payload on later frames still marks the cells as image cells,
    // so Nocterm's differential renderer does not overwrite the existing PNG.
    canvas.drawImage(_asset.bytes, payload, x, y, width, height);
  }

  String _encode(int width, int height) {
    final data = base64Encode(_asset.bytes);
    return '\x1b]1337;File=inline=1;size=${_asset.bytes.length};'
        'width=$width;height=$height:$data\x07';
  }
}
