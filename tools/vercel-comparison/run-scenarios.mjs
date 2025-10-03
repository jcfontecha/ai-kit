import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createScenarioDefinitions } from './scenarios.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '..', '..');
const vercelRoot = path.join(repoRoot, 'vercel-sdk');
const distEntry = path.join(vercelRoot, 'packages', 'ai', 'dist', 'index.mjs');

async function ensureDistExists() {
  try {
    await fs.access(distEntry);
  } catch (error) {
    throw new Error(
      `Vercel AI SDK dist not found at ${distEntry}. Run \`pnpm --filter ai build\` inside vercel-sdk/ first.`,
    );
  }
}

let cachedZod = null;

async function getZod() {
  if (cachedZod) {
    return cachedZod;
  }

  const candidateEntries = [
    path.join(vercelRoot, 'node_modules', 'zod', 'lib', 'index.mjs'),
    path.join(vercelRoot, 'packages', 'ai', 'node_modules', 'zod', 'lib', 'index.mjs'),
  ];

  let resolvedEntry = null;
  for (const candidate of candidateEntries) {
    try {
      await fs.access(candidate);
      resolvedEntry = candidate;
      break;
    } catch (error) {
      // continue checking other candidates
    }
  }

  if (!resolvedEntry) {
    throw new Error(
      `Could not locate zod. Checked: ${candidateEntries.join(', ')}. Ensure dependencies are installed with pnpm install.`,
    );
  }

  const module = await import(pathToFileURL(resolvedEntry).href);
  const z = module.z ?? module.default;
  if (!z) {
    throw new Error('Failed to load zod module.');
  }

  cachedZod = z;
  return z;
}

function schemaToZod(z, schema) {
  if (!schema || schema.type !== 'object') {
    throw new Error('Only object schemas are supported in fixtures.');
  }

  const shape = {};
  const required = new Set(schema.required ?? []);

  for (const [key, property] of Object.entries(schema.properties ?? {})) {
    let base;
    switch (property.type) {
      case 'string':
        if (Array.isArray(property.enum)) {
          base = z.enum(property.enum);
        } else {
          base = z.string();
        }
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
              const error = new Error(normalized.message);
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

function buildModel(responses) {
  let index = 0;
  const recordedCalls = [];
  const cloned = responses.map(response => structuredClone(response));

  const model = {
    specificationVersion: 'v1',
    provider: 'mock-provider',
    modelId: 'mock-model',
    supportsUrl: undefined,
    doStream: undefined,
    defaultObjectGenerationMode: undefined,
    supportsStructuredOutputs: undefined,
    async doGenerate({ prompt, mode }) {
      if (index >= cloned.length) {
        throw new Error('No more mock responses available for scenario.');
      }

      const response = structuredClone(cloned[index]);
      recordedCalls.push({
        step: index + 1,
        mode,
        prompt,
      });
      index += 1;
      return response;
    },
  };

  Object.defineProperty(model, '__recordedCalls', {
    value: recordedCalls,
    enumerable: false,
    configurable: false,
  });

  return model;
}

function parseArgs(rawArgs) {
  try {
    return JSON.parse(rawArgs);
  } catch (error) {
    return null;
  }
}

function serializeToolCall(call) {
  return {
    toolCallId: call.toolCallId,
    toolName: call.toolName,
    arguments: parseArgs(call.args),
    rawArguments: call.args,
  };
}

function serializeUsage(usage) {
  if (!usage) return null;
  return {
    promptTokens: usage.promptTokens,
    completionTokens: usage.completionTokens,
    totalTokens: usage.totalTokens,
  };
}

function serializeModelResponse(response) {
  return {
    text: response.text,
    finishReason: response.finishReason,
    toolCalls: response.toolCalls?.map(serializeToolCall) ?? [],
    usage: serializeUsage(response.usage),
    response: response.response
      ? {
          id: response.response.id,
          timestamp: response.response.timestamp,
          modelId: response.response.modelId,
        }
      : null,
    rawCall: response.rawCall ?? null,
  };
}

function serializeError(error) {
  if (!error || typeof error !== 'object') {
    return { message: String(error) };
  }
  const plain = {
    name: error.name,
    message: error.message,
    stack: error.stack,
  };
  for (const key of Object.keys(error)) {
    plain[key] = error[key];
  }
  return plain;
}

function replacer(key, value) {
  if (value instanceof Map) {
    return Object.fromEntries(value.entries());
  }
  if (value instanceof Set) {
    return Array.from(value.values());
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (typeof value === 'bigint') {
    return Number(value);
  }
  return value;
}

function toSerializable(value) {
  return JSON.parse(JSON.stringify(value, replacer));
}

function convertToolSchemas(definitions) {
  return definitions.map(def => ({
    name: def.name,
    description: def.description,
    schema: def.schema,
  }));
}

function convertMessages(config) {
  if (config.type === 'messages') {
    return structuredClone(config.messages);
  }
  if (config.type === 'prompt') {
    return [
      {
        role: 'user',
        content: [{ type: 'text', text: config.prompt }],
      },
    ];
  }
  throw new Error('Unsupported scenario config type.');
}

async function runScenario({
  name,
  definition,
  generateText,
}) {
  const executedToolsLog = [];
  const tools = await buildTools(definition.tools, executedToolsLog);
  const model = buildModel(definition.modelResponses);

  let result = null;
  let error = null;

  try {
    result = await generateText({
      model,
      tools,
      messages: convertMessages(definition.config),
      toolChoice: definition.toolChoice,
      maxSteps: definition.maxSteps,
    });
  } catch (err) {
    error = err;
  }

  const fallbackVercel = error
    ? { error: serializeError(error) }
    : { result: toSerializable(result) };

  return {
    name,
    description: definition.description,
    config: definition.config,
    maxSteps: definition.maxSteps,
    toolChoice: definition.toolChoice ?? null,
    toolSchemas: convertToolSchemas(definition.tools),
    modelResponses: definition.modelResponses.map(serializeModelResponse),
    recordedModelCalls: model.__recordedCalls,
    toolExecutions: executedToolsLog.map(log => ({
      toolName: log.toolName,
      callId: log.callId,
      args: log.args,
      result: log.result,
    })),
    vercel: definition.expectedVercel
      ? toSerializable(definition.expectedVercel)
      : fallbackVercel,
  };
}

async function main() {
  await ensureDistExists();
  const { generateText } = await import(pathToFileURL(distEntry).href);

  const scenarios = createScenarioDefinitions();
  const requested = process.argv.slice(2).filter(arg => !arg.startsWith('--'));
  const names = requested.length > 0 ? requested : Object.keys(scenarios);

  const missing = names.filter(name => !scenarios[name]);
  if (missing.length > 0) {
    throw new Error(`Unknown scenario(s): ${missing.join(', ')}`);
  }

  const outputDir = path.join(repoRoot, 'Tests', 'Fixtures', 'VercelToolParity');
  await fs.mkdir(outputDir, { recursive: true });

  for (const name of names) {
    const fixture = await runScenario({
      name,
      definition: scenarios[name],
      generateText,
    });

    const filePath = path.join(outputDir, `${name}.json`);
    await fs.writeFile(filePath, `${JSON.stringify(fixture, null, 2)}\n`, 'utf8');
    console.log(`wrote ${path.relative(repoRoot, filePath)}`);
  }
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
