import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/section_header.dart';
import '../data/phone_processing_settings.dart';

/// Settings card: the "Process on phone" switch and the Gemini key.
class PhoneProcessingCard extends StatefulWidget {
  const PhoneProcessingCard({super.key, this.settings});

  final PhoneProcessingSettings? settings;

  @override
  State<PhoneProcessingCard> createState() => _PhoneProcessingCardState();
}

class _PhoneProcessingCardState extends State<PhoneProcessingCard> {
  late final PhoneProcessingSettings _settings =
      widget.settings ?? PhoneProcessingSettings();

  bool _loaded = false;
  bool _enabled = false;
  String? _key;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var enabled = false;
    String? key;
    try {
      enabled = await _settings.isEnabled();
      key = await _settings.geminiKey();
    } catch (_) {
      // Storage unavailable: show the safe default (off, no key).
    }
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _key = key;
      _loaded = true;
    });
  }

  Future<void> _toggle(bool value) async {
    if (value && _key == null) {
      final saved = await _editKey();
      if (!saved) return;
    }
    await _settings.setEnabled(value);
    if (mounted) setState(() => _enabled = value);
  }

  /// Returns true when a key was saved.
  Future<bool> _editKey() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gemini API key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Used to write the AI summary on this phone. It is stored '
              'encrypted on this phone only and sent only to Google Gemini.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'API key',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return false;
    await _settings.saveGeminiKey(result);
    if (mounted) setState(() => _key = result);
    return true;
  }

  Future<void> _removeKey() async {
    await _settings.clearGeminiKey();
    await _settings.setEnabled(false);
    if (mounted) {
      setState(() {
        _key = null;
        _enabled = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = _key;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Processing', icon: Icons.memory_rounded),
          const Divider(height: 20),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(Icons.smartphone_rounded, color: context.accent),
            title: const Text('Process on phone'),
            subtitle: const Text(
              'Read text, summarise and create audio on this phone '
              'for captures taken from the app. Testing — off by default.',
            ),
            value: _enabled,
            onChanged: _loaded ? _toggle : null,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.key_rounded, size: 22, color: context.accent),
            title: const Text('Gemini API key'),
            subtitle: Text(
              key == null
                  ? 'Not set'
                  : 'Saved ${PhoneProcessingSettings.mask(key)}',
            ),
            trailing: key == null
                ? Icon(Icons.chevron_right_rounded, color: context.mutedText)
                : IconButton(
                    tooltip: 'Remove key',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: _removeKey,
                  ),
            onTap: _loaded ? _editKey : null,
          ),
        ],
      ),
    );
  }
}
