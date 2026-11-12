import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/model/model.dart';
import 'package:project_er_operation/panel/panel.dart';

import '../support/sample_models.dart';
import '../support/session_support.dart';

void main() {
  testWidgets('トリガーを持つテーブルには「トリガーN」を表示し、持たないテーブルとビューには表示しない', (tester) async {
    final m = fullModel(); // orders はトリガー2つ
    final s = newSession(model: m);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: s,
          builder: (_, _) => TableListPanel(session: s, onReveal: (_) {}, onPlace: (_) {}),
        ),
      ),
    ));
    expect(find.text('トリガー2'), findsOneWidget);
    expect(find.textContaining('トリガー'), findsOneWidget);
    final orders = m.tables.firstWhere((t) => t.physicalName == 'orders');
    final customers = m.tables.firstWhere((t) => t.physicalName == 'customers');
    expect(find.byKey(ValueKey('trg${orders.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('trg${customers.id}')), findsNothing);
    // トリガーが増えると表示が更新される
    customers.triggers.add(TriggerDef(id: m.allocateId()));
    s.notify(null);
    await tester.pump();
    expect(find.text('トリガー1'), findsOneWidget);
  });
}
