import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khatabol/screens/account_sheet.dart';
import 'package:khatabol/ui/common.dart';
import 'package:khatabol/ui/theme.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
      );

  group('passwordProblem', () {
    test('needs at least 8 characters', () {
      expect(passwordProblem('short', 'short'), isNotNull);
      expect(passwordProblem('longenough', 'longenough'), isNull);
    });

    test('both entries must match', () {
      expect(passwordProblem('longenough', 'longenouhg'), isNotNull);
    });
  });

  testWidgets('Segments reports the tapped option', (tester) async {
    String? picked;
    await tester.pumpWidget(app(Segments<String>(
      options: const [('cash', 'Cash'), ('bank', 'Bank')],
      selected: 'cash',
      onChanged: (v) => picked = v,
    )));
    await tester.tap(find.text('Bank'));
    expect(picked, 'bank');
  });

  testWidgets('ChoiceField picks from a sheet', (tester) async {
    String? value = 'a';
    await tester.pumpWidget(app(StatefulBuilder(
      builder: (context, setState) => ChoiceField<String>(
        label: 'Type',
        options: const [('a', 'Apple'), ('b', 'Banana')],
        value: value,
        onChanged: (v) => setState(() => value = v),
      ),
    )));
    expect(find.text('Apple'), findsOneWidget);
    await tester.tap(find.byType(ChoiceField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Banana'));
    await tester.pumpAndSettle();
    expect(value, 'b');
    expect(find.text('Banana'), findsOneWidget);
  });
}
