#!/usr/bin/env node
/**
 * MCP Bridge for "MCP Browser Tools" Chrome extension
 *
 * 角色: WebSocket 服务端 (监听 23456，等待扩展连接)
 *       + MCP stdio 服务端 (与 Cursor 通信)
 *
 * Chrome 扩展 (mddaedengnmgbkbahkhkcmpkfiainkic) 是一个 WebSocket 客户端，
 * 主动连接到 ws://localhost:23456。我们作为服务端接收它的连接，然后
 * 把它提供的功能暴露为 Cursor 可调用的 MCP 工具。
 *
 * 用法:
 *   node mcp-bridge.js [ws-port]
 *
 * 默认端口: 23456 (可用 WS_PORT 或命令行参数覆盖)
 */

const http = require('http');
const { WebSocketServer } = require('ws');
const { Server } = require('@modelcontextprotocol/sdk/server/index.js');
const { StdioServerTransport } = require('@modelcontextprotocol/sdk/server/stdio.js');
const {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} = require('@modelcontextprotocol/sdk/types.js');

const WS_PORT = parseInt(process.env.WS_PORT || process.argv[2] || '23456', 10);

// ---------------------------------------------------------------------------
// WebSocket 服务端 (Chrome 扩展连接)
// ---------------------------------------------------------------------------
let extensionWs = null;
let requestIdCounter = 1;
const pending = new Map(); // requestId -> { resolve, reject, timer }

// 记录最近一次的扩展推送 (例如连接断开事件)
let lastExtensionMessage = null;

function logErr(msg) {
  process.stderr.write(`[mcp-bridge] ${msg}\n`);
}

// ============================================================================
// HTTP API (供 Python / 任何 HTTP 客户端调用，绕过 WebSocket/MCP 冲突)
// ============================================================================
function httpApi(req, res) {
  // CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'ok',
      extensionConnected: extensionWs !== null && extensionWs.readyState === 1,
      port: WS_PORT
    }));
    return;
  }

  // POST /api/<extensionType>  -> 把请求转发给 Chrome 扩展，等待响应
  if (req.method === 'POST' && req.url.startsWith('/api/')) {
    const extType = req.url.slice('/api/'.length).split('?')[0];
    let body = '';
    req.on('data', (chunk) => { body += chunk; });
    req.on('end', () => {
      let params = {};
      try {
        if (body) params = JSON.parse(body);
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: 'invalid JSON body' }));
        return;
      }
      const timeoutMs = parseInt(params._timeout || '60000', 10);
      sendToExtension(extType, params, timeoutMs)
        .then((data) => {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: true, data }));
        })
        .catch((err) => {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: false, error: err.message }));
        });
    });
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not Found');
}

const httpServer = http.createServer(httpApi);

const wss = new WebSocketServer({ server: httpServer });

wss.on('connection', (ws, req) => {
  const remote = req.socket.remoteAddress + ':' + req.socket.remotePort;
  logErr(`Chrome 扩展已连接 (来自 ${remote})`);
  extensionWs = ws;

  ws.on('message', (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw.toString());
    } catch (err) {
      logErr(`收到非 JSON 消息: ${raw.toString().slice(0, 200)}`);
      return;
    }
    handleExtensionMessage(msg);
  });

  ws.on('close', () => {
    if (extensionWs === ws) extensionWs = null;
    logErr('Chrome 扩展已断开');
    failAllPending(new Error('扩展已断开连接'));
  });

  ws.on('error', (err) => {
    logErr(`WebSocket 错误: ${err.message}`);
  });

  // 主动发送一条欢迎消息 (扩展可能不识别，但无害)
  try {
    ws.send(JSON.stringify({ type: 'welcome', server: 'mcp-browser-bridge' }));
  } catch (_) {}
});

function handleExtensionMessage(msg) {
  lastExtensionMessage = msg;

  // 响应格式: { type: 'response', requestId, data } 或 { type: 'error', requestId, error }
  if (msg.requestId !== undefined && (msg.type === 'response' || msg.type === 'error')) {
    const entry = pending.get(String(msg.requestId));
    if (!entry) {
      logErr(`未找到对应 requestId=${msg.requestId} 的挂起请求`);
      return;
    }
    pending.delete(String(msg.requestId));
    clearTimeout(entry.timer);
    if (msg.type === 'error') {
      entry.reject(new Error(msg.error || '扩展返回错误'));
    } else {
      entry.resolve(msg.data !== undefined ? msg.data : msg);
    }
    return;
  }

  // 其它消息 (例如 ping -> pong) 已经被扩展端处理，这里只记录
  logErr(`收到扩展主动消息: ${JSON.stringify(msg).slice(0, 200)}`);
}

function failAllPending(err) {
  for (const entry of pending.values()) {
    clearTimeout(entry.timer);
    entry.reject(err);
  }
  pending.clear();
}

