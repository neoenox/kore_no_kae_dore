import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kore_no_kae_dore/core/models/match_level.dart';
import 'package:kore_no_kae_dore/core/models/purchase_result.dart';
import 'package:kore_no_kae_dore/core/storage/purchase_result_storage.dart';

PurchaseResult _makeResult(String id) {
  return PurchaseResult(
    id: id,
    sessionId: 'session-$id',
    candidateTitle: '商品 $id',
    confidenceLabel: '候補',
    searchKeywords: const ['検索語'],
    checkBeforeBuy: const ['確認項目'],
    shopStaffSummary: 'テスト用要約',
    createdAt: DateTime.utc(2026, 11, 18),
    matchLevel: MatchLevel.compatibleSpec,
  );
}

void main() {
  late Directory documents;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('purchase-result-test-');
  });

  tearDown(() async {
    if (await documents.exists()) {
      await documents.delete(recursive: true);
    }
  });

  PurchaseResultStorage storage() {
    return PurchaseResultStorage(
      documentsDirectoryProvider: () async => documents,
    );
  }

  test('saved results survive a new storage instance', () async {
    await storage().saveResult(_makeResult('saved'));

    final loaded = await storage().loadResult('saved');
    expect(loaded?.candidateTitle, '商品 saved');
    expect((await storage().listResults()).map((item) => item.id), ['saved']);
  });

  test('listResults reports corrupt files and preserves their bytes', () async {
    await storage().saveResult(_makeResult('a-valid'));
    final corrupt = File('${documents.path}/results/z-broken.json');
    const original = '{"id":';
    await corrupt.writeAsString(original);

    await expectLater(
      storage().listResults(),
      throwsA(
        isA<PurchaseResultStorageReadException>()
            .having((error) => error.fileName, 'fileName', 'z-broken.json')
            .having(
              (error) => error.partialResults.map((item) => item.id).toList(),
              'partialResults',
              ['a-valid'],
            ),
      ),
    );

    expect(await corrupt.readAsString(), original);
  });

  test('loadResult reports corrupt JSON without deleting the source file', () async {
    final resultsDir = Directory('${documents.path}/results');
    await resultsDir.create(recursive: true);
    final corrupt = File('${resultsDir.path}/broken.json');
    const original = '{not-json';
    await corrupt.writeAsString(original);

    await expectLater(
      storage().loadResult('broken'),
      throwsA(
        isA<PurchaseResultStorageReadException>()
            .having((error) => error.fileName, 'fileName', 'broken.json'),
      ),
    );

    expect(await corrupt.readAsString(), original);
  });

  test('directory provider failures propagate instead of looking like empty history', () async {
    final failing = PurchaseResultStorage(
      documentsDirectoryProvider: () async {
        throw StateError('documents directory unavailable');
      },
    );

    await expectLater(
      failing.listResults(),
      throwsA(isA<StateError>()),
    );
  });
}
