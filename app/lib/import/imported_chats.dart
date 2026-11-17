// The conversations imported from a DeepSeek App export, kept beside the host
// session each of them became.
//
// A host session holds the turns that happen here; what the person said on the
// phone before is ours to keep. One JSON file per session under
// `<app support>/deepseek_import/`, plus `index.json` so the drawer, the import
// page and the composer can answer "is this one of them?" without opening the
// transcript.
//
// The transcript is what the first message in the imported session carries to
// the model (`takePreamble`), and what 查看记录 shows; once that preamble has
// gone out, `seeded` records it so a later message does not repeat it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'deepseek_export.dart';

/// One imported conversation.
class ImportedChat {
  const ImportedChat({
    required this.sessionId,
    required this.title,
    required this.messageCount,
    required this.importedAt,
    this.seeded = false,
    this.account,
  });

  final String sessionId;
  final String title;
  final int messageCount;
  final DateTime importedAt;

  /// The history has already been handed to the model once.
  final bool seeded;

  /// The masked DeepSeek account the export came from, when it said so.
  final String? account;

  ImportedChat copyWith({bool? seeded, String? title, int? messageCount}) => ImportedChat(
    sessionId: sessionId,
    title: title ?? this.title,
    messageCount: messageCount ?? this.messageCount,
    importedAt: importedAt,
    seeded: seeded ?? this.seeded,
    account: account,
  );

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'title': title,
    'messageCount': messageCount,
    'importedAt': importedAt.toIso8601String(),
    'seeded': seeded,
    'account': account,
  };

  static ImportedChat? fromJson(Object? json) {
    if (json is! Map) return null;
    final sessionId = json['sessionId'];
    if (sessionId is! String || sessionId.isEmpty) return null;
    return ImportedChat(
      sessionId: sessionId,
      title: json['title'] is String ? json['title'] as String : '',
      messageCount: json['messageCount'] is int ? json['messageCount'] as int : 0,
      importedAt: DateTime.tryParse(json['importedAt'] is String ? json['importedAt'] as String : '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      seeded: json['seeded'] == true,
      account: json['account'] is String ? json['account'] as String : null,
    );
  }
}

/// Where the imported transcripts live.
final importedChatsDirProvider = FutureProvider<Directory>((ref) async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory('${support.path}/deepseek_import');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
});

final importedChatsProvider = AsyncNotifierProvider<ImportedChatsController, List<ImportedChat>>(
  ImportedChatsController.new,
);

class ImportedChatsController extends AsyncNotifier<List<ImportedChat>> {
  @override
  Future<List<ImportedChat>> build() async {
    final index = await _readIndex();
    final known = <ImportedChat>[];
    for (final entry in index) {
      if (await File('${(await _dir()).path}/${entry.sessionId}.json').exists()) known.add(entry);
    }
    known.sort((a, b) => b.importedAt.compareTo(a.importedAt));
    return known;
  }

  Future<Directory> _dir() => ref.read(importedChatsDirProvider.future);

  Future<List<ImportedChat>> _readIndex() async {
    final file = File('${(await _dir()).path}/index.json');
    if (!await file.exists()) return const [];
    try {
      final json = jsonDecode(await file.readAsString());
      final chats = json is Map ? json['chats'] : null;
      if (chats is! List) return const [];
      return [for (final item in chats) ?ImportedChat.fromJson(item)];
    } on Object {
      return const [];
    }
  }

  Future<void> _writeIndex(List<ImportedChat> chats) async {
    final dir = await _dir();
    final file = File('${dir.path}/index.json');
    await file.writeAsString(jsonEncode({
      'version': 1,
      'chats': [for (final chat in chats) chat.toJson()],
    }), flush: true);
  }

  /// Keeps [messages] for [sessionId] and adds it to the index.
  Future<void> record({
    required String sessionId,
    required String title,
    required List<DeepSeekMessage> messages,
    String? account,
  }) async {
    final dir = await _dir();
    await File('${dir.path}/$sessionId.json').writeAsString(jsonEncode({
      'version': 1,
      'title': title,
      'messages': [for (final message in messages) _messageToJson(message)],
    }), flush: true);
    final entry = ImportedChat(
      sessionId: sessionId,
      title: title,
      messageCount: messages.length,
      importedAt: DateTime.now(),
      account: account,
    );
    final next = [...?state.value, entry]..sort((a, b) => b.importedAt.compareTo(a.importedAt));
    state = AsyncValue.data(next);
    await _writeIndex(next);
  }

