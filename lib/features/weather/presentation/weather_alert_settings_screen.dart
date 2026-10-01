import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../data/weather_alert_service.dart';

/// Weather alerts: the member picks the conditions they care about and the app
/// warns them once a day when those conditions are met.
///
/// Design notes:
///  * **Opt-in and off by default.** No row means never contacted.
///  * **One alert per local day.** The dedupe is enforced in the database and
///    again when the claim is written, so a twice-hourly sweep cannot spam.
///  * **Quiet hours** are configurable and enforced server-side, so an app bug
///    cannot wake somebody at 3am.
///  * **Server-side sweep** is what makes this useful: it reaches a member whose
///    phone is closed, which an on-device timer could never do.
class WeatherAlertSettingsScreen extends ConsumerStatefulWidget {
  const WeatherAlertSettingsScreen({super.key});

  @override
  ConsumerState<WeatherAlertSettingsScreen> createState() =>
      _WeatherAlertSettingsScreenState();
}

class _WeatherAlertSettingsScreenState
    extends ConsumerState<WeatherAlertSettingsScreen> {
  final _svc = WeatherAlertService();
  bool _loading = true;
  bool _saving = false;

  bool _enabled = false;
  double? _maxTemp;
  double? _minTemp;
  double? _rainPct;
  double? _windKph;
  int _quietStart = 0;
  int _quietEnd = 6;
  String _timezone = 'Africa/Lusaka';
  String? _label;
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final p = await _svc.load();
    if (!mounted) return;
    setState(() {
      if (p != null) {
        _enabled = p.enabled;
        _maxTemp = p.maxTempC;
        _minTemp = p.minTempC;
        _rainPct = p.rainProbabilityPct;
        _windKph = p.maxWindKph;
        _quietStart = p.quietStartHour;
        _quietEnd = p.quietEndHour;
        _timezone = p.timezone;
        _label = p.locationLabel;
        _lat = p.lat;
        _lng = p.lng;
      }
      _loading = false;
    });
  }

  bool get _hasThreshold =>
      _maxTemp != null ||
      _minTemp != null ||
      _rainPct != null ||
      _windKph != null;

  Future<void> _save() async {
    if (_enabled && !_hasThreshold) {
      _toast('Choose at least one condition to be warned about.');
      return;
    }
    setState(() => _saving = true);
    final ok = await _svc.save(WeatherAlertPrefs(
      enabled: _enabled,
      maxTempC: _maxTemp,
      minTempC: _minTemp,
      rainProbabilityPct: _rainPct,
      maxWindKph: _windKph,
      quietStartHour: _quietStart,
      quietEndHour: _quietEnd,
      timezone: _timezone,
      lat: _lat,
      lng: _lng,
      locationLabel: _label,
    ));
    if (!mounted) return;
    setState(() => _saving = false);
    _toast(ok
        ? 'Weather alerts saved'
        : 'Could not save your settings. Please try again.');
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  String _hour(int h) {
    if (h == 0) return '12:00 AM';
    if (h < 12) return '$h:00 AM';
    if (h == 12) return '12:00 PM';
    return '${h - 12}:00 PM';
  }

  @override
  Widget build(BuildContext context) {
    final brand = Theme.of(context).colorScheme.primary;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weather Alerts'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(LucideIcons.check, size: 16),
            label: const Text('SAVE'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // ── Master switch ────────────────────────────────────────────────
          Card(
            child: SwitchListTile(
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
              title: const Text('Weather warnings'),
              subtitle: const Text(
                'Off by default. We only message you when a condition you '
                'chose is actually expected.',
              ),
              secondary: Icon(LucideIcons.cloudSun, color: brand),
            ),
          ),
          const SizedBox(height: 8),

          if (_enabled) ...[
            _section(context, 'Warn me about'),
            _threshold(
              context,
              icon: LucideIcons.thermometerSun,
              title: 'If it is very hot',
              value: _maxTemp,
              unit: '°C or above',
              min: 25,
              max: 50,
              onChanged: (v) => setState(() => _maxTemp = v),
            ),
            _threshold(
              context,
              icon: LucideIcons.snowflake,
              title: 'If it is very cold',
              value: _minTemp,
              unit: '°C or below',
              min: -5,
              max: 20,
              onChanged: (v) => setState(() => _minTemp = v),
            ),
            _threshold(
              context,
              icon: LucideIcons.cloudRain,
              title: 'If rain is likely',
              value: _rainPct,
              unit: '% chance or more',
              min: 10,
              max: 95,
              isPercent: true,
              onChanged: (v) => setState(() => _rainPct = v),
            ),
            _threshold(
              context,
              icon: LucideIcons.wind,
              title: 'If it is very windy',
              value: _windKph,
              unit: 'km/h or more',
              min: 10,
              max: 120,
              onChanged: (v) => setState(() => _windKph = v),
            ),
            const SizedBox(height: 8),

            // ── Quiet hours ────────────────────────────────────────────────
            _section(context, 'Do not disturb'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'We will never send a weather alert between these '
                      'times. Useful for protecting your rest.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _hourChip('From', _quietStart, (h) {
                            setState(() => _quietStart = h);
                          }),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _hourChip('Until', _quietEnd, (h) {
                            setState(() => _quietEnd = h);
                          }),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ── Location / timezone ────────────────────────────────────────
            _section(context, 'Your location'),
            Card(
              child: ListTile(
                leading: Icon(LucideIcons.mapPin, color: brand),
                title: Text(_label ?? 'Use my church location'),
                subtitle: Text('Timezone: $_timezone'),
                trailing: _lat == null
                    ? null
                    : Text('${_lat!.toStringAsFixed(3)}, '
                        '${_lng!.toStringAsFixed(3)}',
                        style: const TextStyle(fontSize: 11)),
              ),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'How it works: a check runs twice an hour on our servers, so '
                'you still get warned even if the app is closed. You will '
                'receive at most one alert per day.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
        child: Text(t.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: Theme.of(context).colorScheme.primary,
            )),
      );

  Widget _hourChip(String label, int value, ValueChanged<int> onChanged) {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: value, minute: 0),
        );
        if (picked != null) onChanged(picked.hour);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 2),
            Text(_hour(value),
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _threshold(
    BuildContext context, {
    required IconData icon,
    required String title,
    required double? value,
    required String unit,
    required double min,
    required double max,
    required ValueChanged<double?> onChanged,
    bool isPercent = false,
  }) {
    final on = value != null;
    final accent = Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: on ? accent : Colors.grey),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: on ? null : Colors.grey,
                      )),
                ),
                Switch(
                  value: on,
                  onChanged: (v) => onChanged(v ? min : null),
                ),
              ],
            ),
            if (on)
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: value.clamp(min, max),
                      min: min,
                      max: max,
                      divisions: ((max - min) / (isPercent ? 5 : 1)).round().clamp(1, 200),
                      label: '${value.round()}${isPercent ? '%' : ''}',
                      onChanged: (v) => onChanged(v),
                    ),
                  ),
                  SizedBox(
                    width: 92,
                    child: Text('${value.round()}${isPercent ? '%' : ''} $unit',
                        style: const TextStyle(fontSize: 11)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
