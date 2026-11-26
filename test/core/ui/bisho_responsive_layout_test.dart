import 'package:flutter_test/flutter_test.dart';
import 'package:bisho_ide/core/ui/bisho_responsive_layout.dart';

void main() {
  group('BishoResponsiveLayout', () {
    test('uses two columns on narrow phone widths', () {
      expect(BishoResponsiveLayout.dashboardColumns(320), 2);
      expect(BishoResponsiveLayout.dashboardColumns(559), 2);
    });

    test('uses three columns on medium tablet widths', () {
      expect(BishoResponsiveLayout.dashboardColumns(560), 3);
      expect(BishoResponsiveLayout.dashboardColumns(899), 3);
    });

    test('uses four columns on wide layouts', () {
      expect(BishoResponsiveLayout.dashboardColumns(900), 4);
      expect(BishoResponsiveLayout.dashboardColumns(1200), 4);
    });

    test('falls back safely for invalid widths', () {
      expect(BishoResponsiveLayout.dashboardColumns(0), 2);
      expect(BishoResponsiveLayout.dashboardColumns(double.nan), 2);
      expect(BishoResponsiveLayout.dashboardColumns(double.infinity), 2);
    });

    test('uses wider cards on tablet layouts', () {
      expect(BishoResponsiveLayout.toolCardAspectRatio(400), 1.65);
      expect(BishoResponsiveLayout.toolCardAspectRatio(650), 1.9);
    });
  });
}
