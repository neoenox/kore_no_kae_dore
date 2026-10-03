import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kore_no_kae_dore/core/models/capture_session.dart';
import 'package:kore_no_kae_dore/core/models/evidence_state.dart';
import 'package:kore_no_kae_dore/core/storage/session_storage.dart';

CaptureSession session(String status) {
  final now = DateTime.utc(2026, 10, 3, 3);
  return CaptureSession(
    id: 'session-1',
    category: 'bulb',
    status: status,
    currentStep: StepName.fullView,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late Directory documents;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('session-storage-test-');
  });

  tearDown(() async {
    if (await documents.exists()) {
      await documents.delete(recursive: true);
    }
  });

  SessionStorage storage({BeforeAtomicCommit? beforeCommit}) {
    return SessionStorage(
      documentsDirectoryProvider: () async => documents,
      beforeAtomicCommit: beforeCommit,
    );
  }

  test('normal session and evidence survive a new storage instance', () async {
    final writer = storage();
    await writer.saveSession(session('in_progress'));
    await writer.saveEvidence(
      EvidenceState(
        sessionId: 'session-1',
        fullViewCaptured: true,
      ),
    );

    final reader = storage();
    expect((await reader.loadSession('session-1'))?.status, 'in_progress');
    expect(
      (await reader.loadEvidence('session-1'))?.fullViewCaptured,
      isTrue,
    );
  });

  test('failed commit leaves the previous session intact', () async {
    await storage().saveSession(session('in_progress'));

    final failing = storage(
      beforeCommit: (temp, target) async {
        throw StateError('injected commit failure');
      },
    );

    await expectLater(
      failing.saveSession(session('completed')),
      throwsA(isA<StateError>()),
    );

    expect((await storage().loadSession('session-1'))?.status, 'in_progress');
    final sessionDir = Directory('${documents.path}/sessions');
    final tempFiles = await sessionDir
        .list()
        .where((entry) => entry.path.contains('.tmp.'))
        .toList();
    expect(tempFiles, isEmpty);
  });

  test('corrupt session JSON is quarantined instead of reused', () async {
    final sessionDir = Directory('${documents.path}/sessions');
    await sessionDir.create(recursive: true);
    final broken = File('${sessionDir.path}/broken.json');
    await broken.writeAsString('{"id":');

    expect(await storage().loadSession('broken'), isNull);
    expect(await broken.exists(), isFalse);

    final quarantined = await sessionDir
        .list()
        .where((entry) => entry.path.contains('broken.json.corrupt.'))
        .toList();
    expect(quarantined, hasLength(1));
  });

  test('listSessions quarantines malformed session files', () async {
    final writer = storage();
    await writer.saveSession(session('in_progress'));
    final sessionDir = Directory('${documents.path}/sessions');
    await File('${sessionDir.path}/bad.json').writeAsString('[]');

    final sessions = await storage().listSessions();

    expect(sessions.map((entry) => entry.id), ['session-1']);
    expect(await File('${sessionDir.path}/bad.json').exists(), isFalse);
  });
}
