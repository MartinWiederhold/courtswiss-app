import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/cs_theme.dart';

/// A self-contained dialog that asks the user to type a confirmation word
/// before allowing account deletion.
///
/// Returns `true` via [Navigator.pop] when the user confirms,
/// or `false` / `null` when they cancel.
/// Does NOT perform any deletion — the caller is responsible for that.
class DeleteAccountDialog extends StatefulWidget {
  /// The word the user must type to confirm (e.g. "LÖSCHEN" or "DELETE").
  final String confirmWord;

  const DeleteAccountDialog({super.key, required this.confirmWord});

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final typed = _controller.text.trim();
    final isMatch =
        typed.toUpperCase() == widget.confirmWord.toUpperCase();

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CsRadii.lg),
      ),
      title: Text(
        l.deleteAccountTitle,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.deleteAccountBody,
            style: TextStyle(
              fontSize: 14,
              color: CsColors.gray700,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l.typeToConfirm(widget.confirmWord),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: CsColors.gray900,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: widget.confirmWord,
              hintStyle: TextStyle(color: CsColors.gray300),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CsRadii.md),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            l.cancel,
            style: TextStyle(color: CsColors.gray800),
          ),
        ),
        TextButton(
          onPressed: isMatch
              ? () => Navigator.of(context).pop(true)
              : null,
          child: Text(
            l.deleteAccount,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isMatch ? CsColors.error : CsColors.gray300,
            ),
          ),
        ),
      ],
    );
  }
}
