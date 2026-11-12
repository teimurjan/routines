// Runs first in each plugin context. It builds the `routines` global and the web APIs that JavaScriptCore lacks on the native bridge of the Swift host.
import "core-js/actual/url";
import "core-js/actual/url-search-params";
import "core-js/actual/structured-clone";
import type { PluginDefinition, RoutinesHost } from "../../sdk/src/host.ts";
import type { Result } from "../../sdk/src/result.ts";

type Native = {
  call: (method: string, payload: string) => Promise<string>;
  log: (message: string) => void;
  info: () => string;
  randomBytes: (count: number) => number[];
};

declare global {
  var __native: Native;
  var __plugin: PluginDefinition | undefined;
}

const native = globalThis.__native;

const call = async <T>(method: string, payload: unknown = {}): Promise<Result<T>> => {
  try {
    return JSON.parse(await native.call(method, JSON.stringify(payload ?? {}))) as Result<T>;
  } catch (cause) {
    return { ok: false, error: `${method}: ${(cause as Error).message}` };
  }
};

const format = (values: unknown[]) => values.map((value) => (typeof value === "string" ? value : safeStringify(value))).join(" ");

const safeStringify = (value: unknown) => {
  if (value instanceof Error) return `${value.name}: ${value.message}`;
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
};

const routines: RoutinesHost = {
  info: JSON.parse(native.info()),
  log: (message) => native.log(message),
  exec: (cmd, options = {}) => call("exec", { cmd, ...options }),
  which: (name) => call("which", { name }),
  fs: {
    exists: (path) => call("fs.exists", { path }),
    readText: (path) => call("fs.readText", { path }),
    writeText: (path, text, options = {}) => call("fs.writeText", { path, text, ...options }),
    readBase64: (path) => call("fs.readBase64", { path }),
    writeBase64: (path, base64) => call("fs.writeBase64", { path, base64 }),
    remove: (path) => call("fs.remove", { path }),
    mkdir: (path) => call("fs.mkdir", { path }),
    list: (path) => call("fs.list", { path }),
  },
  lock: {
    acquire: (name, timeoutMs = 5000) => call("lock.acquire", { name, timeoutMs }),
    release: (name) => call("lock.release", { name }),
  },
  board: {
    upsert: (card) => call("board.upsert", card),
    remove: (id) => call("board.remove", { id }),
    list: () => call("board.list"),
  },
  notify: (notification) => call("notify", notification),
  runSoon: (delayMs) => call("run.soon", { delayMs }),
  notes: { list: () => call("notes.list") },
  activity: { list: (since) => call("activity.list", { since }) },
  page: {
    publish: (blocks) => call("page.publish", { blocks }),
    get: () => call("page.get"),
  },
  http: (request) => call("http", request),
  browser: {
    open: (profile) => call("browser.open", { profile }),
    goto: (session, url, timeoutMs = 60_000) => call("browser.goto", { session, url, timeoutMs }),
    waitFor: (session, expression, timeoutMs = 60_000) => call("browser.waitFor", { session, expression, timeoutMs }),
    evaluate: (session, body, args = {}) => call("browser.evaluate", { session, body, args }),
    close: (session) => call("browser.close", { session }),
  },
  definePlugin: (plugin) => {
    globalThis.__plugin = plugin;
  },
};

globalThis.routines = routines;

const consoleLog = (...values: unknown[]) => native.log(format(values));
Object.assign(globalThis.console ?? (globalThis.console = {} as Console), {
  log: consoleLog,
  info: consoleLog,
  debug: consoleLog,
  warn: (...values: unknown[]) => native.log(`warning: ${format(values)}`),
  error: (...values: unknown[]) => native.log(`error: ${format(values)}`),
});

// Timers resolve in the host, so a plugin can wait without a busy loop.
let nextTimer = 1;
const cancelled = new Set<number>();
const startTimer = (callback: (...args: unknown[]) => void, ms: number, args: unknown[], repeat: boolean) => {
  const id = nextTimer++;
  const tick = () =>
    call("timer.sleep", { ms: Math.max(0, Number(ms) || 0) }).then(() => {
      if (cancelled.has(id)) return void cancelled.delete(id);
      callback(...args);
      if (repeat) tick();
    });
  tick();
  return id;
};
Object.assign(globalThis, {
  setTimeout: (callback: (...args: unknown[]) => void, ms = 0, ...args: unknown[]) => startTimer(callback, ms, args, false),
  setInterval: (callback: (...args: unknown[]) => void, ms = 0, ...args: unknown[]) => startTimer(callback, ms, args, true),
  clearTimeout: (id: number) => void cancelled.add(id),
  clearInterval: (id: number) => void cancelled.add(id),
  queueMicrotask: (callback: () => void) => void Promise.resolve().then(callback),
});

const BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

const bytesToBase64 = (bytes: Uint8Array) => {
  let out = "";
  for (let index = 0; index < bytes.length; index += 3) {
    const [a, b, c] = [bytes[index] ?? 0, bytes[index + 1], bytes[index + 2]];
    const triple = (a << 16) | ((b ?? 0) << 8) | (c ?? 0);
    out += BASE64[(triple >> 18) & 63]! + BASE64[(triple >> 12) & 63]!;
    out += b === undefined ? "=" : BASE64[(triple >> 6) & 63]!;
    out += c === undefined ? "=" : BASE64[triple & 63]!;
  }
  return out;
};

const base64ToBytes = (base64: string) => {
  const clean = base64.replace(/[^A-Za-z0-9+/]/g, "");
  const bytes: number[] = [];
  for (let index = 0; index < clean.length; index += 4) {
    const chunk = [0, 1, 2, 3].map((offset) => BASE64.indexOf(clean[index + offset] ?? "A"));
    const triple = (chunk[0]! << 18) | (chunk[1]! << 12) | (chunk[2]! << 6) | chunk[3]!;
    bytes.push((triple >> 16) & 255);
    if (index + 2 < clean.length) bytes.push((triple >> 8) & 255);
    if (index + 3 < clean.length) bytes.push(triple & 255);
  }
  return new Uint8Array(bytes);
};

const utf8Encode = (text: string) => {
  const bytes: number[] = [];
  for (const char of text) {
    const code = char.codePointAt(0)!;
    if (code < 0x80) bytes.push(code);
    else if (code < 0x800) bytes.push(0xc0 | (code >> 6), 0x80 | (code & 63));
    else if (code < 0x10000) bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63));
    else bytes.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 63), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63));
  }
  return new Uint8Array(bytes);
};

const utf8Decode = (bytes: Uint8Array) => {
  let out = "";
  for (let index = 0; index < bytes.length; ) {
    const first = bytes[index]!;
    const size = first < 0x80 ? 1 : first < 0xe0 ? 2 : first < 0xf0 ? 3 : 4;
    let code = size === 1 ? first : first & (0xff >> (size + 1));
    for (let offset = 1; offset < size; offset += 1) code = (code << 6) | ((bytes[index + offset] ?? 0) & 63);
    out += String.fromCodePoint(code);
    index += size;
  }
  return out;
};

const latin1 = (text: string) => Uint8Array.from(text, (char) => char.charCodeAt(0) & 255);

class TextEncoderPolyfill {
  readonly encoding = "utf-8";
  encode(text = "") {
    return utf8Encode(text);
  }
}

class TextDecoderPolyfill {
  readonly encoding = "utf-8";
  decode(input?: ArrayBuffer | ArrayBufferView) {
    if (!input) return "";
    const bytes = input instanceof ArrayBuffer ? new Uint8Array(input) : new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
    return utf8Decode(bytes);
  }
}

