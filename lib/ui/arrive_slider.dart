import 'package:flutter/material.dart';

import '../core/constants.dart';

/// "25 min before", "At the listed time", "10 min after".
String arriveLabel(int min) => min == 0
    ? 'At the listed time'
    : min < 0
    ? '${-min} min before'
    : '$min min after';

/// When to arrive, relative to the listed time: up to [arriveRangeMin] minutes either side, in
/// 5-minute steps. Used by the search form and by Settings (the default).
class ArriveSlider extends StatelessWidget {
  const ArriveSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final int value;
  final ValueChanged<int> onChanged;

  /// Left and right inset of the text, to line up with the list it sits in.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: padding,
          leading: Icon(Icons.local_activity_outlined, color: theme.colorScheme.primary),
          title: const Text('Arrive'),
          subtitle: const Text(
            'How long before or after the listed time do you want to arrive? At some cinemas, '
            'but not all, the listed time is when the ads and trailers start. Viewer discretion is advised.',
          ),
          trailing: Text(arriveLabel(value), style: theme.textTheme.titleSmall),
        ),
        Slider(
          value: value.toDouble(),
          min: -arriveRangeMin.toDouble(),
          max: arriveRangeMin.toDouble(),
          divisions: arriveRangeMin * 2 ~/ 5,
          label: arriveLabel(value),
          onChanged: (v) => onChanged(v.round()),
        ),
        Padding(
          padding: padding.add(const EdgeInsets.symmetric(horizontal: 8)),
          child: Row(
            children: [
              Text('Before', style: small),
              const Spacer(),
              Text('Listed time', style: small),
              const Spacer(),
              Text('After', style: small),
            ],
          ),
        ),
      ],
    );
  }
}
