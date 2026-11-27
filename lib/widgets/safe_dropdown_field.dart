import 'package:flutter/material.dart';

import '../utils/safe_dropdown.dart';

/// A DropdownButtonFormField that never asserts on stored data:
/// duplicate values are dropped, and a value that is not among the choices
/// shows nothing selected plus a small "অজানা মান: `value`" note.
class SafeDropdownField extends StatelessWidget {
  final String label;
  final String? value;
  final List<DropdownChoice> choices;
  final ValueChanged<String?>? onChanged;
  final IconData? icon;
  final bool dense;
  final InputBorder? border;
  final bool filled;

  const SafeDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.icon,
    this.dense = false,
    this.border,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final items = uniqueChoices(choices);
    final known = knownChoiceValue(value, items);
    final unknown = isUnknownChoice(value, items);

    return DropdownButtonFormField<String>(
      // A new key when the selection changes from outside (e.g. settings
      // loaded), because initialValue is read only once.
      key: ValueKey('$label|$known'),
      initialValue: known,
      isExpanded: true,
      hint: unknown ? const Text('Choose…') : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon),
        border: border ?? const OutlineInputBorder(),
        isDense: dense,
        filled: filled,
        fillColor: filled ? Colors.white : null,
        helperText: unknown ? 'অজানা মান: ${value!.trim()}' : null,
        helperMaxLines: 2,
        helperStyle: const TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.w700),
      ),
      items: [
        for (final c in items)
          DropdownMenuItem<String>(
            value: c.value,
            child: Text(c.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