const randomUUID = () => {
  const bytes = Uint8Array.from(native.randomBytes(16));
  bytes[6] = (bytes[6]! & 0x0f) | 0x40;
  bytes[8] = (bytes[8]! & 0x3f) | 0x80;
  const hex = [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
};

Object.assign(globalThis, {
  TextEncoder: TextEncoderPolyfill,
  TextDecoder: TextDecoderPolyfill,
  btoa: (text: string) => bytesToBase64(latin1(String(text))),
  atob: (base64: string) => String.fromCharCode(...base64ToBytes(base64)),
  crypto: {
    randomUUID,
    getRandomValues: <T extends ArrayBufferView>(array: T) => {
      const view = new Uint8Array(array.buffer, array.byteOffset, array.byteLength);
      view.set(native.randomBytes(view.length));
      return array;
    },
  },
  performance: { now: () => Date.now() },
});

// fetch is a thin layer over the host `http` call. A timeout comes from AbortSignal.timeout, which the host enforces.
class TimeoutSignal {
  readonly aborted = false;
  constructor(readonly timeoutMs: number) {}
  addEventListener() {}
  removeEventListener() {}
  static timeout(ms: number) {
    return new TimeoutSignal(ms);
  }
}

class HeadersPolyfill {
  private readonly entriesList: [string, string][] = [];
  constructor(init?: Record<string, string> | [string, string][] | HeadersPolyfill) {
    const pairs = init instanceof HeadersPolyfill ? init.entriesList : Array.isArray(init) ? init : Object.entries(init ?? {});
    for (const [name, value] of pairs) this.append(name, value);
  }
  append(name: string, value: string) {
    this.entriesList.push([name.toLowerCase(), String(value)]);
  }
  set(name: string, value: string) {
    this.delete(name);
    this.append(name, value);
  }
  delete(name: string) {
    const lower = name.toLowerCase();
    for (let index = this.entriesList.length - 1; index >= 0; index -= 1) if (this.entriesList[index]![0] === lower) this.entriesList.splice(index, 1);
  }
  get(name: string) {
    const values = this.entriesList.filter(([key]) => key === name.toLowerCase()).map(([, value]) => value);
    return values.length > 0 ? values.join(", ") : null;
  }
  has(name: string) {
    return this.get(name) !== null;
  }
  getSetCookie() {
    return this.entriesList.filter(([key]) => key === "set-cookie").map(([, value]) => value);
  }
  entries() {
    return this.entriesList[Symbol.iterator]();
  }
  forEach(callback: (value: string, name: string) => void) {
    for (const [name, value] of this.entriesList) callback(value, name);
  }
  [Symbol.iterator]() {
    return this.entries();
  }
  toObject() {
    return Object.fromEntries(this.entriesList);
  }
}

class ResponsePolyfill {
  readonly headers: HeadersPolyfill;
  readonly ok: boolean;
  constructor(
    private readonly text_: string,
    readonly status: number,
    headers: [string, string][],
    readonly url: string,
    private readonly base64?: string,
  ) {
    this.headers = new HeadersPolyfill(headers);
    this.ok = status >= 200 && status < 300;
  }
  get statusText() {
    return String(this.status);
  }
  async text() {
    return this.text_;
  }
  async json() {
    return JSON.parse(this.text_);
  }
  async arrayBuffer() {
    const bytes = this.base64 === undefined ? utf8Encode(this.text_) : base64ToBytes(this.base64);
    return bytes.buffer;
  }
}

type FetchInit = {
  method?: string;
  headers?: Record<string, string> | [string, string][] | HeadersPolyfill;
  body?: string | URLSearchParams | Uint8Array | ArrayBuffer;
  redirect?: "follow" | "manual";
  signal?: TimeoutSignal;
};

const bodyOf = (body: FetchInit["body"]) => {
  if (body === undefined) return {};
  if (typeof body === "string") return { body };
  if (body instanceof URLSearchParams) return { body: body.toString() };
  const bytes = body instanceof ArrayBuffer ? new Uint8Array(body) : body;
  return { bodyBase64: bytesToBase64(bytes) };
};

const fetchPolyfill = async (input: string | URL, init: FetchInit = {}) => {
  const headers = new HeadersPolyfill(init.headers);
  if (init.body instanceof URLSearchParams && !headers.has("content-type")) headers.set("content-type", "application/x-www-form-urlencoded;charset=UTF-8");
  const reply = await call<{ status: number; url: string; headers: [string, string][]; body: string; bodyBase64?: string }>("http", {
    url: String(input),
    method: init.method ?? "GET",
    headers: headers.toObject(),
    ...bodyOf(init.body),
    redirect: init.redirect ?? "follow",
    timeoutMs: init.signal?.timeoutMs,
  });
  if (!reply.ok) throw new TypeError(`fetch failed: ${reply.error}`);
  const { body, status, headers: replyHeaders, url, bodyBase64 } = reply.value;
  return new ResponsePolyfill(body, status, replyHeaders, url, bodyBase64);
};

Object.assign(globalThis, {
  fetch: fetchPolyfill,
  Headers: HeadersPolyfill,
  Response: ResponsePolyfill,
  AbortSignal: TimeoutSignal,
});
