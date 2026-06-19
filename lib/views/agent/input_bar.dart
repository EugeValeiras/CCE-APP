import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../services/chat_service.dart';
import '../../theme/cce_tokens.dart';
import '../../theme/components/cce_neo_button.dart';

/// Input row neumórfico: adjuntar/cámara, chips de imagen removibles, un campo
/// de texto hundido (well neoInset), un mic de dictado on-device
/// (speech_to_text) y un botón send/stop que se vuelve stop mientras el agente
/// streamea. Solo cambia la presentación: SSE, voz, imágenes intactos.
class InputBar extends StatefulWidget {
  final ChatService service;

  /// `true` en la TABLET: el composer se presenta como UNA tarjeta neumórfica
  /// ELEVADA, cohesiva (adjuntar + texto + mic + enviar adentro), flotando con
  /// margen — sin la banda-footer full-width ni el botón enviar suelto al lado.
  /// El teléfono ([ChatScreen]) lo deja en `false`: footer band + well hundido.
  final bool embedded;

  const InputBar({super.key, required this.service, this.embedded = false});

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
      backgroundColor: CceColors.neoBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(CceRadii.sheet)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: CceColors.accent),
              title: const Text('Galería',
                  style: TextStyle(color: CceColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _pick(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: CceColors.accent),
              title: const Text('Cámara',
                  style: TextStyle(color: CceColors.textPrimary)),
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

    // Piezas compartidas entre teléfono (well hundido) y tablet (card elevada).
    final attachBtn = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: CceNeoIconButton(
        icon: Icons.add_photo_alternate_outlined,
        tooltip: 'Adjuntar',
        size: 40,
        onPressed: streaming ? null : _showAttachSheet,
      ),
    );
    final textField = Expanded(
      child: TextField(
        controller: _controller,
        minLines: 1,
        maxLines: 5,
        textInputAction: TextInputAction.newline,
        keyboardType: TextInputType.multiline,
        style: const TextStyle(color: CceColors.textPrimary),
        cursorColor: CceColors.accent,
        decoration: const InputDecoration(
          hintText: 'Mensaje',
          hintStyle: TextStyle(color: CceColors.textTertiary),
          border: InputBorder.none,
          // Padding generoso: despega texto/cursor del relieve de los bordes.
          contentPadding: EdgeInsets.fromLTRB(10, 12, 10, 12),
        ),
      ),
    );
    final micBtn = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _NeoMicButton(
        listening: _listening,
        tooltip: _listening ? 'Detener' : 'Dictar',
        size: 40,
        onPressed: streaming ? null : _toggleListen,
      ),
    );
    final sendBtn = _SendButton(
      streaming: streaming,
      enabled: streaming || hasContent,
      onSend: _send,
      onStop: _service.abort,
    );

    // Área del campo: card ELEVADA cohesiva (tablet) vs well hundido + enviar
    // suelto (teléfono).
    final Widget fieldArea = widget.embedded
        ? Container(
            // FLUSH: mismo fondo que la página (transparente) + solo un hairline
            // de contorno. El input no contrasta como loza elevada; adjuntar +
            // texto + mic + enviar flotan directo sobre la superficie, integrando
            // con el resto de la UI en vez de romperla.
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: CceColors.stroke),
            ),
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                attachBtn,
                textField,
                micBtn,
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: sendBtn,
                ),
              ],
            ),
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                // Pill del campo = WELL HUNDIDO: color OPACO neoSunken
                // (requisito de BlurStyle.inner) + neoInset.
                child: Container(
                  decoration: BoxDecoration(
                    color: CceColors.neoSunken,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: CceShadows.neoInset(blur: 8, offset: 3),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [attachBtn, textField, micBtn],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              sendBtn,
            ],
          );

    final content = Column(
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
                for (final img in _images)
                  _ImageChip(file: img, onRemove: () => _removeImage(img)),
              ],
            ),
          ),
        fieldArea,
        if (_listening)
          const Padding(
            padding: EdgeInsets.only(top: 4, left: 12),
            child: Text(
              'Escuchando…',
              style: TextStyle(color: CceColors.danger, fontSize: 12),
            ),
          ),
      ],
    );

    // Tablet: card flotante con margen, sin banda ni hairline.
    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: content,
      );
    }

    // Teléfono: footer neo full-width (fondo neoBase + hairline superior).
    return Container(
      decoration: const BoxDecoration(
        color: CceColors.neoBase,
        border: Border(top: BorderSide(color: CceColors.cardBevel)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: content,
        ),
      ),
    );
  }
}

