import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../services/chat_service.dart';
import '../../theme/cce_tokens.dart';

/// WhatsApp-style input row: attach/camera, removable image chips, a rounded
/// text field, an on-device dictation mic (speech_to_text), and a send/stop
/// button that becomes a stop button while the agent streams.
class InputBar extends StatefulWidget {
  final ChatService service;
  const InputBar({super.key, required this.service});

  @override
  State<InputBar> createState() => InputBarState();
}

class InputBarState extends State<InputBar> {
  final _controller = TextEditingController();
  final _picker = ImagePicker();
  final _speech = SpeechToText();

  final List<XFile> _images = [];
  bool _listening = false;
  bool _speechReady = false;
  String _baseTextBeforeListen = '';

  ChatService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _speech.cancel();
    super.dispose();
  }

  /// Fill the text field externally (e.g. suggestion chips).
  void setText(String text) {
    _controller.text = text;
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    setState(() {});
  }

  // ── Images ───────────────────────────────────────────────────────────────────
  Future<void> _showAttachSheet() async {
    FocusScope.of(context).unfocus();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: CceColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: CceColors.accent),
              title: const Text('Galería',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _pick(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: CceColors.accent),
              title: const Text('Cámara',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _pick(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2048,
      );
      if (file != null) {
        setState(() => _images.add(file));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo acceder a la imagen.')),
        );
      }
    }
  }

  void _removeImage(XFile file) {
    setState(() => _images.remove(file));
  }

  // ── Voice (on-device dictation) ──────────────────────────────────────────────
  Future<void> _toggleListen() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
    }
    if (!_speechReady) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El dictado por voz no está disponible.'),
          ),
        );
      }
      return;
    }
    _baseTextBeforeListen =
        _controller.text.isEmpty ? '' : '${_controller.text} ';
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        final combined = '$_baseTextBeforeListen${result.recognizedWords}';
        _controller.value = TextEditingValue(
          text: combined,
          selection: TextSelection.collapsed(offset: combined.length),
        );
        setState(() {});
      },
      listenOptions: SpeechListenOptions(partialResults: true),
    );
  }

  // ── Send ───────────────────────────────────────────────────────────────────────
  Future<void> _send() async {
    final text = _controller.text;
    final images = List<XFile>.from(_images);
    if (text.trim().isEmpty && images.isEmpty) return;
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
    }
    _controller.clear();
    setState(() => _images.clear());
    await _service.sendMessage(text, images: images);
  }

  @override
  Widget build(BuildContext context) {
    final streaming = _service.streaming;
    final hasContent =
        _controller.text.trim().isNotEmpty || _images.isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: CceColors.surface,
        border: Border(top: BorderSide(color: CceColors.stroke)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_images.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 4),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final img in _images) _ImageChip(file: img, onRemove: () => _removeImage(img)),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: CceColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: 'Adjuntar',
                            icon: const Icon(Icons.add_photo_alternate_outlined,
                                color: Colors.white60),
                            onPressed: streaming ? null : _showAttachSheet,
                          ),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              minLines: 1,
                              maxLines: 5,
                              textInputAction: TextInputAction.newline,
                              keyboardType: TextInputType.multiline,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Mensaje',
                                hintStyle: TextStyle(color: Colors.white38),
                                border: InputBorder.none,
                                contentPadding:
                                    EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: _listening ? 'Detener' : 'Dictar',
                            icon: Icon(
                              _listening ? Icons.mic : Icons.mic_none,
                              color: _listening
                                  ? CceColors.danger
                                  : Colors.white60,
                            ),
                            onPressed: streaming ? null : _toggleListen,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _SendButton(
                    streaming: streaming,
                    enabled: streaming || hasContent,
                    onSend: _send,
                    onStop: _service.abort,
                  ),
                ],
              ),
              if (_listening)
                const Padding(
                  padding: EdgeInsets.only(top: 4, left: 12),
                  child: Text(
                    'Escuchando…',
                    style: TextStyle(color: CceColors.danger, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageChip extends StatelessWidget {
  final XFile file;
  final VoidCallback onRemove;
  const _ImageChip({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(file.path),
            width: 64,
            height: 64,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black87,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(2),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool streaming;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onStop;
  const _SendButton({
    required this.streaming,
    required this.enabled,
    required this.onSend,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final color = streaming
        ? CceColors.danger
        : enabled
            ? CceColors.accent
            : CceColors.surfaceHigh;
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: streaming
            ? onStop
            : enabled
                ? onSend
                : null,
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Icon(
            streaming ? Icons.stop : Icons.arrow_upward,
            color: enabled || streaming ? Colors.white : Colors.white38,
            size: 22,
          ),
        ),
      ),
    );
  }
}
