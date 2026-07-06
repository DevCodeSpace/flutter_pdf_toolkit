import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Holds the strokes drawn on a [SignaturePad] and notifies listeners as the
/// user draws, so the host UI can enable/disable "Clear"/"Done" actions.
class SignaturePadController extends ChangeNotifier {
  final List<List<Offset>> _strokes = <List<Offset>>[];
  List<Offset> _currentStroke = const <Offset>[];

  /// Whether anything has been drawn yet.
  bool get isEmpty => _strokes.isEmpty;

  /// All completed and in-progress strokes, as lists of points.
  List<List<Offset>> get strokes => _strokes;

  void startStroke(Offset point) {
    _currentStroke = <Offset>[point];
    _strokes.add(_currentStroke);
    notifyListeners();
  }

  void addPoint(Offset point) {
    _currentStroke.add(point);
    notifyListeners();
  }

  void endStroke() {
    _currentStroke = const <Offset>[];
  }

  /// Clears all drawn strokes.
  void clear() {
    _strokes.clear();
    _currentStroke = const <Offset>[];
    notifyListeners();
  }
}

/// A simple finger/stylus signature pad. Drawn strokes are tracked by
/// [controller]; call [SignaturePadState.toPngBytes] (via a [GlobalKey]) to
/// export the drawing as a transparent PNG suitable for stamping onto a PDF
/// page.
class SignaturePad extends StatefulWidget {
  const SignaturePad({
    super.key,
    required this.controller,
    this.penColor = const Color(0xFF000000),
    this.penWidth = 3.0,
  });

  final SignaturePadController controller;
  final Color penColor;
  final double penWidth;

  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  final GlobalKey _boundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Renders the current strokes to a transparent PNG image.
  ///
  /// Returns `null` if nothing has been drawn yet or the pad has not been
  /// laid out.
  Future<Uint8List?> toPngBytes({double pixelRatio = 3.0}) async {
    if (widget.controller.isEmpty) {
      return null;
    }
    final RenderRepaintBoundary? boundary =
        _boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      return null;
    }
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    image.dispose();
    return byteData?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _boundaryKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (DragStartDetails details) {
          final Offset p = _clampToBounds(details.localPosition);
          widget.controller.startStroke(p);
        },
        onPanUpdate: (DragUpdateDetails details) {
          final Offset p = _clampToBounds(details.localPosition);
          widget.controller.addPoint(p);
        },
        onPanEnd: (DragEndDetails details) => widget.controller.endStroke(),
        child: CustomPaint(
          painter: _SignaturePainter(
            strokes: widget.controller.strokes,
            color: widget.penColor,
            strokeWidth: widget.penWidth,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  Offset _clampToBounds(Offset point) {
    final Size? s = context.size;
    if (s == null) return point;
    final double x = point.dx.clamp(0.0, s.width);
    final double y = point.dy.clamp(0.0, s.height);
    return Offset(x, y);
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter({
    required this.strokes,
    required this.color,
    required this.strokeWidth,
  });

  final List<List<Offset>> strokes;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    // Ensure drawing is clipped to the pad's bounds so strokes outside
    // the widget (when the pointer moves off the pad) aren't rendered.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final List<Offset> stroke in strokes) {
      if (stroke.isEmpty) {
        continue;
      }
      if (stroke.length == 1) {
        canvas.drawCircle(
          stroke.first,
          strokeWidth / 2,
          paint..style = PaintingStyle.fill,
        );
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final Path path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
