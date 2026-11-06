import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

/** 26-沙雕漫剧 根目录 */
export const SKILL_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../../..');
export const PROJECTS_ROOT = join(SKILL_ROOT, '99-项目');

export function seasonDir(project, season = 1) {
  if (!project) throw new Error('缺少 --project（剧名）');
  const dir = join(PROJECTS_ROOT, project, `第${String(season).padStart(2, '0')}季`);
  if (!existsSync(dir)) throw new Error(`季目录不存在：${dir}`);
  return dir;
}

export function readJson(path) {
  if (!existsSync(path)) throw new Error(`找不到文件：${path}`);
  return JSON.parse(readFileSync(path, 'utf8'));
}

export function writeJson(path, data) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify(data, null, 2) + '\n', 'utf8');
}

export function ensureDir(dir) {
  mkdirSync(dir, { recursive: true });
  return dir;
}

export function relPath(fromDir, target) {
  return relative(fromDir, target).split('\\').join('/');
}

export function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const token = argv[i];
    if (token.startsWith('--')) {
      const key = token.slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith('--')) {
        args[key] = true;
      } else {
        args[key] = next;
        i++;
      }
    } else {
      args._.push(token);
    }
  }
  return args;
}
