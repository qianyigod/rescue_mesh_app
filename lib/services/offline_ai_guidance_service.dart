class OfflineAiGuidance {
  const OfflineAiGuidance({
    required this.systemPrompt,
    required this.fallbackReply,
  });

  final String systemPrompt;
  final String fallbackReply;
}

class OfflineAiGuidanceService {
  const OfflineAiGuidanceService();

  OfflineAiGuidance buildGuidance({
    required String latestMessage,
    List<String> previousUserMessages = const [],
  }) {
    final conversation = [
      ...previousUserMessages,
      latestMessage,
    ].where((message) => message.trim().isNotEmpty).join('\n');

    return OfflineAiGuidance(
      systemPrompt: _buildSystemPrompt(conversation),
      fallbackReply: _buildFallbackReply(conversation),
    );
  }

  String _buildSystemPrompt(String conversation) {
    return [
      '你是一个离线急救助手。',
      '你的目标不是给笼统安慰，而是基于现有描述直接给出尽可能详细、可执行、分步骤的建议。',
      '如果用户信息不充分，你可以根据常见急救场景做合理猜测，但必须明确写出“更可能是哪些情况”和“为什么这样判断”。',
      '不要只说“信息不足”或“建议就医”就结束，必须先给用户此刻能做的具体动作。',
      '回答结构固定为：',
      '1. 当前更可能的情况',
      '2. 现在立刻怎么做',
      '3. 接下来 10 到 30 分钟观察什么',
      '4. 什么情况下必须立刻联系专业急救',
      '5. 如仍缺关键信息，最后只补 1 个最关键的问题',
      '要求：',
      '- 用中文',
      '- 语气直接，不空泛',
      '- 优先给出细化动作，比如体位、压迫、冷敷、固定、休息、补水、避免做什么',
      '- 可以做基于症状的推断，但不要编造检查结果、药物剂量或不存在的既往史',
      '- 如果描述涉及胸痛、呼吸困难、昏迷、持续出血、抽搐、头部重伤等情况，要明确提醒尽快求援',
      '',
      '最近对话：',
      conversation,
    ].join('\n');
  }

