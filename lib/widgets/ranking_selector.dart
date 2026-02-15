import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/ranking_data.dart';
import '../theme/cs_theme.dart';

/// Two-step inline dropdown selector: Country + Ranking.
///
/// Both fields open a floating overlay list anchored to the field.
/// The overlay opens below if there is enough room, otherwise above.
/// No Dialog, no BottomSheet, no Modal — pure floating overlay.
class RankingSelector extends StatefulWidget {
  const RankingSelector({
    super.key,
    required this.country,
    this.rankingValue,
    required this.onCountryChanged,
    required this.onRankingChanged,
    this.rankingError,
    this.enabled = true,
  });

  final String country;
  final int? rankingValue;
  final ValueChanged<String> onCountryChanged;
  final ValueChanged<int> onRankingChanged;
  final String? rankingError;
  final bool enabled;

  @override
  State<RankingSelector> createState() => _RankingSelectorState();
}

enum _ActiveDrop { none, country, ranking }

class _RankingSelectorState extends State<RankingSelector> {
  final _countryLink = LayerLink();
  final _rankingLink = LayerLink();
  final _countryKey = GlobalKey();
  final _rankingKey = GlobalKey();

  OverlayEntry? _entry;
  _ActiveDrop _active = _ActiveDrop.none;

  // ── Lifecycle ──────────────────────────────────────────────

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  // ── Open / Close ───────────────────────────────────────────

