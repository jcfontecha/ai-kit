const BASE_TIMESTAMP = new Date('2024-01-01T00:00:00Z');

function iso(offsetSeconds) {
  return new Date(BASE_TIMESTAMP.getTime() + offsetSeconds * 1000).toISOString();
}

function createUsage({ promptTokens, completionTokens }) {
  return {
    promptTokens,
    completionTokens,
    totalTokens: promptTokens + completionTokens,
  };
}

function buildToolSchema({ description, properties, required = [] }) {
  return {
    type: 'object',
    description,
    properties,
    required,
    additionalProperties: false,
  };
}

function toolCall({ id, name, args }) {
  return {
    toolCallType: 'function',
    toolCallId: id,
    toolName: name,
    args: JSON.stringify(args),
  };
}

function baseResponse({
  id,
  index,
  text = '',
  finishReason = 'stop',
  toolCalls,
  usage,
  providerMetadata = {},
  rawPromptLabel,
}) {
  return {
    rawCall: {
      rawPrompt: rawPromptLabel ?? `scenario-step-${index + 1}`,
      rawSettings: {},
    },
    response: {
      id,
        timestamp: new Date(iso(index)),
      modelId: 'mock-model',
    },
    rawResponse: undefined,
    text,
    finishReason,
    usage: usage ?? createUsage({ promptTokens: 10, completionTokens: 5 }),
    toolCalls,
    providerMetadata,
  };
}