  Future<List<DeepSeekMessage>?> transcript(String sessionId) async {
    final file = File('${(await _dir()).path}/$sessionId.json');
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      final raw = json is Map ? json['messages'] : null;
      if (raw is! List) return null;
      return [for (final item in raw) ?_messageFromJson(item)];
    } on Object {
      return null;
    }
  }

  /// The history to carry into the model, once per session. Null when this
  /// session was not imported, or when it has been carried already.
  Future<String?> takePreamble(String sessionId, {int maxChars = 6000}) async {
    final chats = state.value ?? await future;
    final index = chats.indexWhere((chat) => chat.sessionId == sessionId);
    if (index < 0 || chats[index].seeded) return null;
    final messages = await transcript(sessionId);
    if (messages == null || messages.isEmpty) return null;
    final preamble = DeepSeekChat(
      id: sessionId,
      title: chats[index].title,
      messages: messages,
    ).contextPreamble(maxChars: maxChars);
    if (preamble.isEmpty) return null;
    final next = [...chats];
    next[index] = chats[index].copyWith(seeded: true);
    state = AsyncValue.data(next);
    await _writeIndex(next);
    return preamble;
  }

  Future<ImportedChat?> entryFor(String sessionId) async {
    final chats = state.value ?? await future;
    for (final chat in chats) {
      if (chat.sessionId == sessionId) return chat;
    }
    return null;
  }

  Future<void> forget(String sessionId) async {
    final chats = state.value ?? await future;
    final next = chats.where((chat) => chat.sessionId != sessionId).toList();
    state = AsyncValue.data(next);
    await _writeIndex(next);
    final file = File('${(await _dir()).path}/$sessionId.json');
    if (await file.exists()) await file.delete();
  }

  static Map<String, Object?> _messageToJson(DeepSeekMessage message) => {
    'role': message.role.name,
    'text': message.text,
    if (message.thinking.isNotEmpty) 'thinking': message.thinking,
    if (message.at != null) 'at': message.at!.toIso8601String(),
    if (message.stopped) 'stopped': true,
    if (message.searchQueries.isNotEmpty) 'queries': message.searchQueries,
    if (message.sources.isNotEmpty)
      'sources': [
        for (final source in message.sources) {'title': source.title, 'url': source.url, 'site': source.site},
      ],
    if (message.attachments.isNotEmpty)
      'attachments': [
        for (final file in message.attachments) {'name': file.name, 'bytes': file.bytes, 'isImage': file.isImage},
      ],
  };

  static DeepSeekMessage? _messageFromJson(Object? json) {
    if (json is! Map) return null;
    final role = json['role'] == 'assistant' ? DeepSeekRole.assistant : DeepSeekRole.user;
    final sources = json['sources'];
    final attachments = json['attachments'];
    final queries = json['queries'];
    return DeepSeekMessage(
      role: role,
      text: json['text'] is String ? json['text'] as String : '',
      thinking: json['thinking'] is String ? json['thinking'] as String : '',
      at: DateTime.tryParse(json['at'] is String ? json['at'] as String : ''),
      stopped: json['stopped'] == true,
      searchQueries: [if (queries is List) for (final query in queries) if (query is String) query],
      sources: [
        if (sources is List)
          for (final source in sources)
            if (source is Map)
              DeepSeekSource(
                title: source['title'] is String ? source['title'] as String : '',
                url: source['url'] is String ? source['url'] as String : '',
                site: source['site'] is String ? source['site'] as String : '',
              ),
      ],
      attachments: [
        if (attachments is List)
          for (final file in attachments)
            if (file is Map)
              DeepSeekAttachment(
                name: file['name'] is String ? file['name'] as String : '',
                bytes: file['bytes'] is int ? file['bytes'] as int : 0,
                isImage: file['isImage'] == true,
              ),
      ],
    );
  }
}