  void _close() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
    if (_active != _ActiveDrop.none) {
      _active = _ActiveDrop.none;
      if (mounted) setState(() {});
    }
  }

  void _toggle(_ActiveDrop which) {
    if (!widget.enabled) return;
    if (_active == which) {
      _close();
      return;
    }
    _close();

    // Dismiss keyboard before opening the dropdown.
    FocusManager.instance.primaryFocus?.unfocus();

    HapticFeedback.selectionClick();

    // Small delay lets keyboard dismiss settle so we measure
    // correct screen positions (no layout shift in the sheet).
    Future.delayed(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      // Guard: another dropdown may have opened during the delay.
      if (_active != _ActiveDrop.none) return;

      final LayerLink link;
      final GlobalKey fieldKey;
      final List<Widget> items;

      switch (which) {
        case _ActiveDrop.country:
          link = _countryLink;
          fieldKey = _countryKey;
          items = _countryItems();
        case _ActiveDrop.ranking:
          link = _rankingLink;
          fieldKey = _rankingKey;
          items = _rankingItems();
        case _ActiveDrop.none:
          return;
      }

      // ── Measure available space above & below the field ──
      final box =
          fieldKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) return;

      final fieldSize = box.size;
      final fieldGlobal = box.localToGlobal(Offset.zero);
      final screenH = MediaQuery.of(context).size.height;
      final bottomPad = MediaQuery.of(context).viewInsets.bottom;

      final spaceBelow =
          screenH - bottomPad - fieldGlobal.dy - fieldSize.height - 8;
      final spaceAbove = fieldGlobal.dy - MediaQuery.of(context).padding.top - 8;

      // Open above when space below is too tight.
      final bool openAbove = spaceBelow < 180 && spaceAbove > spaceBelow;

      // Cap maxHeight at 300 but don't exceed available room.
      final double maxH = openAbove
          ? spaceAbove.clamp(120, 300).toDouble()
          : spaceBelow.clamp(120, 300).toDouble();

      final width = fieldSize.width;

      _entry = OverlayEntry(
        builder: (_) => _FloatingDropdown(
          link: link,
          width: width,
          maxHeight: maxH,
          openAbove: openAbove,
          onDismiss: _close,
          items: items,
        ),
      );

      Overlay.of(context).insert(_entry!);
      _active = which;
      setState(() {}); // update chevron
    });
  }

  // ── Country items ──────────────────────────────────────────

  List<Widget> _countryItems() {
    return [
      _sectionHeader('Verfügbar'),
      for (final c in RankingData.countries)
        _itemTile(
          label: c.name,
          selected: c.code == widget.country,
          onTap: () {
            _close();
            if (c.code != widget.country) {
              HapticFeedback.selectionClick();
              widget.onCountryChanged(c.code);
            }
          },
        ),
    ];
  }

  // ── Ranking items ──────────────────────────────────────────

  List<Widget> _rankingItems() {
    final sections = RankingData.sectionsFor(widget.country);
    final list = <Widget>[];
    for (final section in sections) {
      list.add(_sectionHeader(section.title));
      for (final opt in section.options) {
        list.add(_itemTile(
          label: opt.label,
          selected: opt.value == widget.rankingValue,
          onTap: () {
            _close();
            HapticFeedback.selectionClick();
            widget.onRankingChanged(opt.value);
          },
        ));
      }
    }
    return list;
  }

  // ── Reusable sub-widgets ───────────────────────────────────

  static Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: CsColors.gray500,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  static Widget _itemTile({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: selected ? CsColors.gray50 : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: CsColors.gray900,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check, size: 16, color: CsColors.gray900),
          ],
        ),
      ),
    );
  }

  // ── Country display name ───────────────────────────────────

  String get _countryName {
    for (final c in RankingData.countries) {
      if (c.code == widget.country) return c.name;
    }
    return widget.country;
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Country field ──
        Text('Land *', style: CsTextStyles.labelSmall),
        const SizedBox(height: 6),
        CompositedTransformTarget(
          link: _countryLink,
          child: GestureDetector(
            key: _countryKey,
            onTap: () => _toggle(_ActiveDrop.country),
            child: InputDecorator(
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                hintText: 'Bitte auswählen',
                suffixIcon: AnimatedRotation(
                  turns: _active == _ActiveDrop.country ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 130),
                  curve: Curves.easeOut,
                  child: const Icon(
                    Icons.arrow_drop_down,
                    color: CsColors.gray500,
                  ),
                ),
              ),
              isEmpty: false,
              child: Text(
                _countryName,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Ranking field ──
        Text('Ranking *', style: CsTextStyles.labelSmall),
        const SizedBox(height: 6),
        CompositedTransformTarget(
          link: _rankingLink,
          child: GestureDetector(
            key: _rankingKey,
            onTap: () => _toggle(_ActiveDrop.ranking),
            child: InputDecorator(
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                hintText: 'Bitte auswählen',
                errorText: widget.rankingError,
                suffixIcon: AnimatedRotation(
                  turns: _active == _ActiveDrop.ranking ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 130),
                  curve: Curves.easeOut,
                  child: const Icon(
                    Icons.arrow_drop_down,
                    color: CsColors.gray500,
                  ),
                ),
              ),
              isEmpty: widget.rankingValue == null,
              child: widget.rankingValue != null
                  ? Text(
                      RankingData.label(widget.rankingValue),
                      style: const TextStyle(fontSize: 16),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  Floating dropdown card — opens above OR below the anchor field
// ═════════════════════════════════════════════════════════════════

class _FloatingDropdown extends StatelessWidget {
  const _FloatingDropdown({
    required this.link,
    required this.width,
    required this.maxHeight,
    required this.openAbove,
    required this.onDismiss,
    required this.items,
  });

  final LayerLink link;
  final double width;
  final double maxHeight;
  final bool openAbove;
  final VoidCallback onDismiss;
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Full-screen tap barrier (outside = close) ──
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),

        // ── Dropdown card, floating above or below the field ──
        CompositedTransformFollower(
          link: link,
          targetAnchor:
              openAbove ? Alignment.topLeft : Alignment.bottomLeft,
          followerAnchor:
              openAbove ? Alignment.bottomLeft : Alignment.topLeft,
          offset: Offset(0, openAbove ? -4 : 4),
          child: SizedBox(
            width: width,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 130),
              curve: Curves.easeOut,
              builder: (_, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (openAbove ? 4 : -4) * (1 - t)),
                  child: child,
                ),
              ),
              child: Container(
                constraints: BoxConstraints(maxHeight: maxHeight),
                decoration: BoxDecoration(
                  color: CsColors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: CsColors.gray200),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  color: Colors.transparent,
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: items,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
