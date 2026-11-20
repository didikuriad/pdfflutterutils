/// Clockwise page rotation increments in quarter turns.
enum RotationQuarterTurns {
  /// No rotation applied (0°).
  deg0(0),

  /// Rotated 90° clockwise.
  deg90(90),

  /// Rotated 180°.
  deg180(180),

  /// Rotated 270° clockwise (equivalent to 90° counter-clockwise).
  deg270(270);

  const RotationQuarterTurns(this.degrees);

  /// Clockwise rotation angle in degrees (`0`, `90`, `180`, or `270`).
  final int degrees;

  /// Number of clockwise 90° quarter turns (`0`..`3`).
  int get quarterTurns => index;

  /// Returns the rotation rotated 90° clockwise from this rotation.
  RotationQuarterTurns rotateCW90() =>
      RotationQuarterTurns.values[(index + 1) % 4];

  /// Returns the rotation rotated 90° counter-clockwise from this rotation.
  RotationQuarterTurns rotateCCW90() =>
      RotationQuarterTurns.values[(index + 3) % 4];

  /// Returns the rotation rotated 180° from this rotation.
  RotationQuarterTurns rotate180() =>
      RotationQuarterTurns.values[(index + 2) % 4];

  /// Combines this rotation with [other].
  RotationQuarterTurns add(RotationQuarterTurns other) =>
      RotationQuarterTurns.values[(index + other.index) % 4];

  /// Whether a non-zero rotation is currently pending.
  bool get isRotated => this != RotationQuarterTurns.deg0;

  /// Human-readable short badge label for the rotation delta.
  String get label => switch (this) {
        RotationQuarterTurns.deg0 => '0°',
        RotationQuarterTurns.deg90 => '+90°',
        RotationQuarterTurns.deg180 => '+180°',
        RotationQuarterTurns.deg270 => '-90°',
      };
}
