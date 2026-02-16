import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/sport.dart';
import '../services/team_service.dart';
import '../services/team_player_service.dart';
import '../theme/cs_theme.dart';
import '../widgets/ranking_selector.dart';
import '../widgets/ui/ui.dart';

/// Full-screen form to create a new team.
///
/// Sport is hardcoded to Tennis. The screen shows a Tennis hero image at the
/// top with "Team erstellen" overlay text, followed by the form fields.
class CreateTeamScreen extends StatefulWidget {
  const CreateTeamScreen({super.key});

  @override
  State<CreateTeamScreen> createState() => _CreateTeamScreenState();
}

class _CreateTeamScreenState extends State<CreateTeamScreen> {
  static const String _sportKey = 'tennis';
  late AppLocalizations l;

  final _nameCtrl = TextEditingController();
  final _leagueCtrl = TextEditingController(text: '3. Liga Herren');
  final _yearCtrl = TextEditingController(
    text: DateTime.now().year.toString(),
  );
  final _captainNameCtrl = TextEditingController();

  bool _playsSelf = false;
  bool _submitting = false;

  // Ranking dropdowns state
  String _rankingCountry = 'CH';
  int? _rankingValue;
  String? _rankingError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    l = AppLocalizations.of(context)!;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _leagueCtrl.dispose();
    _yearCtrl.dispose();
    _captainNameCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  //  Submit
  // ═══════════════════════════════════════════════════════════

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final year = int.tryParse(_yearCtrl.text.trim());
    final captainName = _captainNameCtrl.text.trim();

    if (name.isEmpty) {
      CsToast.error(context, l.enterTeamName);
      return;
    }
    if (captainName.length < 2) {
      CsToast.error(context, l.enterCaptainName);
      return;
    }
    if (year == null) {
      CsToast.error(context, l.invalidSeasonYear);
      return;
    }

    // Tennis + playsSelf → ranking required
    if (_playsSelf && _rankingValue == null) {
      setState(() {
        _rankingError = l.selectRankingError;
      });
      CsToast.error(context, l.selectRankingError);
      return;
    }

    setState(() => _submitting = true);

    try {
      final teamId = await TeamService.createTeam(
        name: name,
        clubName: null,
        league:
            _leagueCtrl.text.trim().isEmpty ? null : _leagueCtrl.text.trim(),
        seasonYear: year,
        sportKey: _sportKey,
        captainNickname: captainName,
      );

      if (_playsSelf) {
        try {
          await TeamPlayerService.upsertCaptainSlot(
            teamId: teamId,
            ranking: _rankingValue,
          );
        } catch (e) {
          // ignore: avoid_print
          print('CREATE_TEAM upsertCaptainSlot WARN: $e');
        }
      }

      if (!mounted) return;
      CsToast.success(context, l.teamCreatedToast);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      CsToast.error(context, l.teamCreateError);
      setState(() => _submitting = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Hero Header
  // ═══════════════════════════════════════════════════════════

  Widget _buildHeroHeader() {
    final sport = Sport.byKey(_sportKey);

    return SizedBox(
      height: 200,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background image
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(CsRadii.xl),
            ),
            child: Image.asset(
              sport?.assetPath ?? 'assets/sports/Tennis.jpg',
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.3),
              errorBuilder: (context, error, stack) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        (sport?.color ?? Colors.amber).withValues(alpha: 0.7),
                        sport?.color ?? Colors.amber,
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Dark gradient overlay for text readability
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(CsRadii.xl),
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.25),
                    Colors.black.withValues(alpha: 0.45),
                  ],
                ),
              ),
            ),
          ),

          // Title text
          Positioned(
            left: 20,
            bottom: 20,
            right: 20,
            child: Text(
              l.createTeamTitle,
              style: CsTextStyles.onDarkPrimary.copyWith(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Build
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: CsColors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Scrollable content ──
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero image header
                  _buildHeroHeader(),

                  // Form fields
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Team info fields
                        Text(l.teamNameLabel, style: CsTextStyles.labelSmall),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _nameCtrl,
                          decoration: InputDecoration(
                            hintText: l.teamNameHint,
                          ),
                          textCapitalization: TextCapitalization.words,
                          autofocus: true,
                        ),
                        const SizedBox(height: 16),

                        Text(
                          l.leagueLabel,
                          style: CsTextStyles.labelSmall,
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _leagueCtrl,
                          decoration: InputDecoration(
                            hintText: l.leagueHint,
                          ),
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: 16),

                        Text(l.seasonYearLabel, style: CsTextStyles.labelSmall),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _yearCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: '2026',
                          ),
                        ),

                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 16),

                        Text(
                          l.whatsYourName,
                          style: CsTextStyles.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l.captainNamePrompt,
                          style: CsTextStyles.bodySmall,
                        ),
                        const SizedBox(height: 12),

                        Text(
                          l.captainNameRequired,
                          style: CsTextStyles.labelSmall,
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _captainNameCtrl,
                          decoration: InputDecoration(
                            hintText: l.nicknameHint,
                          ),
                          textCapitalization: TextCapitalization.words,
                          maxLength: 30,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),

                        // iOS-style switch
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: CsColors.gray50,
                            borderRadius:
                                BorderRadius.circular(CsRadii.md),
                            border: Border.all(color: CsColors.gray200),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l.captainPlaysTitle,
                                      style: CsTextStyles.titleSmall,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      l.createTeamPlaysSelfSubtitle,
                                      style: CsTextStyles.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Switch.adaptive(
                                value: _playsSelf,
                                onChanged: _submitting
                                    ? null
                                    : (val) =>
                                        setState(() => _playsSelf = val),
                              ),
                            ],
                          ),
                        ),
                        if (_playsSelf) ...[
                          const SizedBox(height: 16),
                          RankingSelector(
                            country: _rankingCountry,
                            rankingValue: _rankingValue,
                            rankingError: _rankingError,
                            enabled: !_submitting,
                            onCountryChanged: (c) => setState(() {
                              _rankingCountry = c;
                              _rankingValue = null;
                              _rankingError = null;
                            }),
                            onRankingChanged: (v) => setState(() {
                              _rankingValue = v;
                              _rankingError = null;
                            }),
                          ),
                        ],

                        if (_submitting) ...[
                          const SizedBox(height: 20),
                          const LinearProgressIndicator(),
                        ],

                        // Extra bottom padding for scrolling
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Sticky CTA ──
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              12 + (bottomInset > 0 ? 0 : safeBottom),
            ),
            decoration: BoxDecoration(
              color: CsColors.white,
              border: Border(
                top: BorderSide(
                  color: CsColors.gray200.withValues(alpha: 0.6),
                  width: 0.5,
                ),
              ),
            ),
            child: CsPrimaryButton(
              onPressed: _submitting ? null : _submit,
              label: l.createButton,
              loading: _submitting,
            ),
          ),
        ],
      ),
    );
  }
}
