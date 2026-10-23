/// 内置 Agent 定义：`build` / `plan` / `general` / `explore`。
library;

import 'package:conatus_agent/conatus_agent.dart'
    show PermissionEffect, PermissionRule;

import 'agent_definition.dart';

/// 内置 `build`：当前默认行为，无额外限制。
const AgentDefinition _buildAgent = AgentDefinition(
  id: 'build',
  sourcePath: 'builtin:build',
  description: '通用编码 Agent',
  system: '你是 nava 的通用编码 Agent。直接完成用户任务：读写代码、运行命令并验证结果。',
);

/// 内置 `plan`：规划优先，禁止改文件。
const AgentDefinition _planAgent = AgentDefinition(
  id: 'plan',
  sourcePath: 'builtin:plan',
  description: '只读规划 Agent',
  system: '你是只读规划 Agent。先调查代码并给出可执行计划；不要修改文件，等待用户确认后再执行。',
  permissions: <PermissionRule>[
    PermissionRule(
      action: 'edit',
      resource: '*',
      effect: PermissionEffect.deny,
      source: 'builtin',
    ),
  ],
);

/// 内置 `general`：可写的通用子 Agent；不能再 spawn 由工具自身限制。
///
/// [tools] 必须显式给出：`null` 会回落到宿主的只读默认白名单（read / rg /
/// glob / git 只读），与「广工具、可写」的定位矛盾。high 风险工具（run_command
/// / run_tests / git_commit）即使列在这里也会被 `spawn_agent` 的 `_usable`
/// 挡掉——子 Agent 没有审批层，这是硬边界。
const AgentDefinition _generalAgent = AgentDefinition(
  id: 'general',
  sourcePath: 'builtin:general',
  description: '通用子 Agent',
  mode: AgentMode.subagent,
  system: '你是通用子 Agent。独立完成委派的子任务，汇报结果与关键证据。',
  tools: <String>[
    'read_file',
    'list_files',
    'rg',
    'glob',
    'write_file',
    'edit_file',
    'apply_patch',
    'git_status',
    'git_diff',
    'git_add',
    'git_branch',
    'git_stash',
    'web_search',
    'fetch_url',
    'update_plan',
  ],
);

/// 内置 `explore`：只读探索，工具白名单限定在读取与联网查询。
const AgentDefinition _exploreAgent = AgentDefinition(
  id: 'explore',
  sourcePath: 'builtin:explore',
  description: '只读探索 Agent',
  mode: AgentMode.subagent,
  system: '你是只读探索 Agent。定位代码与资料，回答事实与位置；不要修改任何文件。',
  tools: <String>[
    'read_file',
    'list_files',
    'rg',
    'glob',
    'web_search',
    'fetch_url',
  ],
  permissions: <PermissionRule>[
    PermissionRule(
      action: 'edit',
      resource: '*',
      effect: PermissionEffect.deny,
      source: 'builtin',
    ),
  ],
);

/// 内置 Agent，按注册顺序排列。
const List<AgentDefinition> kBuiltinAgents = <AgentDefinition>[
  _buildAgent,
  _planAgent,
  _generalAgent,
  _exploreAgent,
];
