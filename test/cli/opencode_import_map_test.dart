/// OpenCode 配置 → nava 导入模型：字段映射与告警。
library;

import 'package:conatus_code/conatus_code.dart';
import 'package:test/test.dart';

OpenCodeImport _build(List<Map<String, Object?>> docs) => buildOpenCodeImport(
  OpenCodeSources(
    documents: <OpenCodeDocument>[
      for (int index = 0; index < docs.length; index++)
        OpenCodeDocument(
          path: '/tmp/opencode-$index.jsonc',
          values: docs[index],
        ),
    ],
    warnings: const <String>[],
  ),
);

void main() {
  test('标量字段后者覆盖，model 去掉 #variant', () {
    final OpenCodeImport result = _build(<Map<String, Object?>>[
      <String, Object?>{
        'model': 'anthropic/claude#high',
        'default_agent': 'build',
      },
      <String, Object?>{'model': 'openai/gpt-6.1'},
    ]);

    expect(result.model, 'openai/gpt-6.1');
    expect(result.defaultAgent, 'build');
    expect(result.warnings.join('\n'), contains('#variant'));
  });

  test('MCP local：command 数组、environment 与 {env:} 占位符', () {
    final OpenCodeImport result = _build(<Map<String, Object?>>[
      <String, Object?>{
        'mcp': <String, Object?>{
          'servers': <String, Object?>{
            'everything': <String, Object?>{
              'type': 'local',
              'command': <String>['npx', '-y', 'server-everything'],
              'environment': <String, String>{
                'TOKEN': '{env:MCP_TOKEN}',
              },
            },
          },
        },
      },
    ]);

    final McpServerSpec spec = result.mcpServers.single;
    expect(spec.type, McpServerType.stdio);
    expect(spec.command, 'npx');
    expect(spec.args, <String>['-y', 'server-everything']);
    expect(spec.env['TOKEN'], r'${MCP_TOKEN}');
  });

  test('MCP remote：url / headers / oauth=false / oauth 对象', () {
    final OpenCodeImport result = _build(<Map<String, Object?>>[
      <String, Object?>{
        'mcp': <String, Object?>{
          'servers': <String, Object?>{
            'plain': <String, Object?>{
              'type': 'remote',
              'url': 'https://a.example/mcp',
              'headers': <String, String>{'X-Key': '{env:KEY}'},
              'oauth': false,
            },
            'registered': <String, Object?>{
              'type': 'remote',
              'url': 'https://b.example/mcp',
              'oauth': <String, Object?>{
                'client_id': 'client-1',
                'scope': 'read write',
              },
            },
          },
        },
      },
    ]);

    final McpServerSpec plain = result.mcpServers[0];
    expect(plain.type, McpServerType.http);
    expect(plain.url, 'https://a.example/mcp');
    expect(plain.headers['X-Key'], r'${KEY}');
    expect(plain.oauthEnabled, isFalse);

    final McpServerSpec registered = result.mcpServers[1];
    expect(registered.oauth!.clientId, 'client-1');
    expect(registered.oauth!.scope, 'read write');
    expect(registered.oauthEnabled, isTrue);
  });

  test('MCP disabled / cwd 与未知字段告警', () {
    final OpenCodeImport result = _build(<Map<String, Object?>>[
      <String, Object?>{
        'mcp': <String, Object?>{
          'servers': <String, Object?>{
            'off': <String, Object?>{
              'type': 'local',
              'command': <String>['npx'],
              'disabled': true,
            },
            'with-cwd': <String, Object?>{
              'type': 'local',
              'command': <String>['npx'],
              'cwd': './tools',
            },
          },
        },
      },
    ]);

    expect(result.mcpServers.map((McpServerSpec spec) => spec.name), <String>[
      'with-cwd',
    ]);
    expect(result.warnings.join('\n'), contains('disabled'));
    expect(result.warnings.join('\n'), contains('cwd'));
  });

  test('高优先级同名 MCP server 整体替换', () {
    final OpenCodeImport result = _build(<Map<String, Object?>>[
      <String, Object?>{
        'mcp': <String, Object?>{
          'servers': <String, Object?>{
            'shared': <String, Object?>{
              'type': 'local',
              'command': <String>['old'],
            },
          },
        },
      },
      <String, Object?>{
        'mcp': <String, Object?>{
          'servers': <String, Object?>{
            'shared': <String, Object?>{
              'type': 'remote',
              'url': 'https://new.example/mcp',
            },
          },
        },
      },
    ]);

    expect(result.mcpServers.single.url, 'https://new.example/mcp');
  });

  test('permissions 归一化 OpenCode 动作并跳过不支持项', () {
    final OpenCodeImport result = _build(<Map<String, Object?>>[
      <String, Object?>{
        'permissions': <Object?>[
          <String, Object?>{
            'action': 'bash',
            'resource': 'git push *',
            'effect': 'ask',
          },
          <String, Object?>{
            'action': 'write',
            'resource': 'src/**',
            'effect': 'deny',
          },
          <String, Object?>{
            'action': 'lsp',
            'resource': '*',
            'effect': 'allow',
          },
        ],
      },
    ]);

    expect(
      result.permissions.map((ImportedPermission rule) => rule.action),
      <String>['shell', 'edit'],
    );
    expect(result.permissions[0].resource, 'git push *');
    expect(result.permissions[1].effect, 'deny');
    expect(result.warnings.join('\n'), contains('lsp'));
  });

  test('providers：baseURL / 密钥 / 类型 / 模型元数据', () {
    final OpenCodeImport result = _build(<Map<String, Object?>>[
      <String, Object?>{
        'providers': <String, Object?>{
          'acme': <String, Object?>{
            'package': '@opencode/ai/providers/openai-compatible',
            'settings': <String, Object?>{
              'baseURL': 'https://acme.example/v1',
              'apiKey': '{env:ACME_KEY}',
            },
            'models': <String, Object?>{
              'gpt-x': <String, Object?>{
                'modelID': 'gpt-x-2025',
                'name': 'GPT X',
                'limit': <String, Object?>{'context': 128000},
              },
            },
          },
          'claude': <String, Object?>{
            'package': '@opencode/ai/providers/anthropic',
            'settings': <String, Object?>{
              'baseURL': 'https://api.anthropic.com/v1',
              'apiKey': 'sk-ant',
            },
          },
          'oauth-only': <String, Object?>{'settings': <String, Object?>{}},
        },
      },
    ]);

    expect(result.providers, hasLength(2));
    final ImportedProvider acme = result.providers[0];
    expect(acme.name, 'acme');
    expect(acme.baseUrl, 'https://acme.example/v1');
    expect(acme.credentialKey, 'ACME_KEY');
    expect(acme.apiKey, isNull);
    expect(acme.type, 'openai');
    expect(acme.models.single.model, 'gpt-x-2025');
    expect(acme.models.single.displayName, 'GPT X');
    expect(acme.models.single.maxContext, 128000);

    final ImportedProvider claude = result.providers[1];
    expect(claude.type, 'anthropic');
    expect(claude.apiKey, 'sk-ant');
    expect(result.warnings.join('\n'), contains('oauth-only'));
  });

  test('instructions 追加；skills 本地目录保留，agents / commands 告警跳过', () {
    final OpenCodeImport result = _build(<Map<String, Object?>>[
      <String, Object?>{
        'instructions': <Object?>['CONTRIBUTING.md', 'docs/*.md'],
        'skills': <Object?>['./team-skills', 'https://example.com/skills'],
        'agents': <String, Object?>{'reviewer': <String, Object?>{}},
        'commands': <String, Object?>{'review': <String, Object?>{}},
      },
    ]);

    expect(result.instructions, <String>['CONTRIBUTING.md', 'docs/*.md']);
    expect(result.skillDirs.single, contains('team-skills'));
    final String warnings = result.warnings.join('\n');
    expect(warnings, contains('HTTP 技能目录'));
    expect(warnings, contains('agents'));
    expect(warnings, contains('commands'));
  });
}
