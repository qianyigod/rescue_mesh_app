import 'dart:async';
import 'dart:io';

import 'package:fcllama/fllama.dart';
import 'package:fcllama/fllama_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'services/offline_ai_guidance_service.dart';
import 'theme/rescue_theme.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final List<Map<String, String>> _messages = [];
  final List<RoleContent> _chatMessages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FCllama? _llama = FCllama.instance();
  final OfflineAiGuidanceService _guidanceService =
      const OfflineAiGuidanceService();

  StreamSubscription<Map<Object?, dynamic>>? _tokenSubscription;
  bool _isModelReady = false;
  bool _isInitializing = false;
  bool _isSending = false;
  String _modelPath = '';
  String? _initError;
  double? _contextId;
  StringBuffer? _responseBuffer;

  @override
  void initState() {
    super.initState();
    _bindTokenStream();
    unawaited(_initLlama(autoTriggered: true));
  }

  void _bindTokenStream() {
    _tokenSubscription = _llama?.onTokenStream?.listen((event) {
      if (!mounted) {
        return;
      }

      final function = event['function']?.toString();
      if (function == 'loadProgress') {
        final progress = event['result'];
        _upsertAssistantMessage('模型加载中... $progress%');
        return;
      }

      if (function != 'completion' || !_isSending || _contextId == null) {
        return;
      }

      final eventContextId = double.tryParse(
        event['contextId']?.toString() ?? '',
      );
      if (eventContextId != _contextId) {
        return;
      }

      final result = event['result'];
      if (result is! Map) {
        return;
      }

      final token = result['token']?.toString() ?? '';
      if (token.isEmpty) {
        return;
      }

      _responseBuffer ??= StringBuffer();
      _responseBuffer!.write(token);

      setState(() {
        if (_messages.isNotEmpty) {
          _messages.last['text'] = _responseBuffer.toString();
        }
      });
      _scrollToBottom();
    });
  }

  Future<void> _initLlama({bool autoTriggered = false}) async {
    if (_isInitializing || _isModelReady) {
      return;
    }

    setState(() {
      _isInitializing = true;
      _initError = null;
      if (!autoTriggered || _messages.isEmpty) {
        _messages.add({'role': 'ai', 'text': '正在自动准备离线模型，请稍候...'});
      }
    });

    try {
      _modelPath = await _prepareBundledModel();

      final result = await _llama?.initContext(
        _modelPath,
        nCtx: 1024,
        nBatch: 256,
        nThreads: 2,
        useMlock: false,
        useMmap: true,
        emitLoadProgress: true,
      );

      final rawContextId = result?['contextId'];
      final contextId = rawContextId is num
          ? rawContextId.toDouble()
          : double.tryParse(rawContextId?.toString() ?? '');

      if (contextId == null) {
        throw Exception('未能获取模型上下文。');
      }

      _contextId = contextId;
      if (!mounted) {
        return;
      }

      setState(() {
        _isModelReady = true;
        _isInitializing = false;
        _initError = null;
      });
      _upsertAssistantMessage(
        '离线 AI 已就绪。请直接描述症状、伤情或现场情况，尽量带上呼吸、意识、出血、疼痛部位和开始时间。',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isInitializing = false;
        _initError = '$error';
      });
      _upsertAssistantMessage('模型加载失败：$error');
    }
  }

  Future<String> _prepareBundledModel() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final modelFile = File(
      '${documentsDir.path}${Platform.pathSeparator}qwen.gguf',
    );

    if (!await modelFile.exists()) {
      final byteData = await rootBundle.load('assets/models/qwen.gguf');
      await modelFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    }

    return modelFile.path;
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || !_isModelReady || _contextId == null || _isSending) {
      return;
    }

    final guidance = _guidanceService.buildGuidance(
      latestMessage: text,
      previousUserMessages: _recentUserMessages(),
    );

    setState(() {
      _isSending = true;
      _messages.add({'role': 'user', 'text': text});
      _messages.add({'role': 'ai', 'text': '正在整理更详细的急救建议...'});
    });

    _textController.clear();
    _scrollToBottom();
    _chatMessages.add(RoleContent(role: 'user', content: text));
    _responseBuffer = StringBuffer();

    try {
      final prompt = _buildPrompt(guidance.systemPrompt);
      final result = await _llama?.completion(
        _contextId!,
        prompt: prompt,
        temperature: 0.7,
        topK: 40,
        topP: 0.9,
        penaltyRepeat: 1.1,
        nPredict: 256,
        emitRealtimeCompletion: true,
        stop: const ['<|im_end|>'],
      );

      final finalText =
          ((result?['text']?.toString() ?? _responseBuffer.toString())
                  .replaceAll('<|im_end|>', ''))
              .trim();
      final safeText = finalText.isEmpty
          ? guidance.fallbackReply
          : finalText;

      _chatMessages.add(RoleContent(role: 'assistant', content: safeText));

      if (!mounted) {
        return;
      }
      setState(() {
        _messages.last['text'] = safeText;
      });
      _scrollToBottom();
    } catch (error) {
      if (!mounted) {
        return;
      }
      final fallbackReply = guidance.fallbackReply;
      _chatMessages.add(RoleContent(role: 'assistant', content: fallbackReply));
      setState(() {
        _messages.last['text'] = fallbackReply;
      });
      _responseBuffer = null;
    } finally {
      _responseBuffer = null;
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  List<String> _recentUserMessages() {
    final userMessages = _chatMessages
        .where((message) => message.role == 'user')
        .map((message) => message.content)
        .toList(growable: false);

    if (userMessages.length <= 4) {
      return userMessages;
    }

    return userMessages.sublist(userMessages.length - 4);
  }

  String _buildPrompt(String systemPrompt) {
    final buffer = StringBuffer();
    _appendPromptMessage(buffer, 'system', systemPrompt);

    for (final message in _chatMessages) {
      _appendPromptMessage(buffer, message.role, message.content);
    }

    buffer.write('<|im_start|>assistant\n');
    return buffer.toString();
  }

  void _appendPromptMessage(
    StringBuffer buffer,
    String role,
    String content,
  ) {
    buffer
      ..write('<|im_start|>')
      ..write(role)
      ..write('\n')
      ..write(content.trim())
      ..write('\n<|im_end|>\n');
  }

  void _upsertAssistantMessage(String text) {
    if (!mounted) {
      return;
    }
    setState(() {
      if (_messages.isEmpty || _messages.last['role'] != 'ai') {
        _messages.add({'role': 'ai', 'text': text});
      } else {
        _messages.last['text'] = text;
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF6F9FB), Color(0xFFEAF1F5)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: RescuePalette.panel,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: RescuePalette.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: RescuePalette.accentSoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.psychology_alt_rounded,
                      color: RescuePalette.accent,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '离线 AI 急救助手',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isModelReady
                              ? '模型已自动加载，可直接开始对话'
                              : _isInitializing
                              ? '正在自动加载本地模型...'
                              : '等待模型准备',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: _isModelReady
                                    ? RescuePalette.success
                                    : RescuePalette.textMuted,
                              ),
                        ),
                        if (_modelPath.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '模型路径：$_modelPath',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: RescuePalette.textMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _isInitializing
                        ? null
                        : () {
                            setState(() {
                              _isModelReady = false;
                              _contextId = null;
                            });
                            unawaited(_initLlama());
                          },
                    child: Text(_isInitializing ? '加载中' : '重载'),
                  ),
                ],
              ),
            ),
            if (_initError != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: RescuePalette.criticalSoft,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: RescuePalette.critical),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: RescuePalette.critical,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '模型准备失败：$_initError',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: RescuePalette.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return _buildBubble(
                    text: message['text'] ?? '',
                    isUser: message['role'] == 'user',
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: const BoxDecoration(
                color: RescuePalette.panel,
                border: Border(top: BorderSide(color: RescuePalette.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      minLines: 1,
                      maxLines: 5,
                        decoration: InputDecoration(
                          hintText: _isModelReady
                              ? '描述症状、伤情或现场情况，尽量写清呼吸、意识、出血和疼痛部位...'
                              : '正在准备模型，请稍候...',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _isSending || !_isModelReady
                        ? null
                        : _sendMessage,
                    style: FilledButton.styleFrom(
                      backgroundColor: RescuePalette.accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(56, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: _isSending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble({required String text, required bool isUser}) {
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor = isUser ? const Color(0xFFDCEBF7) : RescuePalette.panel;
    final borderColor = isUser ? const Color(0xFFA8C7DE) : RescuePalette.border;

    return Align(
      alignment: alignment,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
          boxShadow: const [
            BoxShadow(
              color: Color(0x11000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUser ? '你' : 'AI 助手',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: isUser ? RescuePalette.accent : RescuePalette.critical,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                height: 1.55,
                color: RescuePalette.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tokenSubscription?.cancel();
    final contextId = _contextId;
    if (contextId != null) {
      unawaited(_llama?.releaseContext(contextId));
    }
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
