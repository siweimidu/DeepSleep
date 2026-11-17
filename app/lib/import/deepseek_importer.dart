// Turning a DeepSeek App export into host sessions.
//
// One conversation becomes one real session on the connected host: the app's
// own list, its own title, its own place in the drawer — the thing that makes
// "导入后接着聊" true rather than a viewer. What happened on the phone is kept
// beside it (deepseek_import/) and carried into the model on the first message
// from here (ImportedChatsController.takePreamble).

import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/connection_state.dart';
import '../state/sessions_state.dart';
import 'deepseek_export.dart';
import 'imported_chats.dart';

/// What an import did.
class DeepSeekImportOutcome {
  const DeepSeekImportOutcome({
    required this.imported,
    required this.failed,
    required this.messages,
    required this.problems,
    required this.cancelled,
  });

  final int imported;
  final int failed;
  final int messages;
  final List<String> problems;
  final bool cancelled;

  bool get isEmpty => imported == 0;
}

/// Parses [zipPath] off the UI isolate.
Future<DeepSeekExport> readDeepSeekExport(String zipPath) =>
    Isolate.run(() => DeepSeekExport.readFromPath(zipPath));

/// Creates one session per conversation in [export].
///
/// [onProgress] is called after each conversation with how many are done and
/// how many there are in total; [isCancelled] is asked before each one so the
/// page can stop a five-hundred-session import.
Future<DeepSeekImportOutcome> runDeepSeekImport({
  required WidgetRef ref,
  required DeepSeekExport export,
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  if (ref.read(activeConnectionProvider).value == null) {
    throw StateError('not connected');
  }
  final sessions = ref.read(sessionsProvider.notifier);
  final imported = ref.read(importedChatsProvider.notifier);
  final conversations = export.conversations;
  final problems = <String>[];
  var created = 0;
  var messages = 0;
  var cancelled = false;

  for (var index = 0; index < conversations.length; index++) {
    if (isCancelled?.call() ?? false) {
      cancelled = true;
      break;
    }
    final chat = conversations[index];
    try {
      final sessionId = await sessions.create();
      await sessions.rename(sessionId, chat.sessionTitle);
      await imported.record(
        sessionId: sessionId,
        title: chat.sessionTitle,
        messages: chat.messages,
        account: export.account,
      );
      created++;
      messages += chat.messages.length;
    } on Object catch (error) {
      problems.add('${chat.sessionTitle}: $error');
    }
    onProgress?.call(index + 1, conversations.length);
  }

  return DeepSeekImportOutcome(
    imported: created,
    failed: problems.length,
    messages: messages,
    problems: problems,
    cancelled: cancelled,
  );
}
