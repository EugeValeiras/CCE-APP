import 'package:flutter/material.dart';
import '../models/server_config.dart';
import '../services/api_service.dart';
import '../theme/cce_tokens.dart';

class SettingsView extends StatefulWidget {
  final ServerConfig config;
  final VoidCallback onSaved;

  const SettingsView({
    super.key,
    required this.config,
    required this.onSaved,
  });

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  bool _testing = false;
  bool? _testResult;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: widget.config.host);
    _portController =
        TextEditingController(text: widget.config.port.toString());
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });

    final testConfig = ServerConfig(
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text) ?? 3000,
    );
    final api = ApiService(testConfig);
    final ok = await api.testConnection();

    setState(() {
      _testing = false;
      _testResult = ok;
    });
  }

  Future<void> _save() async {
    widget.config.host = _hostController.text.trim();
    widget.config.port = int.tryParse(_portController.text) ?? 3000;
    await widget.config.save();
    widget.onSaved();
    if (mounted) Navigator.of(context).pop();
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: CceColors.textTertiary),
      hintStyle: const TextStyle(color: Color(0x3DFFFFFF)),
      filled: true,
      fillColor: CceColors.surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CceRadii.control),
        borderSide: BorderSide.none,
      ),
      prefixIcon: Icon(icon, color: CceColors.textTertiary),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CceColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Configuracion'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('SERVIDOR CCE', style: CceText.section),
                const SizedBox(height: 12),
                TextField(
                  controller: _hostController,
                  style: const TextStyle(color: CceColors.textPrimary),
                  decoration: _inputDecoration(
                    label: 'IP del servidor',
                    hint: '100.79.196.98',
                    icon: Icons.dns_outlined,
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _portController,
                  style: const TextStyle(color: CceColors.textPrimary),
                  decoration: _inputDecoration(
                    label: 'Puerto',
                    hint: '3000',
                    icon: Icons.numbers,
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _testing ? null : _testConnection,
                        icon: _testing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: CceColors.textTertiary,
                                ),
                              )
                            : Icon(
                                _testResult == null
                                    ? Icons.wifi_find
                                    : _testResult!
                                        ? Icons.check_circle
                                        : Icons.error,
                                color: _testResult == null
                                    ? CceColors.textTertiary
                                    : _testResult!
                                        ? CceColors.ok
                                        : CceColors.danger,
                              ),
                        label: Text(
                          _testResult == null
                              ? 'Test conexion'
                              : _testResult!
                                  ? 'Conectado!'
                                  : 'Sin conexion',
                          style: TextStyle(
                            color: _testResult == null
                                ? CceColors.textTertiary
                                : _testResult!
                                    ? CceColors.ok
                                    : CceColors.danger,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: _testResult == null
                                ? CceColors.stroke
                                : _testResult!
                                    ? CceColors.ok
                                    : CceColors.danger,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(CceRadii.control),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CceColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(CceRadii.control),
                    ),
                  ),
                  child: const Text(
                    'Guardar',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
