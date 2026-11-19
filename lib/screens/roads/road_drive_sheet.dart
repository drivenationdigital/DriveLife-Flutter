import 'package:drivelife/api/garage_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/providers/user_provider.dart';
import 'package:drivelife/theme/dl_type.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// What somebody drove a road in, and roughly when.
///
/// ── WHY BOTH ANSWERS ARE OPTIONAL ───────────────────────────────────
///
/// The fact is "I have driven this". The car and the date are the
/// story, and a story is worth asking for but never worth blocking on.
///
/// So the sheet opens with "Just mark it driven" as a real way out,
/// not as a cancel. A road driven in a hire car, from the passenger
/// seat, or in something sold years ago is still driven, and an
/// enthusiast with forty roads to tick off should not be interrogated
/// forty times.
class RoadDriveSheet {
  /// Returns what was chosen, or null if the sheet was dismissed.
  static Future<RoadDriveAnswer?> show(
    BuildContext context, {
    required String roadTitle,
    int vehicleId = 0,
    String droveOn = '',
  }) {
    return showModalBottomSheet<RoadDriveAnswer>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _Body(
        roadTitle: roadTitle,
        vehicleId: vehicleId,
        droveOn: droveOn,
      ),
    );
  }
}

/// The answer, or as much of it as was given.
class RoadDriveAnswer {
  final int vehicleId;

  /// YYYY-MM-DD, or empty for "did not say".
  final String droveOn;

  const RoadDriveAnswer({this.vehicleId = 0, this.droveOn = ''});
}

class _Body extends StatefulWidget {
  final String roadTitle;
  final int vehicleId;
  final String droveOn;

  const _Body({
    required this.roadTitle,
    required this.vehicleId,
    required this.droveOn,
  });

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  List<Map<String, dynamic>> _vehicles = const [];

  bool _loading = true;

  late int _vehicleId = widget.vehicleId;
  DateTime? _when;

  @override
  void initState() {
    super.initState();

    _when = _parse(widget.droveOn);
    _loadGarage();
  }

  /// A stored YYYY-MM-DD, or null.
  static DateTime? _parse(String raw) {
    final parts = raw.split('-');

    if (parts.length != 3) return null;

    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);

    if (year == null || month == null || day == null) return null;

    return DateTime(year, month, day);
  }

  static String _format(DateTime? when) {
    if (when == null) return '';

    final month = when.month.toString().padLeft(2, '0');
    final day = when.day.toString().padLeft(2, '0');

    return '${when.year}-$month-$day';
  }

  Future<void> _loadGarage() async {
    final user = Provider.of<UserProvider>(context, listen: false).user;

    final rows = user == null ? null : await GarageAPI.getUserGarage(user.id);

    if (!mounted) return;

    setState(() {
      _vehicles = (rows ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      _loading = false;
    });
  }

  static String _nameOf(Map<String, dynamic> vehicle) {
    final name = [
      '${vehicle['make'] ?? ''}'.trim(),
      '${vehicle['model'] ?? ''}'.trim(),
      '${vehicle['variant'] ?? ''}'.trim(),
    ].where((p) => p.isNotEmpty).join(' ');

    if (name.isNotEmpty) return name;

    final reg = '${vehicle['registration'] ?? ''}'.trim();

    return reg.isNotEmpty ? reg : 'A vehicle';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: _when ?? now,
      // Far enough back for a car anybody still talks about, and not
      // one day into the future: this records a drive that happened.
      firstDate: DateTime(now.year - 60),
      lastDate: now,
    );

    if (picked != null && mounted) setState(() => _when = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDDDDD),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              DlHeading(
                'You drove ${widget.roadTitle}',
                fontSize: 24,
                color: const Color(0xFF0B0B0B),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              const Text(
                'What were you in, and roughly when?',
                style: TextStyle(fontSize: 14.5, color: Color(0xFF6B6B6B)),
              ),

              const SizedBox(height: 18),

              if (_loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: theme.primaryColor,
                    ),
                  ),
                )
              else if (_vehicles.isEmpty)
                // Not an error and not a blocker — plenty of people
                // have no garage yet, and the road was still driven.
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Nothing in your garage yet. Add a vehicle and you '
                    'can record what you drove it in.',
                    style: TextStyle(fontSize: 14, color: Color(0xFF8A8A8A)),
                  ),
                )
              else
                ConstrainedBox(
                  // Enough for three or four without the sheet taking
                  // over the screen; a big garage scrolls.
                  constraints: const BoxConstraints(maxHeight: 230),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _vehicles.length,
                    itemBuilder: (_, i) {
                      final vehicle = _vehicles[i];
                      final id = int.tryParse('${vehicle['id'] ?? ''}') ?? 0;

                      return _VehicleRow(
                        name: _nameOf(vehicle),
                        image: '${vehicle['cover_photo'] ?? ''}'.trim(),
                        selected: id == _vehicleId && id > 0,
                        accent: theme.primaryColor,
                        // Tapping the chosen one again clears it, so a
                        // wrong tap is undoable without closing up.
                        onTap: () => setState(
                          () => _vehicleId = _vehicleId == id ? 0 : id,
                        ),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 14),

              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE2E2E2)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.event_rounded,
                        size: 19,
                        color: Color(0xFF6B6B6B),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _when == null
                              ? 'When was it? (optional)'
                              : _monthYear(_when!),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _when == null
                                ? const Color(0xFF8A8A8A)
                                : const Color(0xFF0B0B0B),
                          ),
                        ),
                      ),
                      if (_when != null)
                        GestureDetector(
                          onTap: () => setState(() => _when = null),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: Color(0xFF8A8A8A),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(
                    context,
                    RoadDriveAnswer(
                      vehicleId: _vehicleId,
                      droveOn: _format(_when),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),

              // A way out that still records the drive. Not a cancel —
              // somebody who got this far has driven the road, and
              // losing that because they could not remember the month
              // would be the wrong answer to a question we chose to
              // ask.
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, const RoadDriveAnswer()),
                child: const Text(
                  'Just mark it driven',
                  style: TextStyle(
                    color: Color(0xFF6B6B6B),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _monthYear(DateTime when) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];

    return '${months[when.month - 1]} ${when.year}';
  }
}

class _VehicleRow extends StatelessWidget {
  final String name;
  final String image;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _VehicleRow({
    required this.name,
    required this.image,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? accent : const Color(0xFFE2E2E2),
              width: selected ? 1.8 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 52,
                  height: 40,
                  child: image.isNotEmpty
                      ? Image.network(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const ColoredBox(color: Color(0xFFEDEDED)),
                        )
                      : const ColoredBox(color: Color(0xFFEDEDED)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 21,
                color: selected ? accent : const Color(0xFFD5D5D5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
