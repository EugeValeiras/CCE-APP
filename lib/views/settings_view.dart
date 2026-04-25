import 'package:flutter/material.dart';
import '../models/server_config.dart';
import '../services/api_service.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: const Text('Configuracion'),
        backgroundColor: const Color(0xFF16213E),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            const Text(
              'Servidor CCE',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hostController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'IP del servidor',
                hintText: '192.168.0.100',
                labelStyle: const TextStyle(color: Colors.white54),
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF16213E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon:
                    const Icon(Icons.dns_outlined, color: Colors.white54),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Puerto',
                hintText: '3000',
                labelStyle: const TextStyle(color: Colors.white54),
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF16213E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.numbers, color: Colors.white54),
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
                              color: Colors.white54,
                            ),
                          )
                        : Icon(
                            _testResult == null
                                ? Icons.wifi_find
                                : _testResult!
                                    ? Icons.check_circle
                                    : Icons.error,
                            color: _testResult == null
                                ? Colors.white54
                                : _testResult!
                                    ? Colors.green
                                    : Colors.red,
                          ),
                    label: Text(
                      _testResult == null
                          ? 'Test conexion'
                          : _testResult!
                              ? 'Conectado!'
                              : 'Sin conexion',
                      style: TextStyle(
                        color: _testResult == null
                            ? Colors.white54
                            : _testResult!
                                ? Colors.green
                                : Colors.red,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: _testResult == null
                            ? Colors.white24
                            : _testResult!
                                ? Colors.green
                                : Colors.red,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
                backgroundColor: const Color(0xFF0F3460),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
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
