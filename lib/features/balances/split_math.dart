/// Deterministic even split in integer cents. Earlier participants get one
/// leftover cent each. Zero cents is valid; negative amounts and N <= 0 are not.
List<int> splitAmount(int cents, int people) {
  if (cents < 0 || people <= 0) {
    throw ArgumentError('Use non-negative cents and at least one person.');
  }
  final base = cents ~/ people;
  final remainder = cents % people;
  return List.generate(
    people,
    (i) => base + (i < remainder ? 1 : 0),
    growable: false,
  );
}
