/// Shared responsive breakpoints for Bisho IDE's dashboard surfaces.
class BishoResponsiveLayout {
  const BishoResponsiveLayout._();

  /// Keeps phone layouts at two columns and progressively uses tablet width.
  static int dashboardColumns(double availableWidth) {
    if (!availableWidth.isFinite || availableWidth <= 0) return 2;
    if (availableWidth >= 900) return 4;
    if (availableWidth >= 560) return 3;
    return 2;
  }

  static double toolCardAspectRatio(double availableWidth) =>
      availableWidth >= 650 ? 1.9 : 1.65;
}
