// The imported DeepSeek conversation whose session this is, at the top of an
// otherwise empty chat.
//
// A session created from an export has no turn of its own yet, so the chat opens
// empty even though the person has a whole conversation with DeepSeek behind it.
// This card is the way back to it (and to the history the first message carries
// to the model).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../import/imported_chats.dart';
import '../../l10n/l10n.dart';
import '../settings/imported_transcript_page.dart';
import '../theme/app_icons.dart';

class ImportedHistoryCard extends ConsumerWidget {
  const ImportedHistoryCard({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imported = ref.watch(importedChatsProvider).value;
    if (imported == null) return const SizedBox.shrink();
    ImportedChat? chat;
    for (final entry in imported) {
      if (entry.sessionId == sessionId) {
        chat = entry;
        break;
      }
    }
    if (chat == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => openImportedTranscript(context, chat!),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(AppIcons.history, size: 18, color: colors.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.hubDeepSeekRecordTitle, style: theme.textTheme.bodyMedium),
                      Text(
                        '${chat.messageCount} ${l10n.hubDeepSeekImportMessages}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(l10n.hubDeepSeekRecordOpen, style: theme.textTheme.labelMedium?.copyWith(color: colors.primary)),
                Icon(AppIcons.disclosure, size: 16, color: colors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
