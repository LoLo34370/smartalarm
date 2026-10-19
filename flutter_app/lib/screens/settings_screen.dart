import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../config/mqtt_config.dart';
import '../controllers/settings_controller.dart';

/// Réglages : broker MQTT (sans recompiler) et données.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.journalLength,
    required this.onClearJournal,
  });

  final SettingsController settings;
  final int journalLength;
  final VoidCallback onClearJournal;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final MqttConfig _initial = widget.settings.brokerConfig;
  late final _host = TextEditingController(text: _initial.host);
  late final _username = TextEditingController(text: _initial.username);
  late final _password = TextEditingController(text: _initial.password);
  late final _topicBase = TextEditingController(text: _initial.topicBase);
  late final _wsPort = TextEditingController(text: '${_initial.webSocketPort}');
  late final _wsPath = TextEditingController(text: _initial.webSocketPath);
  late final _tlsPort = TextEditingController(text: '${_initial.tlsPort}');
  bool _showPassword = false;
  bool _saving = false;
  late int _journalLength = widget.journalLength;

  @override
  void dispose() {
    for (final c in [_host, _username, _password, _topicBase, _wsPort, _wsPath, _tlsPort]) {
      c.dispose();
    }
    super.dispose();
  }

  MqttConfig _formConfig() => MqttConfig(
        host: _host.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
        topicBase: _topicBase.text.trim(),
        webSocketPort: int.parse(_wsPort.text.trim()),
        webSocketPath: _wsPath.text.trim(),
        tlsPort: int.parse(_tlsPort.text.trim()),
      );

  Future<void> _run(Future<void> Function() action, String success) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(success)));
      if (mounted) Navigator.pop(context);
    } on Exception catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Enregistrement impossible : $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final config = _formConfig();
    if (config == widget.settings.brokerConfig) {
      Navigator.pop(context);
      return;
    }
    await _run(() => widget.settings.saveBrokerConfig(config),
        'Broker enregistré : reconnexion en cours…');
  }

  Future<void> _reset() => _run(widget.settings.resetBrokerConfig,
      'Configuration de compilation rétablie : reconnexion en cours…');

  void _clearJournal() {
    widget.onClearJournal();
    setState(() => _journalLength = 0);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Journal effacé.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages'), backgroundColor: AppColors.background),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListenableBuilder(
              listenable: widget.settings,
              builder: (context, _) => Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    _brokerSection(),
                    const SizedBox(height: 16),
                    _dataSection(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _brokerSection() {
    final settings = widget.settings;
    return _Section(
      title: 'Broker MQTT',
      subtitle: settings.usesAppBrokerConfig
          ? 'Configuration saisie dans l\'application (stockée de façon chiffrée sur l\'appareil).'
          : 'Configuration fournie à la compilation (--dart-define). '
              'Modifiez-la ici pour changer de broker sans recompiler.',
      children: [
        _field(_host, 'Hôte', hint: 'xxxxxxxx.s1.eu.hivemq.cloud', validator: _validateHost,
            keyboard: TextInputType.url),
        _field(_username, 'Utilisateur MQTT', validator: _required),
        _field(
          _password,
          'Mot de passe MQTT',
          validator: _required,
          obscure: !_showPassword,
          suffix: IconButton(
            tooltip: _showPassword ? 'Masquer' : 'Afficher',
            icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
        ),
        _field(_topicBase, 'Base des topics', hint: 'smartalarm/demo01', validator: _validateTopic),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Options avancées'),
            subtitle: Text(
              kIsWeb ? 'Web : MQTT sur WebSocket sécurisée' : 'Mobile : MQTT sur TLS',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            children: [
              _field(_tlsPort, 'Port TLS (iOS / Android)', validator: _validatePort,
                  keyboard: TextInputType.number),
              _field(_wsPort, 'Port WebSocket (web)', validator: _validatePort,
                  keyboard: TextInputType.number),
              _field(_wsPath, 'Chemin WebSocket', validator: _validatePath),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_rounded),
          label: const Text('Enregistrer et se reconnecter'),
        ),
        if (settings.usesAppBrokerConfig) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _saving ? null : _reset,
            child: const Text('Revenir à la configuration de compilation'),
          ),
        ],
      ],
    );
  }

  Widget _dataSection() => _Section(
        title: 'Données',
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history_rounded),
            title: const Text('Journal d\'activité'),
            subtitle: Text('$_journalLength entrée${_journalLength > 1 ? 's' : ''} '
                'enregistrée${_journalLength > 1 ? 's' : ''} sur cet appareil'),
            trailing: TextButton(
              onPressed: _journalLength == 0 ? null : _clearJournal,
              child: const Text('Effacer'),
            ),
          ),
        ],
      );

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    String? Function(String?)? validator,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboard,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: keyboard,
          validator: validator,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            suffixIcon: suffix,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );

  // ── Validation ─────────────────────────────────────────────────────────────

  static String? _required(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Champ obligatoire' : null;

  static String? _validateHost(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Champ obligatoire';
    if (v.contains('://') || v.contains(':') || v.contains('/')) {
      return 'Nom d\'hôte seul, sans « mqtts:// » ni port';
    }
    return null;
  }

  static String? _validatePort(String? value) {
    final port = int.tryParse(value?.trim() ?? '');
    return (port == null || port < 1 || port > 65535) ? 'Port entre 1 et 65535' : null;
  }

  static String? _validatePath(String? value) =>
      (value ?? '').trim().startsWith('/') ? null : 'Doit commencer par « / »';

  static String? _validateTopic(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Champ obligatoire';
    if (v.contains('#') || v.contains('+')) return 'Pas de joker MQTT (# ou +)';
    if (v.startsWith('/') || v.endsWith('/')) return 'Sans « / » au début ni à la fin';
    return null;
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, required this.children});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}
