// 测试用 V2 插件：skill.transform + session context hook。
export default {
  id: 'v2-test',
  setup(ctx) {
    ctx.skill.transform((draft) => {
      draft.add({
        id: 'plugin-skill',
        name: 'plugin-skill',
        description: 'from plugin',
        path: '',
        content: 'Do the plugin thing.',
      });
    });
    ctx.session.hook('context', async (event) => {
      const first = event.messages[0];
      first.content.unshift({ type: 'text', text: 'PLUGIN CONTEXT' });
    });
  },
};
