import 'package:flutter_test/flutter_test.dart';
import 'package:pdfutils/domain/models/pdf_rotation.dart';

void main() {
  group('RotationQuarterTurns', () {
    test('rotateCW90 cycles through 0 -> 90 -> 180 -> 270 -> 0', () {
      expect(RotationQuarterTurns.deg0.rotateCW90(), RotationQuarterTurns.deg90);
      expect(
        RotationQuarterTurns.deg90.rotateCW90(),
        RotationQuarterTurns.deg180,
      );
      expect(
        RotationQuarterTurns.deg180.rotateCW90(),
        RotationQuarterTurns.deg270,
      );
      expect(
        RotationQuarterTurns.deg270.rotateCW90(),
        RotationQuarterTurns.deg0,
      );
    });

    test('rotateCCW90 cycles backwards', () {
      expect(
        RotationQuarterTurns.deg0.rotateCCW90(),
        RotationQuarterTurns.deg270,
      );
      expect(
        RotationQuarterTurns.deg270.rotateCCW90(),
        RotationQuarterTurns.deg180,
      );
      expect(
        RotationQuarterTurns.deg180.rotateCCW90(),
        RotationQuarterTurns.deg90,
      );
      expect(
        RotationQuarterTurns.deg90.rotateCCW90(),
        RotationQuarterTurns.deg0,
      );
    });

    test('rotate180 and add combine rotations modulo 360', () {
      expect(
        RotationQuarterTurns.deg90.rotate180(),
        RotationQuarterTurns.deg270,
      );
      expect(
        RotationQuarterTurns.deg180.add(RotationQuarterTurns.deg270),
        RotationQuarterTurns.deg90,
      );
    });

    test('isRotated, quarterTurns, and labels match expected values', () {
      expect(RotationQuarterTurns.deg0.isRotated, isFalse);
      expect(RotationQuarterTurns.deg90.isRotated, isTrue);
      expect(RotationQuarterTurns.deg270.quarterTurns, 3);
      expect(RotationQuarterTurns.deg0.label, '0°');
      expect(RotationQuarterTurns.deg90.label, '+90°');
      expect(RotationQuarterTurns.deg180.label, '+180°');
      expect(RotationQuarterTurns.deg270.label, '-90°');
    });
  });
}