export function createScenarioDefinitions() {
  return {
    'auto-single-tool-call': {
      description:
        'Single tool call automatically executed and incorporated into final assistant message.',
      model: 'gpt-4o-mini',
      config: {
        type: 'messages',
        messages: [
          {
            role: 'user',
            content: [
              {
                type: 'text',
                text: 'What is the weather in Boston, MA today? Please respond in Fahrenheit.',
              },
            ],
          },
        ],
      },
      maxSteps: 3,
      toolChoice: 'auto',
      tools: [
        {
          name: 'get_weather',
          description: 'Fetches the current weather for a city.',
          schema: buildToolSchema({
            description: 'Weather lookup parameters',
            required: ['location'],
            properties: {
              location: {
                type: 'string',
                description: 'City and state to look up',
              },
              unit: {
                type: 'string',
                enum: ['celsius', 'fahrenheit'],
                description: 'Preferred unit for the response',
              },
            },
          }),
          execute: ({ location, unit = 'fahrenheit' }) => ({
            type: 'text',
            value: `Weather in ${location}: 72°${unit === 'celsius' ? 'C' : 'F'}, Sunny`,
          }),
        },
      ],
      modelResponses: [
        baseResponse({
          id: 'resp-auto-1',
          index: 0,
          text: 'I can look that up using my weather tool.',
          finishReason: 'tool-calls',
          toolCalls: [
            toolCall({
              id: 'call-1',
              name: 'get_weather',
              args: { location: 'Boston, MA', unit: 'fahrenheit' },
            }),
          ],
          usage: createUsage({ promptTokens: 28, completionTokens: 8 }),
          rawPromptLabel: 'auto-single-step-1',
        }),
        baseResponse({
          id: 'resp-auto-2',
          index: 1,
          text:
            'According to the latest data, the weather in Boston, MA is 72°F and sunny. Enjoy your day!',
          finishReason: 'stop',
          usage: createUsage({ promptTokens: 12, completionTokens: 64 }),
          rawPromptLabel: 'auto-single-step-2',
        }),
      ],
    },
    'multi-tool-handoff': {
      description:
        'Two sequential tool calls where the model first searches notes before fetching weather details.',
      model: 'gpt-4o-mini',
      config: {
        type: 'prompt',
        prompt:
          'You are an assistant that can search travel notes and fetch weather forecasts. Find the latest trip notes for Kyoto and decide if the user should bring an umbrella.',
      },
      maxSteps: 4,
      toolChoice: 'auto',
      tools: [
        {
          name: 'search_notes',
          description: 'Search indexed travel notes.',
          schema: buildToolSchema({
            description: 'Search query',
            required: ['query'],
            properties: {
              query: {
                type: 'string',
                description: 'Keywords to search for in notes',
              },
            },
          }),
          execute: ({ query }) => ({
            type: 'json',
            value: {
              hits: [
                {
                  noteId: 'note-kyoto-2023',
                  summary: 'Kyoto in May: light showers expected in afternoons.',
                },
              ],
            },
          }),
        },
        {
          name: 'get_weather',
          description: 'Fetch weather forecast for a destination.',
          schema: buildToolSchema({
            description: 'Weather lookup parameters',
            required: ['location'],
            properties: {
              location: {
                type: 'string',
                description: 'City name to fetch forecast for',
              },
              timeframe: {
                type: 'string',
                enum: ['today', 'tomorrow', 'week'],
              },
            },
          }),
          execute: ({ location, timeframe = 'today' }) => ({
            type: 'json',
            value: {
              location,
              timeframe,
              forecast: timeframe === 'week'
                ? 'Mixed clouds with occasional showers. Pack a light rain jacket.'
                : 'Light showers expected later in the day. Bring an umbrella.',
            },
          }),
        },
      ],
      modelResponses: [
        baseResponse({
          id: 'resp-multi-1',
          index: 0,
          text:
            'First, I will look up your notes related to Kyoto to understand past recommendations.',
          finishReason: 'tool-calls',
          toolCalls: [
            toolCall({
              id: 'call-1',
              name: 'search_notes',
              args: { query: 'Kyoto umbrella packing list' },
            }),
          ],
          usage: createUsage({ promptTokens: 52, completionTokens: 24 }),
          rawPromptLabel: 'multi-tool-step-1',
        }),
        baseResponse({
          id: 'resp-multi-2',
          index: 1,
          text:
            'Based on your notes, I will now check the upcoming weather for Kyoto.',
          finishReason: 'tool-calls',
          toolCalls: [
            toolCall({
              id: 'call-2',
              name: 'get_weather',
              args: { location: 'Kyoto, Japan', timeframe: 'week' },
            }),
          ],
          usage: createUsage({ promptTokens: 34, completionTokens: 18 }),
          rawPromptLabel: 'multi-tool-step-2',
        }),
        baseResponse({
          id: 'resp-multi-3',
          index: 2,
          text:
            'Your notes mention afternoon showers in Kyoto. The latest weekly forecast also predicts mixed clouds with occasional rain. You should bring a compact umbrella and a light waterproof jacket.',
          finishReason: 'stop',
          usage: createUsage({ promptTokens: 48, completionTokens: 72 }),
          rawPromptLabel: 'multi-tool-step-3',
        }),
      ],
    },
    'tool-json-result': {
      description:
        'Tool returns structured JSON that should be surfaced consistently across SDKs.',
      model: 'gpt-4o-mini',
      config: {
        type: 'messages',
        messages: [
          {
            role: 'user',
            content: [
              {
                type: 'text',
                text: 'Generate a grocery list for a vegan dinner party for four people.',
              },
            ],
          },
        ],
      },
      maxSteps: 3,
      toolChoice: 'auto',
      tools: [
        {
          name: 'plan_menu',
          description: 'Creates a menu and shopping list.',
          schema: buildToolSchema({
            description: 'Menu planning inputs',
            required: ['diet', 'servings'],
            properties: {
              diet: {
                type: 'string',
                enum: ['vegan', 'vegetarian', 'omnivore'],
              },
              servings: {
                type: 'integer',
                description: 'Number of people to serve',
              },
            },
          }),
          execute: ({ diet, servings }) => ({
            type: 'json',
            value: {
              diet,
              servings,
              courses: [
                {
                  name: 'Roasted Cauliflower Steak',
                  ingredients: ['cauliflower', 'olive oil', 'smoked paprika', 'salt'],
                },
                {
                  name: 'Quinoa Salad',
                  ingredients: ['quinoa', 'cherry tomatoes', 'cucumber', 'lemon'],
                },
              ],
              shoppingList: [
                { item: 'Cauliflower heads', quantity: Math.ceil(servings / 2) },
                { item: 'Quinoa (cups)', quantity: Math.ceil((servings * 0.75) * 10) / 10 },
                { item: 'Fresh herbs bundle', quantity: 1 },
              ],
            },
          }),
        },
      ],
      modelResponses: [
        baseResponse({
          id: 'resp-json-1',
          index: 0,
          text: 'Let me design a menu using the planning tool.',
          finishReason: 'tool-calls',
          toolCalls: [
            toolCall({
              id: 'call-1',
              name: 'plan_menu',
              args: { diet: 'vegan', servings: 4 },
            }),
          ],
          usage: createUsage({ promptTokens: 30, completionTokens: 12 }),
          rawPromptLabel: 'tool-json-step-1',
        }),
        baseResponse({
          id: 'resp-json-2',
          index: 1,
          text:
            'Here is a tailored vegan dinner party menu complete with ingredients and shopping list.',
          finishReason: 'stop',
          usage: createUsage({ promptTokens: 16, completionTokens: 80 }),
          rawPromptLabel: 'tool-json-step-2',
        }),
      ],
    },
    'tool-execution-error': {
      description:
        'Tool execution failure should surface the same structured error as the Vercel SDK.',
      model: 'gpt-4o-mini',
      config: {
        type: 'messages',
        messages: [
          {
            role: 'user',
            content: [
              {
                type: 'text',
                text: 'Check the status of the database migration job JOB-77.',
              },
            ],
          },
        ],
      },
      maxSteps: 2,
      toolChoice: 'auto',
      tools: [
        {
          name: 'get_migration_status',
          description: 'Returns the status of a long running migration.',
          schema: buildToolSchema({
            description: 'Migration status lookup',
            required: ['jobId'],
            properties: {
              jobId: {
                type: 'string',
                description: 'Identifier of the migration job',
              },
            },
          }),
          execute: ({ jobId }) => {
            if (jobId === 'JOB-77') {
              const error = new Error('Migration job timed out contacting shard-3');
              error.code = 'ETIMEDOUT';
              throw error;
            }
            return { type: 'text', value: `Job ${jobId} completed successfully.` };
          },
        },
      ],
      modelResponses: [
        baseResponse({
          id: 'resp-error-1',
          index: 0,
          text: 'I will query the migration tool for the latest status.',
          finishReason: 'tool-calls',
          toolCalls: [
            toolCall({
              id: 'call-1',
              name: 'get_migration_status',
              args: { jobId: 'JOB-77' },
            }),
          ],
          usage: createUsage({ promptTokens: 22, completionTokens: 10 }),
          rawPromptLabel: 'tool-error-step-1',
        }),
      ],
    },
    'sequential-image-tools': {
      description:
        'Two generate_and_show_image tool calls executed before the assistant sends a final message.',
      model: 'gpt-4o-mini',
      config: {
        type: 'prompt',
        prompt:
          'Please create one image of a dog and one image of a cat. Call generate_and_show_image for each and only send a final reply after both succeed, including attachment links.',
      },
      maxSteps: 4,
      toolChoice: 'auto',
      tools: [
        {
          name: 'generate_and_show_image',
          description: 'Render an image and return an attachment identifier.',
          schema: buildToolSchema({
            description: 'Image generation parameters',
            required: ['prompt'],
            properties: {
              prompt: {
                type: 'string',
                description: 'A short description of the desired image',
              },
            },
          }),
          execute: ({ prompt }) => ({
            type: 'json',
            value: {
              attachments: [prompt && prompt.toLowerCase().includes('cat') ? 'attachment_cat_image' : 'attachment_dog_image'],
              success: true,
              prompt,
            },
          }),
        },
      ],
      modelResponses: [
        baseResponse({
          id: 'resp-img-1',
          index: 0,
          text: 'I will generate those images now.',
          finishReason: 'tool-calls',
          toolCalls: [
            toolCall({
              id: 'call-img-1',
              name: 'generate_and_show_image',
              args: { prompt: 'a friendly dog playing in a park' },
            }),
            toolCall({
              id: 'call-img-2',
              name: 'generate_and_show_image',
              args: { prompt: 'a curious cat sitting on a windowsill' },
            }),
          ],
          usage: createUsage({ promptTokens: 48, completionTokens: 14 }),
          rawPromptLabel: 'sequential-image-step-1',
        }),
        baseResponse({
          id: 'resp-img-2',
          index: 1,
          text:
            'Here are the images you requested.\n<attachment:attachment_dog_image>\n<attachment:attachment_cat_image>',
          finishReason: 'stop',
          usage: createUsage({ promptTokens: 16, completionTokens: 44 }),
          rawPromptLabel: 'sequential-image-step-2',
        }),
      ],
      toolExecutions: [
        {
          toolName: 'generate_and_show_image',
          callId: 'call-img-1',
          args: { prompt: 'a friendly dog playing in a park' },
          result: {
            type: 'json',
            value: {
              attachments: ['attachment_dog_image'],
              success: true,
              prompt: 'a friendly dog playing in a park',
            },
          },
        },
        {
          toolName: 'generate_and_show_image',
          callId: 'call-img-2',
          args: { prompt: 'a curious cat sitting on a windowsill' },
          result: {
            type: 'json',
            value: {
              attachments: ['attachment_cat_image'],
              success: true,
              prompt: 'a curious cat sitting on a windowsill',
            },
          },
        },
      ],
      expectedVercel: {
        result: {
          text:
            'Here are the images you requested.\n<attachment:attachment_dog_image>\n<attachment:attachment_cat_image>',
          files: [],
          reasoningDetails: [],
          toolCalls: [],
          toolResults: [],
          finishReason: 'stop',
          usage: {
            promptTokens: 64,
            completionTokens: 58,
            totalTokens: 122,
          },
          response: {
            id: 'resp-img-2',
            timestamp: '2024-01-01T00:00:02.000Z',
            modelId: 'mock-model',
            messages: [
              {
                role: 'assistant',
                content: [
                  {
                    type: 'text',
                    text: 'I will generate those images now.',
                  },
                  {
                    type: 'tool-call',
                    toolCallId: 'call-img-1',
                    toolName: 'generate_and_show_image',
                    args: { prompt: 'a friendly dog playing in a park' },
                  },
                  {
                    type: 'tool-call',
                    toolCallId: 'call-img-2',
                    toolName: 'generate_and_show_image',
                    args: { prompt: 'a curious cat sitting on a windowsill' },
                  },
                ],
                id: 'msg-img-step-1',
              },
              {
                role: 'tool',
                content: [
                  {
                    type: 'tool-result',
                    toolCallId: 'call-img-1',
                    toolName: 'generate_and_show_image',
                    result: {
                      attachments: ['attachment_dog_image'],
                      success: true,
                      prompt: 'a friendly dog playing in a park',
                    },
                  },
                  {
                    type: 'tool-result',
                    toolCallId: 'call-img-2',
                    toolName: 'generate_and_show_image',
                    result: {
                      attachments: ['attachment_cat_image'],
                      success: true,
                      prompt: 'a curious cat sitting on a windowsill',
                    },
                  },
                ],
                id: 'msg-img-tools',
              },
              {
                role: 'assistant',
                content: [
                  {
                    type: 'text',
                    text:
                      'Here are the images you requested.\n<attachment:attachment_dog_image>\n<attachment:attachment_cat_image>',
                  },
                ],
                id: 'msg-img-final',
              },
            ],
          },
          steps: [
            {
              stepType: 'initial',
              toolCalls: [
                {
                  toolCallId: 'call-img-1',
                  toolName: 'generate_and_show_image',
                  args: { prompt: 'a friendly dog playing in a park' },
                },
                {
                  toolCallId: 'call-img-2',
                  toolName: 'generate_and_show_image',
                  args: { prompt: 'a curious cat sitting on a windowsill' },
                },
              ],
              toolResults: [
                {
                  toolCallId: 'call-img-1',
                  toolName: 'generate_and_show_image',
                  result: {
                    attachments: ['attachment_dog_image'],
                    success: true,
                    prompt: 'a friendly dog playing in a park',
                  },
                },
                {
                  toolCallId: 'call-img-2',
                  toolName: 'generate_and_show_image',
                  result: {
                    attachments: ['attachment_cat_image'],
                    success: true,
                    prompt: 'a curious cat sitting on a windowsill',
                  },
                },
              ],
              text: 'I will generate those images now.',
            },
            {
              stepType: 'tool-result',
              toolCalls: [],
              toolResults: [],
              text:
                'Here are the images you requested.\n<attachment:attachment_dog_image>\n<attachment:attachment_cat_image>',
            },
          ],
        },
        error: null,
      },
    },
    'interleaved-image-tools': {
      description:
        'Assistant sends partial text between image tool calls to verify ordering of tool results and subsequent tool calls.',
      model: 'gpt-4o-mini',
      config: {
        type: 'prompt',
        prompt:
          'Create one image of a sunrise and then another of a sunset. After the first tool result, tell the user it is attached before calling the tool again. Include attachment references in the final response.',
      },
      maxSteps: 5,
      toolChoice: 'auto',
      tools: [
        {
          name: 'generate_and_show_image',
          description: 'Render an image and return an attachment identifier.',
          schema: buildToolSchema({
            description: 'Image generation parameters',
            required: ['prompt'],
            properties: {
              prompt: {
                type: 'string',
                description: 'A short description of the desired image',
              },
            },
          }),
          execute: ({ prompt }) => ({
            type: 'json',
            value: {
              attachments: [prompt && prompt.toLowerCase().includes('sunset') ? 'attachment_sunset_image' : 'attachment_sunrise_image'],
              success: true,
              prompt,
            },
          }),
        },
      ],
      modelResponses: [
        baseResponse({
          id: 'resp-inter-1',
          index: 0,
          text: 'Starting on the sunrise illustration now.',
          finishReason: 'tool-calls',
          toolCalls: [
            toolCall({
              id: 'call-sunrise',
              name: 'generate_and_show_image',
              args: { prompt: 'a sunrise over the mountains in watercolor style' },
            }),
          ],
          usage: createUsage({ promptTokens: 42, completionTokens: 12 }),
          rawPromptLabel: 'interleaved-step-1',
        }),
        baseResponse({
          id: 'resp-inter-2',
          index: 1,
          text: 'The sunrise image is attached. Creating the sunset illustration next.',
          finishReason: 'tool-calls',
          toolCalls: [
            toolCall({
              id: 'call-sunset',
              name: 'generate_and_show_image',
              args: { prompt: 'a sunset over the ocean with vibrant colors' },
            }),
          ],
          usage: createUsage({ promptTokens: 26, completionTokens: 22 }),
          rawPromptLabel: 'interleaved-step-2',
        }),
        baseResponse({
          id: 'resp-inter-3',
          index: 2,
          text:
            'Both images are ready for you.\n<attachment:attachment_sunrise_image>\n<attachment:attachment_sunset_image>',
          finishReason: 'stop',
          usage: createUsage({ promptTokens: 20, completionTokens: 38 }),
          rawPromptLabel: 'interleaved-step-3',
        }),
      ],
      toolExecutions: [
        {
          toolName: 'generate_and_show_image',
          callId: 'call-sunrise',
          args: { prompt: 'a sunrise over the mountains in watercolor style' },
          result: {
            type: 'json',
            value: {
              attachments: ['attachment_sunrise_image'],
              success: true,
              prompt: 'a sunrise over the mountains in watercolor style',
            },
          },
        },
        {
          toolName: 'generate_and_show_image',
          callId: 'call-sunset',
          args: { prompt: 'a sunset over the ocean with vibrant colors' },
          result: {
            type: 'json',
            value: {
              attachments: ['attachment_sunset_image'],
              success: true,
              prompt: 'a sunset over the ocean with vibrant colors',
            },
          },
        },
      ],
      expectedVercel: {
        result: {
          text:
            'Both images are ready for you.\n<attachment:attachment_sunrise_image>\n<attachment:attachment_sunset_image>',
          files: [],
          reasoningDetails: [],
          toolCalls: [],
          toolResults: [],
          finishReason: 'stop',
          usage: {
            promptTokens: 88,
            completionTokens: 72,
            totalTokens: 160,
          },
          response: {
            id: 'resp-inter-3',
            timestamp: '2024-01-01T00:00:03.000Z',
            modelId: 'mock-model',
            messages: [
              {
                role: 'assistant',
                content: [
                  {
                    type: 'text',
                    text: 'Starting on the sunrise illustration now.',
                  },
                  {
                    type: 'tool-call',
                    toolCallId: 'call-sunrise',
                    toolName: 'generate_and_show_image',
                    args: {
                      prompt: 'a sunrise over the mountains in watercolor style',
                    },
                  },
                ],
                id: 'msg-inter-step-1',
              },
              {
                role: 'tool',
                content: [
                  {
                    type: 'tool-result',
                    toolCallId: 'call-sunrise',
                    toolName: 'generate_and_show_image',
                    result: {
                      attachments: ['attachment_sunrise_image'],
                      success: true,
                      prompt: 'a sunrise over the mountains in watercolor style',
                    },
                  },
                ],
                id: 'msg-inter-tool-1',
              },
              {
                role: 'assistant',
                content: [
                  {
                    type: 'text',
                    text: 'The sunrise image is attached. Creating the sunset illustration next.',
                  },
                  {
                    type: 'tool-call',
                    toolCallId: 'call-sunset',
                    toolName: 'generate_and_show_image',
                    args: {
                      prompt: 'a sunset over the ocean with vibrant colors',
                    },
                  },
                ],
                id: 'msg-inter-step-2',
              },
              {
                role: 'tool',
                content: [
                  {
                    type: 'tool-result',
                    toolCallId: 'call-sunset',
                    toolName: 'generate_and_show_image',
                    result: {
                      attachments: ['attachment_sunset_image'],
                      success: true,
                      prompt: 'a sunset over the ocean with vibrant colors',
                    },
                  },
                ],
                id: 'msg-inter-tool-2',
              },
              {
                role: 'assistant',
                content: [
                  {
                    type: 'text',
                    text:
                      'Both images are ready for you.\n<attachment:attachment_sunrise_image>\n<attachment:attachment_sunset_image>',
                  },
                ],
                id: 'msg-inter-final',
              },
            ],
          },
          steps: [
            {
              stepType: 'initial',
              toolCalls: [
                {
                  toolCallId: 'call-sunrise',
                  toolName: 'generate_and_show_image',
                  args: {
                    prompt: 'a sunrise over the mountains in watercolor style',
                  },
                },
              ],
              toolResults: [
                {
                  toolCallId: 'call-sunrise',
                  toolName: 'generate_and_show_image',
                  result: {
                    attachments: ['attachment_sunrise_image'],
                    success: true,
                    prompt: 'a sunrise over the mountains in watercolor style',
                  },
                },
              ],
              text: 'Starting on the sunrise illustration now.',
            },
            {
              stepType: 'tool-result',
              toolCalls: [
                {
                  toolCallId: 'call-sunset',
                  toolName: 'generate_and_show_image',
                  args: {
                    prompt: 'a sunset over the ocean with vibrant colors',
                  },
                },
              ],
              toolResults: [
                {
                  toolCallId: 'call-sunset',
                  toolName: 'generate_and_show_image',
                  result: {
                    attachments: ['attachment_sunset_image'],
                    success: true,
                    prompt: 'a sunset over the ocean with vibrant colors',
                  },
                },
              ],
              text: 'The sunrise image is attached. Creating the sunset illustration next.',
            },
            {
              stepType: 'tool-result',
              toolCalls: [],
              toolResults: [],
              text:
                'Both images are ready for you.\n<attachment:attachment_sunrise_image>\n<attachment:attachment_sunset_image>',
            },
          ],
        },
        error: null,
      },
    },
    'preface-text-and-image': {
      description:
        'Assistant offers descriptive text, triggers an image tool, then follows up with another suggestion.',
      model: 'gpt-4o-mini',
      config: {
        type: 'messages',
        messages: [
          {
            role: 'user',
            content: [
              {
                type: 'text',
                text:
                  'Please describe huskies pulling a sled in the snow, generate the image, then suggest a new scene.',
              },
            ],
          },
        ],
      },
      maxSteps: 4,
      toolChoice: 'auto',
      tools: [
        {
          name: 'generate_and_show_image',
          description: 'Render an image and return an attachment identifier.',
          schema: buildToolSchema({
            description: 'Image generation parameters',
            required: ['prompt'],
            properties: {
              prompt: {
                type: 'string',
                description: 'Description of the image to create',
              },
              num_images: {
                type: 'integer',
              },
            },
          }),
          execute: ({ prompt, num_images = 1 }) => ({
            type: 'json',
            value: {
              success: true,
              count: num_images,
              attachmentIds: ['attachment_husky_sled_image'],
            },
          }),
        },
      ],
      modelResponses: [
        baseResponse({
          id: 'resp-preface-1',
          index: 0,
          text:
            'Imagine the huskies charging across the glistening snow — I will fetch that image for you now.',
          finishReason: 'tool-calls',
          toolCalls: [
            toolCall({
              id: 'call-preface-image',
              name: 'generate_and_show_image',
              args: { prompt: 'Huskies pulling a sled through a snowy forest.', num_images: 1 },
            }),
          ],
          usage: createUsage({ promptTokens: 46, completionTokens: 22 }),
          rawPromptLabel: 'preface-step-1',
        }),
        baseResponse({
          id: 'resp-preface-2',
          index: 1,
          text:
            'How about we follow that with a malamute resting by a cozy fireplace?',
          finishReason: 'stop',
          usage: createUsage({ promptTokens: 20, completionTokens: 28 }),
          rawPromptLabel: 'preface-step-2',
        }),
      ],
      toolExecutions: [
        {
          toolName: 'generate_and_show_image',
          callId: 'call-preface-image',
          args: {
            prompt: 'Huskies pulling a sled through a snowy forest.',
            num_images: 1,
          },
          result: {
            type: 'json',
            value: {
              success: true,
              count: 1,
              attachmentIds: ['attachment_husky_sled_image'],
            },
          },
        },
      ],
      expectedVercel: {
        result: {
          text:
            'How about we follow that with a malamute resting by a cozy fireplace?',
          files: [],
          reasoningDetails: [],
          toolCalls: [],
          toolResults: [],
          finishReason: 'stop',
          usage: {
            promptTokens: 66,
            completionTokens: 50,
            totalTokens: 116,
          },
          response: {
            id: 'resp-preface-2',
            timestamp: '2024-01-01T00:00:02.000Z',
            modelId: 'mock-model',
            messages: [
              {
                role: 'assistant',
                content: [
                  {
                    type: 'text',
                    text:
                      'Imagine the huskies charging across the glistening snow — I will fetch that image for you now.',
                  },
                  {
                    type: 'tool-call',
                    toolCallId: 'call-preface-image',
                    toolName: 'generate_and_show_image',
                    args: {
                      prompt: 'Huskies pulling a sled through a snowy forest.',
                      num_images: 1,
                    },
                  },
                ],
                id: 'msg-preface-step-1',
              },
              {
                role: 'tool',
                content: [
                  {
                    type: 'tool-result',
                    toolCallId: 'call-preface-image',
                    toolName: 'generate_and_show_image',
                    result: {
                      success: true,
                      count: 1,
                      attachmentIds: ['attachment_husky_sled_image'],
                    },
                  },
                ],
                id: 'msg-preface-tool',
              },
              {
                role: 'assistant',
                content: [
                  {
                    type: 'text',
                    text:
                      'How about we follow that with a malamute resting by a cozy fireplace?',
                  },
                ],
                id: 'msg-preface-step-2',
              },
            ],
          },
          steps: [
            {
              stepType: 'initial',
              toolCalls: [
                {
                  toolCallId: 'call-preface-image',
                  toolName: 'generate_and_show_image',
                  args: {
                    prompt: 'Huskies pulling a sled through a snowy forest.',
                    num_images: 1,
                  },
                },
              ],
              toolResults: [],
              text:
                'Imagine the huskies charging across the glistening snow — I will fetch that image for you now.',
            },
            {
              stepType: 'tool-result',
              toolCalls: [],
              toolResults: [
                {
                  toolCallId: 'call-preface-image',
                  toolName: 'generate_and_show_image',
                  result: {
                    success: true,
                    count: 1,
                    attachmentIds: ['attachment_husky_sled_image'],
                  },
                },
              ],
              text: null,
            },
            {
              stepType: 'tool-result',
              toolCalls: [],
              toolResults: [],
              text:
                'How about we follow that with a malamute resting by a cozy fireplace?',
            },
          ],
        },
        error: null,
      },
    },
  };
}
