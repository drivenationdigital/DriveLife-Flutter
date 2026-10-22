// Why the Shop's product grid passes `padding: EdgeInsets.zero`.
//
// A vertical GridView or ListView with a null padding does not get zero —
// BoxScrollView reaches into MediaQuery and adopts its vertical insets, so
// that a full-screen list clears the notch and the home indicator without
// anyone having to ask. That is the right default for a list that owns the
// screen and the wrong one for a grid halfway down a page, and the Shop's
// grid is the second kind: the shell above it measures the status bar into
// a SizedBox rather than consuming it, so the inset was still live and
// turned up as a band of empty space under the category pills.
//
// These two tests pin the behaviour rather than the fix, so they stay
// meaningful if the grid is rewritten.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// A grid inside a page, the way the Shop's Browse tab nests one: a row
  /// of pills, then the grid, inside a scroll view, under a status bar
  /// inset that nothing has consumed.
  Widget page({EdgeInsets? gridPadding}) {
    return MediaQuery(
      data: const MediaQueryData(padding: EdgeInsets.only(top: 50, bottom: 34)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(key: Key('pills'), height: 40),
              GridView.builder(
                key: const Key('grid'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: gridPadding,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                    ),
                itemCount: 2,
                itemBuilder: (_, i) =>
                    SizedBox(key: Key('cell$i'), height: 100),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Distance from the bottom of the pills to the top of the first cell.
  double gapAfterPills(WidgetTester tester) {
    final pills = tester.getRect(find.byKey(const Key('pills')));
    final firstCell = tester.getRect(find.byKey(const Key('cell0')));
    return firstCell.top - pills.bottom;
  }

  testWidgets('a null padding leaves the status bar inset under the pills', (
    tester,
  ) async {
    await tester.pumpWidget(page());

    // The 50 that MediaQuery reported, inherited rather than asked for.
    // This is the bug, not the fix — if a Flutter release ever stops doing
    // this, this test fails and the explicit zero becomes unnecessary.
    expect(gapAfterPills(tester), 50);
  });

  testWidgets('EdgeInsets.zero puts the first row against the pills', (
    tester,
  ) async {
    await tester.pumpWidget(page(gridPadding: EdgeInsets.zero));

    expect(gapAfterPills(tester), 0);
  });
}
