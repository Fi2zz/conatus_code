/// 内嵌插件宿主源码。首次使用时写到 `~/.nava/plugins/host-<hash>.mjs`。
///
// REASON: 内嵌 JS 宿主必须保持单文件制品，拆分会破坏 AOT 二进制自包含；
// 这是仓库「超长静态映射表/第三方固定格式」例外。
library;

/// Node ESM 宿主：加载插件、收集技能/工具/上下文，并代理 hook。
///
/// 这是插件运行时的唯一 JS 文件；不依赖外部 npm 包。stdout 只写 JSON-RPC，
/// 插件的 console 输出全部重定向到 stderr。
const String kPluginHostSource = r'''
import { createInterface } from 'node:readline';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import { execFile } from 'node:child_process';

const write = (value) => process.stdout.write(JSON.stringify(value) + '\n');
const log = (...args) => process.stderr.write('[nava-plugin] ' + args.map(String).join(' ') + '\n');
console.log = console.info = console.debug = (...args) => log(...args);
console.warn = console.error = (...args) => log(...args);

const state = {
  hooks: Object.create(null),
  tools: new Map(),
  skills: [],
  skillRoots: [],
  contextHooks: [],
  shellEnv: Object.create(null),
  warnings: [],
  directory: process.cwd(),
  worktree: process.cwd(),
};
const pending = new Map();
let nextId = 1;

function request(method, params) {
  const id = 'h' + nextId++;
  write({ jsonrpc: '2.0', id, method, params: params || {} });
  return new Promise((resolve) => pending.set(id, resolve));
}
function respond(id, result) {
  write({ jsonrpc: '2.0', id, result: result || {} });
}
function respondError(id, message) {
  write({ jsonrpc: '2.0', id, error: { code: -32000, message: String(message) } });
}
function notify(method, params) {
  write({ jsonrpc: '2.0', method, params: params || {} });
}
function warn(message) {
  const text = String(message);
  state.warnings.push(text);
  log(text);
}

function mergeHooks(target, source) {
  if (!source || typeof source !== 'object') return;
  for (const [name, value] of Object.entries(source)) {
    if (Array.isArray(value)) {
      for (const fn of value) {
        if (typeof fn === 'function') (target[name] ||= []).push(fn);
      }
    } else if (typeof value === 'function') {
      (target[name] ||= []).push(value);
    } else if (name === 'tool' && value && typeof value === 'object') {
      for (const [toolName, def] of Object.entries(value)) registerTool(toolName, def);
    }
  }
}

function schemaFromArgs(args) {
  if (!args) return { type: 'object', additionalProperties: true };
  if (typeof args === 'object' && typeof args.type === 'string') return args;
  const shape = args.shape || (args._def && args._def.shape);
  if (!shape) return { type: 'object', additionalProperties: true };
  const resolved = typeof shape === 'function' ? shape() : shape;
  if (!resolved || typeof resolved !== 'object') {
    return { type: 'object', additionalProperties: true };
  }
  const properties = {};
  const required = [];
  for (const [key, value] of Object.entries(resolved)) {
    const converted = schemaFromZod(value);
    properties[key] = converted.schema;
    if (converted.required) required.push(key);
  }
  const result = { type: 'object', properties };
  if (required.length) result.required = required;
  return result;
}

function schemaFromZod(value) {
  if (!value || typeof value !== 'object') return { schema: {}, required: false };
  const def = value._def || {};
  const type = def.typeName || '';
  const unwrap = (inner) => schemaFromZod(inner);
  switch (type) {
    case 'ZodOptional':
    case 'ZodDefault':
    case 'ZodNullable':
      return { ...unwrap(def.innerType), required: false };
    case 'ZodString': return { schema: { type: 'string' }, required: true };
    case 'ZodNumber': return { schema: { type: 'number' }, required: true };
    case 'ZodBoolean': return { schema: { type: 'boolean' }, required: true };
    case 'ZodEnum': return { schema: { type: 'string', enum: def.values || [] }, required: true };
    case 'ZodLiteral': return { schema: { const: def.value }, required: true };
    case 'ZodArray':
      return { schema: { type: 'array', items: schemaFromZod(def.type).schema }, required: true };
    case 'ZodObject':
      return { schema: schemaFromArgs(value), required: true };
    case 'ZodRecord':
      return { schema: { type: 'object', additionalProperties: true }, required: true };
    case 'ZodUnion':
      return { schema: {}, required: true };
    default:
      return { schema: {}, required: true };
  }
}

function registerTool(name, def) {
  if (!def || typeof def.execute !== 'function') return;
  const entry = {
    name: String(name),
    description: String(def.description || ''),
    parameters: schemaFromArgs(def.args),
    execute: def.execute,
  };
  state.tools.set(entry.name, entry);
}

function makeDraft(list) {
  return {
    list,
    add(item) { list.push(item); },
    update(id, item) {
      const index = list.findIndex((entry) => entry && entry.id === id);
      if (index >= 0) list[index] = item;
    },
    remove(id) {
      for (let i = list.length - 1; i >= 0; i -= 1) {
        if (list[i] && list[i].id === id) list.splice(i, 1);
      }
    },
  };
}

function makeContext(plugin) {
  const session = {
    hook: (name, fn) => {
      if (typeof fn !== 'function') return;
      if (name === 'context') state.contextHooks.push(fn);
      else (state.hooks['session.' + name] ||= []).push(fn);
    },
    get: async () => undefined,
  };
  const skill = {
    transform: (fn) => {
      const draft = makeDraft([]);
      try { fn(draft); } catch (error) { warn('skill.transform 失败：' + error); }
      state.skills.push(...draft.list);
    },
  };
  const tool = {
    transform: (fn) => {
      const draft = makeDraft([]);
      try { fn(draft); } catch (error) { warn('tool.transform 失败：' + error); }
      for (const def of draft.list) {
        if (def && def.name) registerTool(def.name, def);
      }
    },
  };
  const noopDomain = new Proxy({}, {
    get: (_target, key) => {
      if (key === 'transform') return (fn) => {
        const draft = makeDraft([]);
        try { fn(draft); } catch (error) { warn('domain.transform 失败：' + error); }
      };
      if (key === 'hook') return () => {};
      if (key === 'get') return async () => undefined;
      return () => undefined;
    },
  });
  return new Proxy({
    options: plugin.options || {},
    directory: plugin.directory || state.directory,
    worktree: plugin.worktree || state.worktree,
    log: async (value) => log(value && value.body ? value.body.message : value),
    skill,
    session,
    tool,
  }, {
    get: (target, key) => (key in target ? target[key] : noopDomain),
  });
}

const clientStub = {
  app: { log: async (value) => log(value && value.body ? value.body.message : value) },
  session: { get: async () => undefined },
};

function shellStub(strings, ...values) {
  let command = strings[0];
  for (let i = 0; i < values.length; i += 1) command += String(values[i]) + strings[i + 1];
  return new Promise((resolve) => {
    execFile('sh', ['-c', command], { cwd: state.directory }, (error, stdout, stderr) => {
      const text = String(stdout || '');
      if (error) log('$ 失败：' + error.message + ' ' + String(stderr || ''));
      resolve(text);
    });
  });
}

async function loadPlugin(plugin) {
  const target = plugin.local
    ? pathToFileURL(plugin.entry).href
    : plugin.entry;
  const module = await import(target);
  const context = {
    project: { id: 'nava', name: path.basename(state.worktree) },
    directory: plugin.directory || state.directory,
    worktree: plugin.worktree || state.worktree,
    client: clientStub,
    $: shellStub,
    options: plugin.options || {},
  };
  const hooks = Object.create(null);
  const setup = module.default && typeof module.default.setup === 'function'
    ? module.default.setup
    : null;
  if (setup) {
    await setup(makeContext(plugin));
    if (module.SuperpowersPlugin) log('插件同时提供 V1/V2，按 V2 setup 加载：' + plugin.id);
    return;
  }
  const candidates = [];
  for (const [name, value] of Object.entries(module)) {
    if (name === 'default') continue;
    if (typeof value === 'function') candidates.push(value);
  }
  if (typeof module.default === 'function') candidates.push(module.default);
  else if (module.default && typeof module.default.server === 'function') {
    candidates.push(module.default.server);
  }
  for (const fn of candidates) {
    const returned = await fn(context);
    mergeHooks(hooks, returned);
  }
  mergeHooks(state.hooks, hooks);
}

async function collectLegacySkillRoots() {
  for (const fn of state.hooks.config || []) {
    const config = { skills: { paths: [] } };
    try {
      await fn(config);
      const paths = config.skills && config.skills.paths;
      if (Array.isArray(paths)) state.skillRoots.push(...paths.map(String));
    } catch (error) {
      warn('config hook 失败：' + error);
    }
  }
}

async function collectContext() {
  const texts = [];
  for (const fn of state.contextHooks) {
    const event = {
      sessionID: 'nava-bootstrap',
      messages: [{ role: 'user', content: [{ type: 'text', text: '' }] }],
    };
    try {
      await fn(event);
      for (const message of event.messages || []) {
        for (const part of message.content || []) {
          if (part && part.type === 'text' && part.text && !texts.includes(part.text)) {
            texts.push(part.text);
          }
        }
      }
    } catch (error) {
      warn('session context hook 失败：' + error);
    }
  }
  for (const fn of state.hooks['experimental.chat.messages.transform'] || []) {
    const output = {
      messages: [{ info: { role: 'user', sessionID: 'nava-bootstrap' }, parts: [{ type: 'text', text: '' }] }],
    };
    try {
      await fn({}, output);
      for (const message of output.messages || []) {
        for (const part of message.parts || []) {
          if (part && part.type === 'text' && part.text && !texts.includes(part.text)) {
            texts.push(part.text);
          }
        }
      }
    } catch (error) {
      warn('messages.transform hook 失败：' + error);
    }
  }
  return texts.join('\n\n');
}

async function collectShellEnv() {
  const env = Object.create(null);
  for (const fn of state.hooks['shell.env'] || []) {
    const output = { env: {} };
    try {
      await fn({ cwd: state.directory }, output);
      Object.assign(env, output.env || {});
    } catch (error) {
      warn('shell.env hook 失败：' + error);
    }
  }
  return env;
}

async function initPlugins(params) {
  state.directory = params.directory || state.directory;
  state.worktree = params.worktree || state.directory;
  for (const plugin of params.plugins || []) {
    try {
      await loadPlugin(plugin);
    } catch (error) {
      warn('插件 ' + plugin.id + ' 加载失败：' + error);
    }
  }
  await collectLegacySkillRoots();
  const context = await collectContext();
  const env = await collectShellEnv();
  return {
    skills: state.skills,
    skillRoots: state.skillRoots,
    tools: [...state.tools.values()].map((entry) => ({
      name: entry.name,
      description: entry.description,
      parameters: entry.parameters,
    })),
    context,
    shellEnv: env,
    warnings: state.warnings,
  };
}

async function runHook(params) {
  const list = state.hooks[params.name] || [];
  const output = params.output || {};
  for (const fn of list) {
    try {
      await fn(params.input || {}, output);
    } catch (error) {
      if (params.name === 'tool.execute.before') {
        return { blocked: true, reason: String(error), output };
      }
      warn(params.name + ' hook 失败：' + error);
    }
  }
  return { blocked: false, output };
}

async function runTool(params) {
  const tool = state.tools.get(params.name);
  if (!tool) throw new Error('未知插件工具：' + params.name);
  const value = await tool.execute(params.args || {}, {
    directory: state.directory,
    worktree: state.worktree,
    sessionID: params.sessionID || '',
  });
  return { output: typeof value === 'string' ? value : JSON.stringify(value) };
}

function notifyEvent(event) {
  const list = state.hooks.event || [];
  for (const fn of list) {
    Promise.resolve()
      .then(() => fn({ event }))
      .catch((error) => warn('event hook 失败：' + error));
  }
}

async function handle(message) {
  if (message.method && message.id !== undefined) {
    try {
      let result;
      if (message.method === 'init') result = await initPlugins(message.params || {});
      else if (message.method === 'hook') result = await runHook(message.params || {});
      else if (message.method === 'tool.execute') result = await runTool(message.params || {});
      else if (message.method === 'shutdown') {
        respond(message.id, {});
        setTimeout(() => process.exit(0), 0);
        return;
      } else throw new Error('未知方法：' + message.method);
      respond(message.id, result);
    } catch (error) {
      respondError(message.id, error && error.message ? error.message : String(error));
    }
    return;
  }
  if (message.method) {
    if (message.method === 'event') notifyEvent((message.params || {}).event || {});
    return;
  }
  if (message.id !== undefined && pending.has(message.id)) {
    const resolve = pending.get(message.id);
    pending.delete(message.id);
    resolve(message);
  }
}

const reader = createInterface({ input: process.stdin, crlfDelay: Infinity });
reader.on('line', (line) => {
  if (!line.trim()) return;
  let message;
  try { message = JSON.parse(line); } catch (error) { log('协议行不是 JSON：' + error); return; }
  handle(message).catch((error) => log('消息处理失败：' + error));
});
reader.on('close', () => process.exit(0));
''';