/**
 * 向扩展发送命令并等待响应
 * @param {string} type 扩展识别的命令名 (例如 'getListTab')
 * @param {object} params 附加参数
 * @param {number} timeoutMs
 */
function sendToExtension(type, params = {}, timeoutMs = 30000) {
  return new Promise((resolve, reject) => {
    if (!extensionWs || extensionWs.readyState !== 1) {
      reject(new Error('Chrome 扩展未连接。请确认扩展已启用并打开任意页面。'));
      return;
    }
    const requestId = requestIdCounter++;
    const timer = setTimeout(() => {
      pending.delete(String(requestId));
      reject(new Error(`扩展响应超时 (${timeoutMs}ms): ${type}`));
    }, timeoutMs);
    pending.set(String(requestId), { resolve, reject, timer });
    try {
      extensionWs.send(JSON.stringify({ type, requestId, ...params }));
    } catch (err) {
      pending.delete(String(requestId));
      clearTimeout(timer);
      reject(err);
    }
  });
}

// ---------------------------------------------------------------------------
// 启动 WebSocket 服务端
// ---------------------------------------------------------------------------
httpServer.listen(WS_PORT, '127.0.0.1', () => {
  logErr(`WebSocket 服务端已启动: ws://localhost:${WS_PORT}`);
  logErr(`健康检查: http://127.0.0.1:${WS_PORT}/health`);
  logErr(`等待 Chrome 扩展 (MCP Browser Tools) 连接...`);
});

httpServer.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    logErr(`端口 ${WS_PORT} 已被占用。如果另一个实例在运行，这是正常的；否则请检查。`);
  } else {
    logErr(`HTTP 服务错误: ${err.message}`);
  }
});

// ---------------------------------------------------------------------------
// MCP 工具定义
// 工具名 -> 扩展侧 type
// ---------------------------------------------------------------------------
const TOOL_DEFS = [
  {
    name: 'browser_status',
    description:
      '检查与 Chrome 扩展的连接状态。返回 connected/port/lastExtensionMessage。',
    extensionType: null, // 特殊: 不需要发给扩展
  },
  {
    name: 'get_list_tab',
    description: '获取所有打开的浏览器标签。',
    extensionType: 'getListTab',
    schema: { type: 'object', properties: {}, additionalProperties: false },
  },
  {
    name: 'get_active_tab',
    description: '获取当前活动标签。',
    extensionType: 'getActiveTab',
    schema: { type: 'object', properties: {}, additionalProperties: false },
  },
  {
    name: 'set_active_tab',
    description: '将指定标签设为活动标签。',
    extensionType: 'setActiveTab',
    schema: {
      type: 'object',
      properties: { tabId: { type: 'number', description: '目标 tabId' } },
      required: ['tabId'],
      additionalProperties: false,
    },
  },
  {
    name: 'pin_active_tab',
    description: '固定一个标签，使后续命令始终作用于该标签。',
    extensionType: 'pinActiveTab',
    schema: {
      type: 'object',
      properties: { tabId: { type: 'number' } },
      required: ['tabId'],
      additionalProperties: false,
    },
  },
  {
    name: 'unpin_active_tab',
    description: '取消固定标签，恢复自动跟踪当前活动标签。',
    extensionType: 'unpinActiveTab',
    schema: { type: 'object', properties: {}, additionalProperties: false },
  },
  {
    name: 'new_tab',
    description: '新建一个标签并跳转 URL。',
    extensionType: 'newTab',
    schema: {
      type: 'object',
      properties: { url: { type: 'string' } },
      required: ['url'],
      additionalProperties: false,
    },
  },
  {
    name: 'close_tab',
    description: '关闭一个标签。',
    extensionType: 'closeTab',
    schema: {
      type: 'object',
      properties: { tabId: { type: 'number' } },
      required: ['tabId'],
      additionalProperties: false,
    },
  },
  {
    name: 'set_url_tab',
    description: '让指定标签导航到 URL。',
    extensionType: 'setUrlTab',
    schema: {
      type: 'object',
      properties: {
        tabId: { type: 'number' },
        url: { type: 'string' },
      },
      required: ['tabId', 'url'],
      additionalProperties: false,
    },
  },
  {
    name: 'get_tab_content_html',
    description: '获取当前活动标签的完整 HTML。',
    extensionType: 'getTabContentHtml',
    schema: { type: 'object', properties: {}, additionalProperties: false },
  },
  {
    name: 'get_tab_content_text',
    description: '获取当前活动标签的可见文本。',
    extensionType: 'getTabContentText',
    schema: { type: 'object', properties: {}, additionalProperties: false },
  },
  {
    name: 'query_selector',
    description: '在当前活动标签上用 CSS 选择器查询元素，返回 outerHTML 数组。',
    extensionType: 'querySelector',
    schema: {
      type: 'object',
      properties: { selector: { type: 'string' } },
      required: ['selector'],
      additionalProperties: false,
    },
  },
  {
    name: 'execute_script',
    description:
      '在当前活动标签的内容脚本中执行 JavaScript (会通过 EXECUTE_CODE 派发)。',
    extensionType: 'executeScript',
    schema: {
      type: 'object',
      properties: {
        script: { type: 'string', description: '要执行的 JS 代码' },
      },
      required: ['script'],
      additionalProperties: false,
    },
  },
  {
    name: 'get_console_log',
    description: '获取 console.log (需要目标标签已打开 DevTools)。',
    extensionType: 'getConsoleLog',
    schema: { type: 'object', properties: {}, additionalProperties: false },
  },
  {
    name: 'get_console_warn',
    description: '获取 console.warn (需要 DevTools 已打开)。',
    extensionType: 'getConsoleWarn',
    schema: { type: 'object', properties: {}, additionalProperties: false },
  },
  {
    name: 'get_console_error',
    description: '获取 console.error (需要 DevTools 已打开)。',
    extensionType: 'getConsoleError',
    schema: { type: 'object', properties: {}, additionalProperties: false },
  },
  {
    name: 'get_console_info',
    description: '获取 console.info (需要 DevTools 已打开)。',
    extensionType: 'getConsoleInfo',
    schema: { type: 'object', properties: {}, additionalProperties: false },
  },
  {
    name: 'get_console_debug',
    description: '获取 console.debug (需要 DevTools 已打开)。',
    extensionType: 'getConsoleDebug',
    schema: { type: 'object', properties: {}, additionalProperties: false },
  },
  {
    name: 'get_network_request',
    description: '获取网络请求列表 (需要 DevTools 已打开)。',
    extensionType: 'getNetworkRequest',
    schema: { type: 'object', properties: {}, additionalProperties: false },
  },
  {
    name: 'get_network_request_detail',
    description: '获取指定网络请求的详情 (需要 DevTools 已打开)。',
    extensionType: 'getNetworkRequestDetail',
    schema: {
      type: 'object',
      properties: {
        id: { type: 'string', description: '网络请求 ID' },
      },
      required: ['id'],
      additionalProperties: false,
    },
  },
  {
    name: 'extension_request',
    description:
      '直接向扩展发送任意 { type, ... } 命令并返回响应。用于协议调试或本服务尚未封装的命令。',
    extensionType: '__raw__',
    schema: {
      type: 'object',
      properties: {
        type: { type: 'string', description: '扩展侧 type 字段' },
        params: { type: 'object', description: '附加到消息根的其它字段' },
      },
      required: ['type'],
      additionalProperties: false,
    },
  },
];

