/// Window layout mode for the desktop application.
enum AppWindowMode {
  /// Standard full desktop window (`1280 x 800` default).
  desktop('Mode Desktop'),

  /// Compact phone-sized floating utility window (`412 x 780`).
  compact('Mode Kecil (HP)');

  const AppWindowMode(this.label);

  /// User-facing Indonesian label for this mode.
  final String label;

  /// Default width for [desktop] mode in logical pixels.
  static const double desktopWidth = 1280;

  /// Default height for [desktop] mode in logical pixels.
  static const double desktopHeight = 800;

  /// Width for [compact] (phone-sized) mode in logical pixels.
  static const double compactWidth = 412;

  /// Height for [compact] (phone-sized) mode in logical pixels.
  static const double compactHeight = 780;

  /// Minimum allowed window width in logical pixels.
  static const double minimumWidth = 380;

  /// Minimum allowed window height in logical pixels.
  static const double minimumHeight = 640;
}
