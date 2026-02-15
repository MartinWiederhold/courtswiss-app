import 'package:flutter/material.dart';
import '../../theme/cs_theme.dart';

/// Premium scaffold with gradient page background + standard padding.
///
/// Wraps children in a gradient from light gray to white.
/// Optionally makes the body scrollable.
class CsScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final bool scrollable;

  /// Extra padding around the body (default 16 on all sides).
  final EdgeInsetsGeometry padding;

  const CsScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.scrollable = false,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(padding: padding, child: body);

    if (scrollable) {
      content = SingleChildScrollView(child: content);
    }

    return Scaffold(
      extendBodyBehindAppBar: false,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: Container(
        decoration: const BoxDecoration(gradient: csPageGradient),
        child: content,
      ),
    );
  }
}

/// Variant of [CsScaffold] that takes a ListView-style body directly
/// (no extra padding / scrolling wrapper).
class CsScaffoldList extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  const CsScaffoldList({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: false,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: Container(
        decoration: const BoxDecoration(gradient: csPageGradient),
        child: body,
      ),
    );
  }
}
