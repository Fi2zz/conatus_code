/// 审批浮层的说明文本：工具描述 + 权限动作 / 资源 / 命中规则。
library;

import 'package:conatus_agent/conatus_agent.dart';

/// 组合展示文本；没有任何附加权限信息时原样返回 [ApprovalRequest.description]。
String approvalRequestDetail(ApprovalRequest request) {
  final List<String> lines = <String>[
    if (request.description.isNotEmpty) request.description,
    if (request.action.isNotEmpty) '动作：${request.action}',
    if (request.resources.isNotEmpty) '资源：${request.resources.join('、')}',
    if (request.rule != null) '命中规则：${request.rule}',
  ];
  return lines.join('\n');
}
