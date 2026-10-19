import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../controllers/alarm_controller.dart';
import '../models/alarm_event.dart';
import '../widgets/formatters.dart';
import '../widgets/journal_widgets.dart';

/// Filtres proposés au-dessus du journal.
enum JournalFilter {
  all('Tout', null),
  intrusions('Intrusions', {AlarmEventKind.triggered}),
  motions('Mouvements', {AlarmEventKind.motion}),
  arming('Activations', {AlarmEventKind.armed, AlarmEventKind.disarmed});

  const JournalFilter(this.label, this.kinds);

  final String label;

  /// Types retenus, `null` pour tout afficher.
  final Set<AlarmEventKind>? kinds;

  bool accepts(AlarmEvent event) => kinds?.contains(event.kind) ?? true;
}

/// Journal d'activité complet, conservé sur l'appareil, regroupé par jour.
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key, required this.controller});

  final AlarmController controller;

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  JournalFilter _filter = JournalFilter.all;

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Effacer le journal ?'),
        content: const Text('Toutes les entrées enregistrées sur cet appareil seront supprimées.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.alert,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) widget.controller.clearJournal();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final journal = widget.controller.journal;
        final events = journal.where(_filter.accepts).toList();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Journal d\'activité'),
            backgroundColor: AppColors.background,
            actions: [
              if (journal.isNotEmpty)
                IconButton(
                  tooltip: 'Effacer le journal',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: _confirmClear,
                ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final filter in JournalFilter.values)
                              ChoiceChip(
                                label: Text(filter.label),
                                selected: filter == _filter,
                                onSelected: (_) => setState(() => _filter = filter),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (events.isEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverToBoxAdapter(
                          child: JournalEmptyState(
                            message: journal.isEmpty
                                ? 'Aucune activité enregistrée pour l\'instant.'
                                : 'Aucune entrée pour ce filtre.',
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        sliver: SliverList.list(children: _groupedByDay(context, events)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _groupedByDay(BuildContext context, List<AlarmEvent> events) {
    final textTheme = Theme.of(context).textTheme;
    final widgets = <Widget>[];
    DateTime? currentDay;
    for (final event in events) {
      if (currentDay == null || !isSameDay(currentDay, event.at)) {
        currentDay = event.at;
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(formatDay(event.at),
              style: textTheme.titleSmall?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              )),
        ));
      }
      widgets.add(JournalEventTile(event: event, showDate: false));
    }
    return widgets;
  }
}
