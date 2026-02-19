import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../services/match_service.dart';
import '../theme/cs_theme.dart';
import '../widgets/ui/ui.dart';

/// Screen for creating OR editing a match.
/// Pass [existingMatch] to enter edit mode.
class CreateMatchScreen extends StatefulWidget {
  final String teamId;
  final Map<String, dynamic>? existingMatch;

  const CreateMatchScreen({
    super.key,
    required this.teamId,
    this.existingMatch,
  });

  bool get isEditing => existingMatch != null;

  @override
  State<CreateMatchScreen> createState() => _CreateMatchScreenState();
}

class _CreateMatchScreenState extends State<CreateMatchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _opponentCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool? _isHome = true; // true=Heim, false=Auswärts, null=unbekannt
  DateTime? _matchDate;
  TimeOfDay? _matchTime;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.existingMatch;
    if (m != null) {
      _opponentCtrl.text = m['opponent'] as String? ?? '';
      _locationCtrl.text = m['location'] as String? ?? '';
      _noteCtrl.text = m['note'] as String? ?? '';
      _isHome = m['is_home'] as bool?;
      final dt = DateTime.tryParse(m['match_at'] ?? '')?.toLocal();
      if (dt != null) {
        _matchDate = DateTime(dt.year, dt.month, dt.day);
        _matchTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
      }
    }
  }

  @override
  void dispose() {
    _opponentCtrl.dispose();
    _locationCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _matchDate ?? now,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date != null) setState(() => _matchDate = date);
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _matchTime ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (time != null) setState(() => _matchTime = time);
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context)!;

    if (!_formKey.currentState!.validate()) return;
    if (_matchDate == null || _matchTime == null) {
      CsToast.info(context, l.chooseDateAndTime);
      return;
    }

    setState(() => _saving = true);

    final matchAt = DateTime(
      _matchDate!.year,
      _matchDate!.month,
      _matchDate!.day,
      _matchTime!.hour,
      _matchTime!.minute,
    );

    try {
      final opponentVal = _opponentCtrl.text.trim().isEmpty
          ? null
          : _opponentCtrl.text.trim();

      if (widget.isEditing) {
        await MatchService.updateMatch(widget.existingMatch!['id'] as String, {
          'opponent': opponentVal,
          'match_at': matchAt.toUtc().toIso8601String(),
          'is_home': _isHome,
          'location': _locationCtrl.text.trim().isEmpty
              ? null
              : _locationCtrl.text.trim(),
          'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        });
      } else {
        await MatchService.createMatch(
          teamId: widget.teamId,
          opponent: opponentVal ?? '',
          matchAt: matchAt,
          isHome: _isHome,
          location: _locationCtrl.text.trim().isEmpty
              ? null
              : _locationCtrl.text.trim(),
          note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        );
      }
      if (!mounted) return;
      CsToast.success(context, widget.isEditing ? l.matchUpdated : l.matchCreated);
      Navigator.pop(context, true); // true = changed
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, l.matchCreateError);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    final dateText = _matchDate != null
        ? '${_matchDate!.day.toString().padLeft(2, '0')}.'
              '${_matchDate!.month.toString().padLeft(2, '0')}.'
              '${_matchDate!.year}'
        : l.chooseDate;
    final timeText = _matchTime != null
        ? '${_matchTime!.hour.toString().padLeft(2, '0')}:'
              '${_matchTime!.minute.toString().padLeft(2, '0')}'
        : l.chooseTime;

    return CsScaffoldList(
      appBar: CsGlassAppBar(
        title: widget.isEditing ? l.editMatch : l.addMatch,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CsAnimatedEntrance(
                child: CsCard(
                  backgroundColor: CsColors.white,
                  borderColor: CsColors.gray200.withValues(alpha: 0.45),
                  boxShadow: CsShadows.soft,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.sports_tennis,
                            color: CsColors.gray900,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            l.matchDetails,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: CsColors.gray900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _opponentCtrl,
                        decoration: InputDecoration(
                          labelText: l.opponent,
                          hintText: l.opponentHint,
                        ),
                        style: const TextStyle(color: CsColors.gray900),
                      ),
                    ],
                  ),
                ),
              ),

              CsAnimatedEntrance(
                delay: const Duration(milliseconds: 60),
                child: CsCard(
                  backgroundColor: CsColors.white,
                  borderColor: CsColors.gray200.withValues(alpha: 0.45),
                  boxShadow: CsShadows.soft,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.dateAndTime,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: CsColors.gray900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickDate,
                              icon: const Icon(
                                Icons.calendar_today,
                                size: 18,
                              ),
                              label: Text(dateText),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: CsColors.gray900,
                                side: const BorderSide(
                                  color: CsColors.gray300,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickTime,
                              icon: const Icon(
                                Icons.access_time,
                                size: 18,
                              ),
                              label: Text(timeText),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: CsColors.gray900,
                                side: const BorderSide(
                                  color: CsColors.gray300,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<bool?>(
                          segments: [
                            ButtonSegment<bool?>(
                              value: true,
                              label: Text(l.home),
                              icon: const Icon(Icons.home, size: 16),
                            ),
                            ButtonSegment<bool?>(
                              value: false,
                              label: Text(l.away),
                              icon: const Icon(Icons.directions_car_outlined, size: 16),
                            ),
                            const ButtonSegment<bool?>(
                              value: null,
                              label: Text('Unbekannt'),
                              icon: Icon(Icons.help_outline, size: 16),
                            ),
                          ],
                          selected: {_isHome},
                          onSelectionChanged: (v) {
                            HapticFeedback.selectionClick();
                            setState(() => _isHome = v.first);
                          },
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return CsColors.black;
                              }
                              return CsColors.white;
                            }),
                            foregroundColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return CsColors.white;
                              }
                              return CsColors.gray900;
                            }),
                            textStyle: const WidgetStatePropertyAll(
                              TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                            visualDensity: VisualDensity.compact,
                            side: const WidgetStatePropertyAll(
                              BorderSide(color: CsColors.gray300),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              CsAnimatedEntrance(
                delay: const Duration(milliseconds: 120),
                child: CsCard(
                  backgroundColor: CsColors.white,
                  borderColor: CsColors.gray200.withValues(alpha: 0.45),
                  boxShadow: CsShadows.soft,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.details,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: CsColors.gray900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _locationCtrl,
                        decoration: InputDecoration(
                          labelText: l.location,
                          hintText: l.locationHint,
                        ),
                        style: const TextStyle(color: CsColors.gray900),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _noteCtrl,
                        decoration: InputDecoration(
                          labelText: l.noteOptional,
                          hintText: l.noteHint,
                        ),
                        style: const TextStyle(color: CsColors.gray900),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: LinearProgressIndicator(),
                ),

              CsAnimatedEntrance(
                delay: const Duration(milliseconds: 180),
                child: CsPrimaryButton(
                  onPressed: _saving ? null : _save,
                  loading: _saving,
                  icon: Icon(
                    widget.isEditing ? Icons.check : Icons.save,
                    size: 18,
                  ),
                  label: widget.isEditing
                      ? l.saveChanges
                      : l.createMatch,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