  String _buildFallbackReply(String conversation) {
    final text = _normalize(conversation);

    if (_containsAny(text, const ['流血', '出血', '伤口', '割伤', '血流不止', '止不住血'])) {
      return [
        '基于你目前的描述，更可能是开放性伤口或软组织损伤出血；如果血流很快、按压后仍止不住，也不能排除较严重血管损伤。',
        '现在立刻怎么做：直接用干净纱布、衣物或毛巾持续压住出血点，不要反复掀开看；如果四肢伤口出血，抬高受伤肢体并继续压迫；伤口周围能简单包扎就做加压包扎。',
        '接下来 10 到 30 分钟观察什么：看出血是否明显减少，皮肤是否变白、发冷，是否出现头晕、心慌、乏力。',
        '什么情况下必须立刻联系专业急救：血流不止、伤口很深、喷涌样出血、患者头晕站不稳，或者面色苍白出冷汗。',
        '还需要确认：出血现在按压后能不能明显止住？',
      ].join('\n');
    }

    if (_containsAny(text, const ['胸痛', '胸闷', '胸口痛', '胸口疼', '喘不上气', '呼吸困难', '冒冷汗'])) {
      return [
        '基于你目前的描述，更需要优先怀疑心肺问题，比如急性心脏供血不足、剧烈胸壁疼痛，或伴随呼吸受限的急症。',
        '现在立刻怎么做：立刻停止活动，坐下或半躺休息，保持周围空气流通，解开领口，尽量不要独自行动。',
        '接下来 10 到 30 分钟观察什么：胸痛是否持续超过几分钟，呼吸是否越来越费力，是否伴随冷汗、恶心、头晕、嘴唇发紫。',
        '什么情况下必须立刻联系专业急救：如果胸痛持续不缓解、呼吸困难加重、出现濒死感、冷汗、意识发差，应该马上联系急救。',
        '还需要确认：胸痛是持续压榨样，还是按压、转身时才更痛？',
      ].join('\n');
    }

    if (_containsAny(text, const ['头晕', '头痛', '头疼', '眼前发黑'])) {
      return [
        '基于你目前的描述，更可能是疲劳、脱水、低血糖、血压波动，或者普通头痛发作；如果同时有说话不清、单侧无力、剧烈呕吐，也不能排除更严重问题。',
        '现在立刻怎么做：先坐下或平卧，避免继续走动；如果长时间没吃东西，少量补充温水和容易吸收的糖分；保持安静休息，先不要开车或登高。',
        '接下来 10 到 30 分钟观察什么：头晕是否缓解，是否出现胸痛、呼吸困难、呕吐、肢体无力、意识变差。',
        '什么情况下必须立刻联系专业急救：突然最严重的头痛、说话不清、一侧手脚无力、反复呕吐、昏睡叫不醒。',
        '还需要确认：现在有没有说话不清、单侧无力，或者胸痛呼吸困难？',
      ].join('\n');
    }

    if (_containsAny(text, const ['烫伤', '烧伤'])) {
      return [
        '基于你目前的描述，更像是局部热力损伤；如果面积大、起大泡很多或伤在面部手部会更麻烦。',
        '现在立刻怎么做：立即用流动凉水持续冲洗 15 到 20 分钟；去掉附近的戒指、手表等勒紧物；不要涂牙膏、酱油或偏方。',
        '接下来 10 到 30 分钟观察什么：看疼痛是否缓解，皮肤是否起泡、发白、焦黑，范围是否继续扩大。',
        '什么情况下必须立刻联系专业急救：面积较大、面部或会阴烧伤、深度烧伤、呼吸道灼伤，或疼痛和肿胀持续加重。',
        '还需要确认：烫伤部位和大概面积有多大？',
      ].join('\n');
    }

    if (_containsAny(text, const ['摔倒', '扭伤', '骨折', '变形', '不能活动'])) {
      return [
        '基于你目前的描述，更可能是扭伤、骨折，或关节脱位一类的创伤问题。',
        '现在立刻怎么做：先停止活动，尽量固定受伤部位；能冷敷就冷敷 15 到 20 分钟；不要反复揉按，也不要强行复位。',
        '接下来 10 到 30 分钟观察什么：疼痛是否迅速加重，肿胀是否扩大，远端手脚有没有麻木、发凉、颜色变差。',
        '什么情况下必须立刻联系专业急救：肢体明显变形、完全不能承重或活动、疼痛剧烈、末端发白发凉发麻。',
        '还需要确认：受伤部位现在还能轻微活动吗？',
      ].join('\n');
    }

    return [
      '基于你现在的描述，暂时更像是常见不适、轻伤，或者还没有把关键症状说完整；但我会先按最常见、最实用的方向给你处理建议。',
      '现在立刻怎么做：先停下手头动作，坐下或休息到安全位置；如果有疼痛、头晕、恶心、伤口或发热，先处理最明显的不适，不要硬撑着继续活动。',
      '接下来 10 到 30 分钟观察什么：是否出现呼吸困难、胸痛、明显出血、意识变差、持续加重的疼痛，或者活动后越来越难受。',
      '什么情况下必须立刻联系专业急救：出现胸痛胸闷、喘不上气、昏迷、抽搐、持续出血、头部重伤后呕吐或意识差。',
      '还需要确认：最难受的是哪里？是疼、晕、喘、出血，还是发热？从什么时候开始？',
    ].join('\n');
  }

  bool _containsAny(String source, List<String> needles) {
    for (final needle in needles) {
      if (source.contains(needle)) {
        return true;
      }
    }
    return false;
  }

  String _normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('，', '')
        .replaceAll('。', '')
        .replaceAll('？', '')
        .replaceAll('！', '')
        .replaceAll(',', '')
        .replaceAll('.', '')
        .replaceAll('?', '')
        .replaceAll('!', '');
  }
}
