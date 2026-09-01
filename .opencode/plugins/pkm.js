/**
 * pkm plugin for OpenCode.ai
 *
 * Auto-registers the skills directory via the config hook (no symlinks needed).
 *
 * Unlike superpowers, this plugin injects no per-session bootstrap context.
 * The pkm skills are explicitly invoked — you reach for them when clipping a
 * session or filing a bookmark — so OpenCode's native `skill` tool discovering
 * them is all that is needed. `obsidian-session-clip` must never fire on its
 * own, which is another reason there is no preamble here.
 */

import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export const PkmPlugin = async () => {
  const pkmSkillsDir = path.resolve(__dirname, '../../skills');

  return {
    // Inject skills path into live config so OpenCode discovers pkm skills
    // without requiring manual symlinks or config file edits.
    // This works because Config.get() returns a cached singleton — modifications
    // here are visible when skills are lazily discovered later.
    config: async (config) => {
      config.skills = config.skills || {};
      config.skills.paths = config.skills.paths || [];
      if (!config.skills.paths.includes(pkmSkillsDir)) {
        config.skills.paths.push(pkmSkillsDir);
      }
    },
  };
};
