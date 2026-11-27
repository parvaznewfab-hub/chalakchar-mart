// Dropdowns fed by stored values (settings/app) must never crash the page:
// Flutter asserts (debug: red error screen; release: grey/blank page) when
// the value is not exactly once among the items. These pure helpers decide
// what to show and what may be saved; widgets/safe_dropdown_field.dart uses
// them.

class DropdownChoice {
  final String value;
  final String label;
  const DropdownChoice(this.value, this.label);
}

/// The choices with every value once (the first label wins).
List<DropdownChoice> uniqueChoices(List<DropdownChoice> choices) {
  final seen = <String>{};
  return [for (final c in choices) if (seen.add(c.value)) c];
}

/// [value] when it is one of the choices, else null (show nothing selected).
String? knownChoiceValue(String? value, List<DropdownChoice> choices) {
  if (value == null) return null;
  return choices.any((c) => c.value == value) ? value : null;
}

/// A stored value that is set but not one of the choices ("অজানা মান").
bool isUnknownChoice(String? value, List<DropdownChoice> choices) {
  final v = value?.trim() ?? '';
  return v.isNotEmpty && knownChoiceValue(value, choices) == null;
}

/// Puts [key] into [target] only when [value] is a valid choice, so a save
/// never writes an unknown value (and leaves the stored one untouched with
/// a merge write).
void putIfKnownChoice(Map<String, dynamic> target, String key, String? value, List<DropdownChoice> choices) {
  final known = knownChoiceValue(value, choices);
  if (known != null) target[key] = known;
}
