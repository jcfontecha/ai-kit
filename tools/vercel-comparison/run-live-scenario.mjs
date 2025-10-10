import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { execSync } from 'node:child_process';
import { createScenarioDefinitions } from './scenarios.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '..', '..');
const vercelRoot = path.join(repoRoot, 'vercel-sdk');
const distEntry = path.join(vercelRoot, 'packages', 'ai', 'dist', 'index.mjs');
async function resolveOpenAIEntry() {
  const candidates = [
    path.join(vercelRoot, 'node_modules', '@ai-sdk', 'openai', 'dist', 'index.mjs'),
    path.join(vercelRoot, 'packages', 'openai', 'dist', 'index.mjs'),
  ];
  for (const candidate of candidates) {
    try {
      await fs.access(candidate);
      return candidate;
    } catch (error) {
      // continue searching
    }
  }
  throw new Error(
    'Required bundle not found for @ai-sdk/openai. Ensure dependencies are installed and the package is built.',
  );
}

async function ensureDistExists(openaiEntry) {
  for (const entry of [distEntry, openaiEntry]) {
    try {
      await fs.access(entry);
    } catch (error) {
      throw new Error(
        `Required bundle not found at ${entry}. Run \`(cd vercel-sdk && corepack pnpm --filter ai build && corepack pnpm --filter @ai-sdk/openai build)\` first.`,
      );
    }
  }
}

function readOpenAIKey() {
  if (process.env.OPENAI_API_KEY && process.env.OPENAI_API_KEY.trim().length > 0) {
    return process.env.OPENAI_API_KEY.trim();
  }
  try {
    const output = execSync('plutil -extract OPENAI_API_KEY raw -o - Config.plist', {
      cwd: repoRoot,
      stdio: ['ignore', 'pipe', 'ignore'],
      encoding: 'utf8',
    }).trim();
    if (!output) {
      throw new Error('Config.plist did not contain OPENAI_API_KEY');
    }
    return output;
  } catch (error) {
    throw new Error(
      'Could not resolve OPENAI_API_KEY. Set the environment variable or ensure Config.plist contains it.',
    );
  }
}

function toSerializable(value) {
  const replacer = (key, val) => {
    if (val instanceof Map) {
      return Object.fromEntries(val.entries());
    }
    if (val instanceof Set) {
      return Array.from(val.values());
    }
    if (val instanceof Date) {
      return val.toISOString();
    }
    if (typeof val === 'bigint') {
      return Number(val);
    }
    if (typeof val === 'function' || typeof val === 'undefined') {
      return null;
    }
    return val;
  };
  return JSON.parse(JSON.stringify(value, replacer));
}

let cachedZod = null;
async function getZod() {
  if (cachedZod) {
    return cachedZod;
  }
  const candidates = [
    path.join(vercelRoot, 'node_modules', 'zod', 'lib', 'index.mjs'),
    path.join(vercelRoot, 'packages', 'ai', 'node_modules', 'zod', 'lib', 'index.mjs'),
  ];
  let resolved = null;
  for (const candidate of candidates) {
    try {
      await fs.access(candidate);
      resolved = candidate;
      break;
    } catch (error) {
      // continue
    }
  }
  if (!resolved) {
    throw new Error('Could not locate zod in the workspace. Install dependencies first.');
  }
  const module = await import(pathToFileURL(resolved).href);
  const z = module.z ?? module.default;
  if (!z) {
    throw new Error('Failed to load zod module.');
  }
  cachedZod = z;
  return z;
}

function schemaToZod(z, schema) {
  if (!schema || schema.type !== 'object') {
    throw new Error('Only object schemas are currently supported for live scenarios.');
  }
  const required = new Set(schema.required ?? []);
  const shape = {};
  for (const [key, property] of Object.entries(schema.properties ?? {})) {
    let base;
    switch (property.type) {
      case 'string':
        base = Array.isArray(property.enum) ? z.enum(property.enum) : z.string();
        break;
      case 'integer':
        base = z.number().int();
        break;
      case 'number':
        base = z.number();
        break;
      case 'boolean':
        base = z.boolean();
        break;
      default:
        throw new Error(`Unsupported property type ${property.type} in schema.`);
    }
    shape[key] = required.has(key) ? base : base.optional();
  }
  return z.object(shape);
}