/// Mic neumórfico press-to-inset, gemelo de [CceNeoIconButton] pero con color
/// de icono parametrizable: en estado `listening` el glifo va en danger (rojo),
/// algo que CceNeoIconButton no expone para IconData. Helper PRIVADO de este
/// archivo (no archivo compartido).
class _NeoMicButton extends StatefulWidget {
  const _NeoMicButton({
    required this.listening,
    required this.onPressed,
    this.tooltip,
    this.size = 40,
  });

  final bool listening;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  @override
  State<_NeoMicButton> createState() => _NeoMicButtonState();
}

class _NeoMicButtonState extends State<_NeoMicButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final List<BoxShadow> shadow = !enabled
        ? const []
        : (_pressed
            ? CceShadows.neoInset(blur: 6, offset: 2)
            : CceShadows.neo(blur: 8, offset: 3));

    final Color iconColor = !enabled
        ? CceColors.neoTextSub
        : widget.listening
            ? CceColors.danger
            : CceColors.neoText;

    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _setPressed(true) : null,
      onTapUp: enabled ? (_) => _setPressed(false) : null,
      onTapCancel: enabled ? () => _setPressed(false) : null,
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              widget.onPressed!();
            }
          : null,
      child: Container(
        width: widget.size,
        height: widget.size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: CceColors.neoBase, // opaco: requisito de BlurStyle.inner
          boxShadow: shadow,
        ),
        child: Icon(
          widget.listening ? Icons.mic : Icons.mic_none,
          size: widget.size * 0.5,
          color: iconColor,
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
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
        // Thumb sobre fondo neoSunken (well hundido) con clip propio.
        Container(
          decoration: BoxDecoration(
            color: CceColors.neoSunken,
            borderRadius: BorderRadius.circular(CceRadii.control),
          ),
          clipBehavior: Clip.antiAlias,
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
                color: CceColors.neoDark,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(2),
              // Badge blanco minusculo sobre circulo oscuro -> sin emboss.
              child: const Icon(Icons.close,
                  size: 14, color: CceColors.textPrimary, shadows: []),
            ),
          ),
        ),
      ],
    );
  }
}

/// Botón send/stop neumórfico custom (NO CceNeoIconButton: éste no modela los
/// 3 estados de color streaming=danger / enabled=accent / disabled). Fill plano
/// + CceShadows.neo (raised) que se hunde a neoInset al presionar. El glifo
/// blanco va sin emboss (shadows:[]) sobre el fill saturado.
class _SendButton extends StatefulWidget {
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
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final bool active = widget.streaming || widget.enabled;
    final Color color = widget.streaming
        ? CceColors.danger
        : widget.enabled
            ? CceColors.accent
            : CceColors.neoSunken;

    // Reposo activo = neo() raised; presionado = neoInset; inactivo = plano.
    final List<BoxShadow> shadow = !active
        ? const []
        : (_pressed
            ? CceShadows.neoInset(blur: 6, offset: 2)
            : CceShadows.neo(blur: 8, offset: 3));

    final VoidCallback? onTap = widget.streaming
        ? widget.onStop
        : widget.enabled
            ? widget.onSend
            : null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: onTap != null ? (_) => _setPressed(true) : null,
      onTapUp: onTap != null ? (_) => _setPressed(false) : null,
      onTapCancel: onTap != null ? () => _setPressed(false) : null,
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap();
            },
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color, // fill plano saturado (NO cardSurface sobre fills ON)
          boxShadow: shadow,
        ),
        child: Icon(
          widget.streaming ? Icons.stop : Icons.arrow_upward,
          color: active ? CceColors.textPrimary : CceColors.textTertiary,
          size: 22,
          // Glyph blanco sobre fill accent/danger: el relieve sobra -> sin emboss.
          shadows: const [],
        ),
      ),
    );
  }
}
