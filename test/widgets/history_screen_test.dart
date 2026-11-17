import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kore_no_kae_dore/core/models/match_level.dart';
import 'package:kore_no_kae_dore/core/models/purchase_result.dart';
import 'package:kore_no_kae_dore/core/storage/purchase_result_storage.dart';
import 'package:kore_no_kae_dore/features/history/history_screen.dart';

class FakeStorage extends PurchaseResultStorage {
  final List<PurchaseResult> results;
  final Object? listError;

  FakeStorage(this.results, {this.listError});

  @override
  Future<List<PurchaseResult>> listResults() async {
    if (listError != null) throw listError!;
    return results;
  }

  @override
  Future<PurchaseResult?> loadResult(String id) async {
    try {
      return results.firstWhere((result) => result.id == id);
    } catch (_) {
      return null;
    }
  }
}

PurchaseResult _makeResult({required String id, String title = 'テスト商品'}) {
  return PurchaseResult(
    id: id,
    sessionId: 's-$id',
    candidateTitle: title,
    confidenceLabel: '候補',
    searchKeywords: ['キーワード1', 'キーワード2'],
    checkBeforeBuy: ['確認ポイント1'],
    shopStaffSummary: 'これはテスト用の商品です。',
    createdAt: DateTime(2026, 7, 10, 12, 0),
    matchLevel: MatchLevel.compatibleSpec,
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(home: child);
}

void main() {
  group('HistoryScreen', () {
    testWidgets('履歴が空 →「履歴がありません」を表示', (tester) async {
      final storage = FakeStorage([]);
      await tester.pumpWidget(_wrap(HistoryScreen(storage: storage)));
      await tester.pump();
      await tester.pump();

      expect(find.text('履歴がありません'), findsOneWidget);
    });

    testWidgets('結果が1件 → タイトル・日時・信頼度・検索ワード・確認ポイント・要約が表示される', (tester) async {
      final storage = FakeStorage([
        _makeResult(id: 'r1', title: 'E26 LED電球 60形相当'),
      ]);
      await tester.pumpWidget(_wrap(HistoryScreen(storage: storage)));
      await tester.pump();
      await tester.pump();

      expect(find.text('E26 LED電球 60形相当'), findsOneWidget);
      expect(find.text('2026/07/10 12:00'), findsOneWidget);
      expect(find.text('候補'), findsOneWidget);

      await tester.tap(find.text('E26 LED電球 60形相当'));
      await tester.pump();

      expect(find.text('キーワード1'), findsOneWidget);
      expect(find.text('キーワード2'), findsOneWidget);
      expect(find.text('確認ポイント1'), findsOneWidget);
      expect(find.text('これはテスト用の商品です。'), findsAtLeast(1));
    });

    testWidgets('結果が複数件 → ExpansionTile が2つ表示される', (tester) async {
      final storage = FakeStorage([
        _makeResult(id: 'r2', title: '商品B'),
        _makeResult(id: 'r1', title: '商品A'),
      ]);
      await tester.pumpWidget(_wrap(HistoryScreen(storage: storage)));
      await tester.pump();
      await tester.pump();

      final tiles = find.byType(ExpansionTile);
      expect(tiles, findsNWidgets(2));
    });

    testWidgets('一部の保存ファイルが壊れている場合は警告し、読めた履歴を表示する', (tester) async {
      final partial = _makeResult(id: 'r1', title: '保存済み商品');
      final storage = FakeStorage(
        [],
        listError: PurchaseResultStorageReadException(
          fileName: 'broken.json',
          cause: const FormatException('invalid JSON'),
          partialResults: [partial],
        ),
      );

      await tester.pumpWidget(_wrap(HistoryScreen(storage: storage)));
      await tester.pumpAndSettle();

      expect(find.textContaining('broken.json'), findsOneWidget);
      expect(find.text('保存済み商品'), findsOneWidget);
      expect(find.text('履歴がありません'), findsNothing);
    });
  });
}
