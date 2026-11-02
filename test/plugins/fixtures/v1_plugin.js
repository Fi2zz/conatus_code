// 测试用 V1 插件：技能根、自定义工具、before/after、event、shell.env。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

export const TestPlugin = async () => {
  return {
    config: async (config) => {
      config.skills.paths.push(path.join(here, 'skills'));
    },
    'tool.execute.before': async (_input, output) => {
      if (output.args && String(output.args.filePath || '').includes('.env')) {
        throw new Error('blocked .env');
      }
    },
    'tool.execute.after': async (_input, output) => {
      output.output = output.output + ' [after]';
    },
    'shell.env': async (_input, output) => {
      output.env.TEST_PLUGIN_ENV = '1';
    },
    event: async ({ event }) => {
      if (event.type === 'session.idle') {
        fs.writeFileSync(path.join(process.cwd(), 'plugin-event.txt'), 'idle');
      }
    },
    tool: {
      plugin_echo: {
        description: 'echo from plugin',
        args: {
          type: 'object',
          properties: { text: { type: 'string' } },
          required: ['text'],
        },
        execute: async (args) => 'echo:' + args.text,
      },
    },
  };
};
