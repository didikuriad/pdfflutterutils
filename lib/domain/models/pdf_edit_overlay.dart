import 'dart:math' as math;
import 'dart:typed_data';

/// Extracts the 8-bit alpha channel (`0..255`) from a 32-bit ARGB color integer.
int argbAlpha(int argb) => (argb >> 24) & 0xFF;

/// Extracts the 8-bit red channel (`0..255`) from a 32-bit ARGB color integer.
int argbRed(int argb) => (argb >> 16) & 0xFF;

/// Extracts the 8-bit green channel (`0..255`) from a 32-bit ARGB color integer.
int argbGreen(int argb) => (argb >> 8) & 0xFF;

/// Extracts the 8-bit blue channel (`0..255`) from a 32-bit ARGB color integer.
int argbBlue(int argb) => argb & 0xFF;

/// Returns [argb] with its alpha channel replaced by [alpha] (`0..255`).
int withArgbAlpha(int argb, int alpha) =>
    ((alpha & 0xFF) << 24) | (argb & 0x00FFFFFF);

/// Active editing tool inside the PDF Editor workspace.
enum PdfEditTool {
  /// Select, move, resize, restyle, or remove existing overlays.
  select('Pilih'),

  /// Tap on the page to place editable text (with optional whiteout backing).
  text('Teks'),

  /// Drag an opaque rectangle to cover unwanted content.
  whiteout('Whiteout'),

  /// Drag a translucent color band over existing content.
  highlight('Highlight'),

  /// Freehand vector pen strokes.
  pen('Pena'),

  /// Drag an outlined rectangular box.
  rectangle('Kotak');

  const PdfEditTool(this.label);

  /// User-facing Indonesian tool name.
  final String label;
}

/// Visual style of a rectangular PDF overlay.
enum PdfRectOverlayKind {
  /// Opaque fill used to cover existing text or graphics.
  whiteout,

  /// Semi-transparent highlighter fill.
  highlight,

  /// Unfilled stroked border rectangle.
  outline,
}

/// Logical dimensions of a PDF page in PDF points (1/72 inch, visually oriented).
class PdfPageSize {
  /// Creates an immutable [PdfPageSize].
  const PdfPageSize({
    required this.width,
    required this.height,
  });

  /// Fallback portrait A4 dimensions (`595 x 842` points).
  static const PdfPageSize a4 = PdfPageSize(width: 595, height: 842);

  /// Page width in PDF points.
  final double width;

  /// Page height in PDF points.
  final double height;

  /// Aspect ratio `width / height`, guarded against non-positive heights.
  double get aspectRatio => height > 0 ? width / height : 1.0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PdfPageSize &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(width, height);
}

/// Normalized coordinate on a visually oriented PDF page (`0.0..1.0`, top-left origin).
class NormalizedPoint {
  /// Creates an immutable [NormalizedPoint] clamped to `[0.0, 1.0]`.
  NormalizedPoint(double x, double y)
      : x = x.clamp(0.0, 1.0),
        y = y.clamp(0.0, 1.0);

  /// Creates an unclamped constant [NormalizedPoint] when coordinates are known valid.
  const NormalizedPoint.raw(this.x, this.y);

  /// Horizontal fraction from left (`0.0`) to right (`1.0`).
  final double x;

  /// Vertical fraction from top (`0.0`) to bottom (`1.0`).
  final double y;

  /// Returns this point shifted by `(dx, dy)` and clamped inside `[0.0, 1.0]`.
  NormalizedPoint translated(double dx, double dy) =>
      NormalizedPoint(x + dx, y + dy);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NormalizedPoint && other.x == x && other.y == y;
  }

  @override
  int get hashCode => Object.hash(x, y);
}

