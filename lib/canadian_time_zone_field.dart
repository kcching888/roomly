import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

// Location names are persisted; offsets are display-only and calculated for today.
const canadianTimeZones = <String, String>{
  'America/Vancouver': 'B.C. — Vancouver / Victoria',
  'America/Dawson_Creek': 'B.C. — Dawson Creek / Fort St. John',
  'America/Fort_Nelson': 'B.C. — Fort Nelson',
  'America/Creston': 'B.C. — Creston',
  'America/Edmonton': 'Alberta — Calgary / Edmonton; Alberta-aligned B.C.',
  'America/Regina': 'Saskatchewan — Regina / Saskatoon',
  'America/Swift_Current': 'Saskatchewan — Swift Current',
  'America/Winnipeg': 'Manitoba — Winnipeg',
  'America/Toronto': 'Ontario / Quebec — Toronto / Ottawa / Montreal',
  'America/Thunder_Bay': 'Ontario — Thunder Bay',
  'America/Atikokan': 'Ontario — Atikokan',
  'America/Rainy_River': 'Ontario — Rainy River',
  'America/Blanc-Sablon': 'Quebec — Blanc-Sablon',
  'America/Halifax': 'Nova Scotia / New Brunswick / P.E.I.',
  'America/Glace_Bay': 'Nova Scotia — Glace Bay',
  'America/Moncton': 'New Brunswick — Moncton',
  'America/St_Johns': 'Newfoundland — St. John’s',
  'America/Goose_Bay': 'Labrador — Goose Bay',
  'America/Whitehorse': 'Yukon — Whitehorse',
  'America/Dawson': 'Yukon — Dawson',
  'America/Yellowknife': 'Northwest Territories — Yellowknife',
  'America/Inuvik': 'Northwest Territories — Inuvik',
  'America/Iqaluit': 'Nunavut — Iqaluit',
  'America/Pangnirtung': 'Nunavut — Pangnirtung',
  'America/Rankin_Inlet': 'Nunavut — Rankin Inlet',
  'America/Resolute': 'Nunavut — Resolute',
  'America/Cambridge_Bay': 'Nunavut — Cambridge Bay',
};

class CanadianTimeZoneField extends StatelessWidget {
  const CanadianTimeZoneField({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.helperText,
  });
  final String? value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String? helperText;

  String _offset(String zone) {
    final minutes = tz.TZDateTime.from(
      DateTime.now().toUtc(),
      tz.getLocation(zone),
    ).timeZoneOffset.inMinutes;
    final absolute = minutes.abs();
    return 'UTC${minutes < 0 ? '-' : '+'}'
        '${(absolute ~/ 60).toString().padLeft(2, '0')}:'
        '${(absolute % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final locations = tz.timeZoneDatabase.locations;
    if (locations.isEmpty) {
      return const InputDecorator(
        decoration: InputDecoration(
          labelText: 'Organization time zone',
          border: OutlineInputBorder(),
        ),
        child: Text('Time-zone data is not initialized. Restart the app.'),
      );
    }
    final choices = <String, String>{
      for (final entry in canadianTimeZones.entries)
        if (locations.containsKey(entry.key)) entry.key: entry.value,
    };
    if (value != null && value!.isNotEmpty && locations.containsKey(value)) {
      choices.putIfAbsent(value!, () => 'Existing setting — $value');
    }
    final selected = choices.containsKey(value) ? value : null;
    final unknown = value != null && value!.isNotEmpty && selected == null;
    return DropdownButtonFormField<String>(
      key: ValueKey(value),
      initialValue: selected,
      isExpanded: true,
      menuMaxHeight: 440,
      decoration: InputDecoration(
        labelText: 'Organization time zone',
        border: const OutlineInputBorder(),
        helperText: unknown
            ? 'Saved zone "$value" is unavailable. Contact your platform administrator.'
            : helperText ??
                  'Choose the facility’s location. Offsets shown are for today; '
                      'booking calculations use the booking date.',
        helperMaxLines: 4,
      ),
      items: choices.entries
          .map(
            (entry) => DropdownMenuItem<String>(
              value: entry.key,
              child: Text(
                '${entry.value} (${_offset(entry.key)})',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      selectedItemBuilder: (context) => choices.entries
          .map(
            (entry) => Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${entry.value} (${_offset(entry.key)})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: enabled
          ? (zone) {
              if (zone != null) onChanged(zone);
            }
          : null,
      validator: !enabled
          ? null
          : (zone) => zone == null ? 'Select the facility’s time zone.' : null,
    );
  }
}
