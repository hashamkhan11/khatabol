import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khatabol/data/ledger_repository.dart';
import 'package:khatabol/ui/common.dart';
import 'package:khatabol/ui/theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late LedgerRepository repo;
  late int loads;

  setUp(() {
    repo = LedgerRepository(SupabaseClient('http://localhost', 'key'));
    loads = 0;
  });

  Widget view() => AsyncView<int>(
        cacheKey: 'count',
        load: () async => ++loads,
        builder: (context, n, reload) => Text('loaded $n'),
      );

  Widget app({Widget? home, GlobalKey<NavigatorState>? nav}) => Repo(
        repository: repo,
        child: MaterialApp(navigatorKey: nav, theme: buildTheme(Brightness.light), home: home),
      );

  testWidgets('refreshes when coming back from a page on top', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(app(nav: nav, home: Scaffold(body: view())));
    await tester.pumpAndSettle();
    expect(find.text('loaded 1'), findsOneWidget);

    nav.currentState!.push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('party'))));
    await tester.pumpAndSettle();
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('loaded 2'), findsOneWidget);
  });

  testWidgets('a hidden tab skips changes and refreshes when shown', (tester) async {
    var shown = false;
    late StateSetter setShown;
    await tester.pumpWidget(app(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          setShown = setState;
          return TickerMode(enabled: shown, child: view());
        }),
      ),
    ));
    await tester.pumpAndSettle();
    expect(loads, 1);

    repo.markChanged();
    await tester.pumpAndSettle();
    expect(loads, 1);

    setShown(() => shown = true);
    await tester.pumpAndSettle();
    expect(find.text('loaded 2'), findsOneWidget);

    repo.markChanged();
    await tester.pumpAndSettle();
    expect(find.text('loaded 3'), findsOneWidget);
  });
}