async function buildTools(definitions, executedToolsLog) {
  const z = await getZod();
  const tools = {};
  for (const def of definitions) {
    const schema = schemaToZod(z, def.schema);
    tools[def.name] = {
      description: def.description,
      parameters: schema,
      execute: def.execute
        ? async (args, options) => {
            const result = await def.execute(args, options);
            const normalized = normalizeToolResult(result);
            executedToolsLog.push({
              toolName: def.name,
              callId: options?.toolCallId ?? null,
              args,
              result: normalized,
            });
            if (normalized.type === 'error') {
              const error = new Error(normalized.message ?? 'Tool error');
              if (normalized.code) {
                error.code = normalized.code;
              }
              throw error;
            }
            return normalized.value;
          }
        : undefined,
    };
  }
  return tools;
}

function normalizeToolResult(result) {
  if (!result || typeof result !== 'object') {
    return { type: 'text', value: String(result ?? '') };
  }
  if ('type' in result) {
    switch (result.type) {
      case 'text':
        return { type: 'text', value: String(result.value ?? '') };
      case 'json':
        return { type: 'json', value: result.value };
      case 'error':
        return {
          type: 'error',
          message: result.message ?? 'Unknown tool error',
          code: result.code,
        };
      default:
        return { type: 'text', value: JSON.stringify(result.value ?? result) };
    }
  }
  return { type: 'json', value: result };
}

function convertScenarioConfig(definition) {
  if (definition.config.type === 'messages') {
    return definition.config.messages;
  }
  if (definition.config.type === 'prompt') {
    return [
      {
        role: 'user',
        content: [{ type: 'text', text: definition.config.prompt }],
      },
    ];
  }
  throw new Error(`Unsupported config type: ${definition.config.type}`);
}

function serializeToolExecutions(log) {
  return log.map(entry => ({
    toolName: entry.toolName,
    callId: entry.callId,
    args: entry.args,
    result: entry.result,
  }));
}

async function runLiveScenario(name) {
  const openaiEntry = await resolveOpenAIEntry();
  await ensureDistExists(openaiEntry);
  const scenarios = createScenarioDefinitions();
  const definition = scenarios[name];
  if (!definition) {
    throw new Error(`Unknown scenario '${name}'.`);
  }

  const openaiKey = readOpenAIKey();
  const { createOpenAI } = await import(pathToFileURL(openaiEntry).href);
  const { generateText } = await import(pathToFileURL(distEntry).href);

  const executedToolsLog = [];
  const vercelTools = await buildTools(definition.tools, executedToolsLog);
  const openai = createOpenAI({ apiKey: openaiKey });
  const modelId = definition.model ?? 'openai:gpt-4o-mini';
  const model = openai(modelId); // returns LanguageModel

  const messages = convertScenarioConfig(definition);

  const result = await generateText({
    model,
    tools: vercelTools,
    messages,
    maxSteps: definition.maxSteps,
    toolChoice: definition.toolChoice,
    temperature: 0,
    seed: parseInt(process.env.VERCEL_PARITY_SEED ?? '42', 10),
  });

  return {
    name,
    model: modelId,
    config: definition.config,
    maxSteps: definition.maxSteps,
    toolChoice: definition.toolChoice ?? null,
    toolSchemas: definition.tools.map(tool => ({
      name: tool.name,
      description: tool.description,
      schema: tool.schema,
    })),
    toolExecutions: serializeToolExecutions(executedToolsLog),
    vercel: { result: toSerializable(result) },
  };
}

async function main() {
  const args = process.argv.slice(2).filter(arg => !arg.startsWith('--'));
  if (args.length !== 1) {
    console.error('Usage: node run-live-scenario.mjs <scenario-name>');
    process.exit(1);
  }
  try {
    const payload = await runLiveScenario(args[0]);
    process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
  } catch (error) {
    console.error(error);
    process.exitCode = 1;
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}

export { runLiveScenario };