const TOOLS_FOR_LIST = TOOL_DEFS.map(({ name, description, schema }) => ({
  name,
  description,
  inputSchema: schema || { type: 'object', properties: {}, additionalProperties: false },
}));

// ---------------------------------------------------------------------------
// MCP stdio 服务端
// ---------------------------------------------------------------------------
const server = new Server(
  { name: 'mcp-browser-bridge', version: '1.0.0' },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS_FOR_LIST }));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args = {} } = request.params;
  const def = TOOL_DEFS.find((t) => t.name === name);
  if (!def) {
    return {
      content: [{ type: 'text', text: `未知工具: ${name}` }],
      isError: true,
    };
  }

  try {
    if (name === 'browser_status') {
      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(
              {
                wsPort: WS_PORT,
                extensionConnected:
                  extensionWs !== null && extensionWs.readyState === 1,
                pendingRequests: pending.size,
                lastExtensionMessage,
              },
              null,
              2
            ),
          },
        ],
      };
    }

    if (def.extensionType === '__raw__') {
      const { type, params = {} } = args;
      const result = await sendToExtension(type, params);
      return { content: [{ type: 'text', text: JSON.stringify(result, null, 2) }] };
    }

    const result = await sendToExtension(def.extensionType, args);
    return { content: [{ type: 'text', text: JSON.stringify(result, null, 2) }] };
  } catch (err) {
    return {
      content: [{ type: 'text', text: `错误: ${err.message}` }],
      isError: true,
    };
  }
});

const transport = new StdioServerTransport();
server.connect(transport).catch((err) => {
  logErr(`MCP stdio 连接失败: ${err.message}`);
  process.exit(1);
});

// ---------------------------------------------------------------------------
// 优雅退出
// ---------------------------------------------------------------------------
function shutdown() {
  logErr('正在关闭...');
  try {
    for (const c of wss.clients) c.close();
    wss.close();
    httpServer.close();
  } catch (_) {}
  process.exit(0);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