/// Normalized rectangle on a visually oriented PDF page (`0.0..1.0`, top-left origin).
class NormalizedRect {
  /// Creates a [NormalizedRect] clamped inside `[0.0, 1.0]`.
  factory NormalizedRect({
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    final safeLeft = left.clamp(0.0, 1.0);
    final safeTop = top.clamp(0.0, 1.0);
    final safeWidth = width.clamp(0.0, 1.0 - safeLeft);
    final safeHeight = height.clamp(0.0, 1.0 - safeTop);
    return NormalizedRect._(
      left: safeLeft,
      top: safeTop,
      width: safeWidth,
      height: safeHeight,
    );
  }

  const NormalizedRect._({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// Builds the smallest axis-aligned rectangle enclosing [a] and [b].
  factory NormalizedRect.fromPoints(NormalizedPoint a, NormalizedPoint b) {
    final left = math.min(a.x, b.x);
    final top = math.min(a.y, b.y);
    final right = math.max(a.x, b.x);
    final bottom = math.max(a.y, b.y);
    return NormalizedRect(
      left: left,
      top: top,
      width: right - left,
      height: bottom - top,
    );
  }

  /// Normalized left edge (`0.0..1.0`).
  final double left;

  /// Normalized top edge (`0.0..1.0`).
  final double top;

  /// Normalized width (`0.0..1.0`).
  final double width;

  /// Normalized height (`0.0..1.0`).
  final double height;

  /// Normalized right edge.
  double get right => left + width;

  /// Normalized bottom edge.
  double get bottom => top + height;

  /// Returns `true` when [point] falls inside or on the boundary of this rect.
  bool contains(NormalizedPoint point) {
    return point.x >= left &&
        point.x <= right &&
        point.y >= top &&
        point.y <= bottom;
  }

  /// Moves this rectangle by `(dx, dy)` while keeping it entirely within the page.
  NormalizedRect translated(double dx, double dy) {
    final maxLeft = math.max(0.0, 1.0 - width);
    final maxTop = math.max(0.0, 1.0 - height);
    return NormalizedRect._(
      left: (left + dx).clamp(0.0, maxLeft),
      top: (top + dy).clamp(0.0, maxTop),
      width: width,
      height: height,
    );
  }

  /// Resizes this rectangle to `(newWidth, newHeight)` anchored at top-left,
  /// clamped to a minimum side length of `0.02` and the page boundary.
  NormalizedRect resized(double newWidth, double newHeight) {
    final maxWidth = math.max(0.0, 1.0 - left);
    final maxHeight = math.max(0.0, 1.0 - top);
    final minWidth = math.min(0.02, maxWidth);
    final minHeight = math.min(0.02, maxHeight);
    return NormalizedRect._(
      left: left,
      top: top,
      width: newWidth.clamp(minWidth, maxWidth),
      height: newHeight.clamp(minHeight, maxHeight),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NormalizedRect &&
        other.left == left &&
        other.top == top &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(left, top, width, height);
}

/// Base class for all non-destructive PDF edit overlays placed on a page.
sealed class PdfEditOverlay {
  /// Creates a [PdfEditOverlay].
  const PdfEditOverlay({
    required this.id,
    required this.pageNumber,
  });

  /// Unique identifier within the editing session.
  final String id;

  /// 1-based page number to which this overlay belongs.
  final int pageNumber;

  /// Returns a copy shifted by normalized `(dx, dy)` on the same page.
  PdfEditOverlay translated(double dx, double dy);
}

/// Placed text annotation overlay (optionally backed by an opaque background).
final class PdfTextOverlay extends PdfEditOverlay {
  /// Creates a [PdfTextOverlay].
  const PdfTextOverlay({
    required super.id,
    required super.pageNumber,
    required this.x,
    required this.y,
    required this.text,
    required this.fontSizePt,
    required this.colorArgb,
    this.backgroundColorArgb,
    this.isBold = false,
  });

  /// Normalized left origin (`0.0..1.0`).
  final double x;

  /// Normalized top origin (`0.0..1.0`).
  final double y;

  /// Plain text content (supports `\n` line breaks).
  final String text;

  /// Font size in PDF points.
  final double fontSizePt;

  /// 32-bit ARGB text color.
  final int colorArgb;

  /// Optional 32-bit ARGB background color behind text (e.g. `0xFFFFFFFF` whiteout).
  final int? backgroundColorArgb;

  /// Whether bold styling is applied.
  final bool isBold;

  /// Returns a modified copy of this overlay.
  PdfTextOverlay copyWith({
    double? x,
    double? y,
    String? text,
    double? fontSizePt,
    int? colorArgb,
    int? backgroundColorArgb,
    bool clearBackground = false,
    bool? isBold,
  }) {
    return PdfTextOverlay(
      id: id,
      pageNumber: pageNumber,
      x: (x ?? this.x).clamp(0.0, 0.98),
      y: (y ?? this.y).clamp(0.0, 0.98),
      text: text ?? this.text,
      fontSizePt: (fontSizePt ?? this.fontSizePt).clamp(6.0, 72.0),
      colorArgb: colorArgb ?? this.colorArgb,
      backgroundColorArgb: clearBackground
          ? null
          : (backgroundColorArgb ?? this.backgroundColorArgb),
      isBold: isBold ?? this.isBold,
    );
  }

  @override
  PdfTextOverlay translated(double dx, double dy) {
    return copyWith(x: x + dx, y: y + dy);
  }
}

/// Rectangular overlay for whiteout boxes, highlights, or bordered boxes.
final class PdfRectOverlay extends PdfEditOverlay {
  /// Creates a [PdfRectOverlay].
  const PdfRectOverlay({
    required super.id,
    required super.pageNumber,
    required this.rect,
    required this.kind,
    required this.colorArgb,
    this.strokeWidthPt = 2.0,
  });

  /// Normalized bounds on the page.
  final NormalizedRect rect;

  /// Visual rendering style.
  final PdfRectOverlayKind kind;

  /// 32-bit ARGB color used for fill or stroke.
  final int colorArgb;

  /// Border width in PDF points (used when [kind] is [PdfRectOverlayKind.outline]).
  final double strokeWidthPt;

  /// Returns a modified copy of this overlay.
  PdfRectOverlay copyWith({
    NormalizedRect? rect,
    PdfRectOverlayKind? kind,
    int? colorArgb,
    double? strokeWidthPt,
  }) {
    return PdfRectOverlay(
      id: id,
      pageNumber: pageNumber,
      rect: rect ?? this.rect,
      kind: kind ?? this.kind,
      colorArgb: colorArgb ?? this.colorArgb,
      strokeWidthPt: (strokeWidthPt ?? this.strokeWidthPt).clamp(0.5, 16.0),
    );
  }

  @override
  PdfRectOverlay translated(double dx, double dy) {
    return copyWith(rect: rect.translated(dx, dy));
  }
}

/// Vector polyline overlay used for freehand pen drawings and signatures.
final class PdfStrokeOverlay extends PdfEditOverlay {
  /// Creates a [PdfStrokeOverlay].
  PdfStrokeOverlay({
    required super.id,
    required super.pageNumber,
    required List<List<NormalizedPoint>> strokes,
    required this.colorArgb,
    this.strokeWidthPt = 2.5,
    this.isSignature = false,
  }) : strokes = List<List<NormalizedPoint>>.unmodifiable(
          strokes
              .where((s) => s.isNotEmpty)
              .map(List<NormalizedPoint>.unmodifiable),
        );

  /// Ordered polylines in normalized page coordinates.
  final List<List<NormalizedPoint>> strokes;

  /// 32-bit ARGB stroke color.
  final int colorArgb;

  /// Stroke width in PDF points.
  final double strokeWidthPt;

  /// Whether this stroke group originated from the signature pad.
  final bool isSignature;

  /// Tight normalized bounding rectangle enclosing all stroke vertices.
  NormalizedRect get bounds {
    var minX = 1.0;
    var minY = 1.0;
    var maxX = 0.0;
    var maxY = 0.0;
    var hasPoints = false;

    for (final polyline in strokes) {
      for (final pt in polyline) {
        hasPoints = true;
        if (pt.x < minX) minX = pt.x;
        if (pt.y < minY) minY = pt.y;
        if (pt.x > maxX) maxX = pt.x;
        if (pt.y > maxY) maxY = pt.y;
      }
    }

    if (!hasPoints) {
      return NormalizedRect(left: 0, top: 0, width: 0, height: 0);
    }
    return NormalizedRect(
      left: minX,
      top: minY,
      width: math.max(0.01, maxX - minX),
      height: math.max(0.01, maxY - minY),
    );
  }

  /// Returns a modified copy of this overlay.
  PdfStrokeOverlay copyWith({
    List<List<NormalizedPoint>>? strokes,
    int? colorArgb,
    double? strokeWidthPt,
    bool? isSignature,
  }) {
    return PdfStrokeOverlay(
      id: id,
      pageNumber: pageNumber,
      strokes: strokes ?? this.strokes,
      colorArgb: colorArgb ?? this.colorArgb,
      strokeWidthPt: (strokeWidthPt ?? this.strokeWidthPt).clamp(0.5, 16.0),
      isSignature: isSignature ?? this.isSignature,
    );
  }

  @override
  PdfStrokeOverlay translated(double dx, double dy) {
    final b = bounds;
    final clampedDx = dx.clamp(-b.left, math.max(0.0, 1.0 - b.right)).toDouble();
    final clampedDy = dy.clamp(-b.top, math.max(0.0, 1.0 - b.bottom)).toDouble();
    final shifted = <List<NormalizedPoint>>[
      for (final polyline in strokes)
        <NormalizedPoint>[
          for (final pt in polyline) pt.translated(clampedDx, clampedDy),
        ],
    ];
    return copyWith(strokes: shifted);
  }

  /// Scales all stroke vertices proportionally to fit inside [targetBounds].
  PdfStrokeOverlay resizedTo(NormalizedRect targetBounds) {
    final b = bounds;
    final scaled = <List<NormalizedPoint>>[
      for (final polyline in strokes)
        <NormalizedPoint>[
          for (final pt in polyline)
            NormalizedPoint(
              b.width > 0.0001
                  ? targetBounds.left +
                      ((pt.x - b.left) / b.width) * targetBounds.width
                  : targetBounds.left + targetBounds.width * 0.5,
              b.height > 0.0001
                  ? targetBounds.top +
                      ((pt.y - b.top) / b.height) * targetBounds.height
                  : targetBounds.top + targetBounds.height * 0.5,
            ),
        ],
    ];
    return copyWith(strokes: scaled);
  }
}

/// Embedded raster image overlay (e.g., stamp, logo, or PNG signature).
final class PdfImageOverlay extends PdfEditOverlay {
  /// Creates a [PdfImageOverlay].
  const PdfImageOverlay({
    required super.id,
    required super.pageNumber,
    required this.rect,
    required this.imageBytes,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.fileName,
    this.preDecodedBgraBytes,
  });

  /// Normalized target box on the page.
  final NormalizedRect rect;

  /// Original encoded image bytes (PNG/JPEG/etc.) used for UI preview and fallback decode.
  final Uint8List imageBytes;

  /// Decoded pixel width of [imageBytes].
  final int pixelWidth;

  /// Decoded pixel height of [imageBytes].
  final int pixelHeight;

  /// Base file name of the inserted image.
  final String fileName;

  /// Optional straight-BGRA pixel buffer matching [pixelWidth] x [pixelHeight].
  final Uint8List? preDecodedBgraBytes;

  /// Returns a modified copy of this overlay.
  PdfImageOverlay copyWith({
    NormalizedRect? rect,
    Uint8List? imageBytes,
    int? pixelWidth,
    int? pixelHeight,
    String? fileName,
    Uint8List? preDecodedBgraBytes,
  }) {
    return PdfImageOverlay(
      id: id,
      pageNumber: pageNumber,
      rect: rect ?? this.rect,
      imageBytes: imageBytes ?? this.imageBytes,
      pixelWidth: pixelWidth ?? this.pixelWidth,
      pixelHeight: pixelHeight ?? this.pixelHeight,
      fileName: fileName ?? this.fileName,
      preDecodedBgraBytes: preDecodedBgraBytes ?? this.preDecodedBgraBytes,
    );
  }

  @override
  PdfImageOverlay translated(double dx, double dy) {
    return copyWith(rect: rect.translated(dx, dy));
  }
}
