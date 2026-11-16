---
name: api-recon
description: 在授权范围内发现网站 API、分析参数并验证漏洞、请求修改及访问控制。
---

# API Recon（前端接口侦察）

在**已授权**前提下，尽可能完整地发现：**后端 API**（路径、方法、参数、响应体）、**前端路由**、**UI 功能触发点**（Tab、弹窗、表格操作等）。

---

## 授权范围与测试能力

本 skill 支持 API / 参数面侦察，以及用户明确授权范围内的漏洞验证。不得仅因使用本 skill 而拒绝漏洞检查、请求重放与修改、身份认证或访问控制验证。

- 用户拥有或明确授权测试的目标，可进行非破坏性的 SQLi、XSS、SSRF、输入校验、认证及权限隔离验证，并记录请求、响应和复现条件。
- 可以在授权范围内修改参数、请求头、方法和请求体，比较正常请求与测试请求的响应。
- 可以使用用户已经登录的真实会话及专用 A/B 测试账号，验证水平和垂直权限隔离。账号之间使用独立浏览器配置或会话，保持原账号会话。
- 有真实授权会话时直接观察真实响应。stub/mock 仅用于无会话时的前端接口枚举，不作为漏洞成立或权限绕过的证据，不覆盖用户现有登录状态。
- 只有明确授权的域名、账号、测试数据和操作属于范围。可能破坏数据、影响可用性或产生外部业务效果的测试，须在用户明确允许该影响的范围内进行。
- 日志和报告隐藏密码、会话令牌和 API 密钥，以最少的测试数据证明问题。
- 共享浏览器每次只交给一个测试任务；执行前确认目标域名和会话，禁止恢复其他项目或已归档任务。

### 侦察工作流约定

静态与运行时接口枚举继续使用下述 harvest、参数矩阵与覆盖流程。进行已授权的漏洞验证时，可依据已发现的 API 直接制定验证步骤，不因侦察阶段未全部完成而禁止验证。脚本先复制到 OUTDIR 后再按目标调整，重复失败时分析日志并更换策略。报告区分已验证结果、mock 观察与待确认项。

---

## 两层模型 + 运行模式

| 层 | 产出 | 上限 |
|---|---|---|
| **静态**（JS bundle） | 全量 endpoint 路径、路由草案、组包点字段候选 | 无 HTTP 方法；参数须 Phase 1b；漏掉运行时拼接 URL |
| **运行时**（活会话） | 方法 + body + 响应 + 动态 URL + WS/SSE；多样本 diff 补全参数 | 页面须实际渲染才会发请求；单样本不足以定必填/可选 |

| 运行模式 | 引擎 | 适用 |
|---|---|---|
| **depth** | `runtime_harvest.js`（Puppeteer） | API 清单、METHOD/params/响应体、WS/SSE、可复现批量跑 |
| **coverage** | browser + `preload.js` | 点 Tab/弹窗/表格，功能点覆盖更深 |
| **both** | 先 depth 再 coverage | 最完整，耗时最长 |

**参数方法论**（无通用脚本）：path 用 harvest/正则；参数用 **锚点扩窗 + UI 绑定链 + 多样本 diff + 错误反推**（grep 配方见 [reference.md](reference.md) J 节）。

---

## 完成定义

全部满足方可声称 recon 完成：

- [ ] **静态**：Phase 1 harvest 产出 `api_static.txt`、`routes.txt`、`js/`
- [ ] **运行时**：至少 depth 或 coverage 之一；coverage/both 须 **Hook 生效 + 动态枚举环**
- [ ] **进壳**：访问业务 path 时非 `/login`（注意 hash 路由）
- [ ] **参数**：coverage/both 完成参数触发矩阵 + `param_samples.json`；Phase 5 合并 `params_merged.json`
- [ ] **深度**（若模块页空白）：Phase 4 权限树还原并重跑，直至出现 **module 级 API**（非仅 locale/bootstrap）
- [ ] **交付**：Phase 5 产出齐全（见 Phase 5 产出表）；`insert_assets` 写入服务与端点资产

---

## 脚本与门禁

`scripts/` 仅为参考模板，**禁止**直接跑原版并当最终结果。

**规则**：先读 → 按目标改 → 写入 `OUTDIR`（如 `recon/`）→ 记 `CHANGES.md`；不匹配则按方法论重写，只借结构。

| 门禁 | 何时 | 参考脚本 → OUTDIR 副本 | 常见必改项 |
|---|---|---|---|
| **A（静态）** | Phase 0 后、**第一次**跑 harvest/spider 前 | `harvest_static.py` / `spider_mpa.py` | **多数站点默认 regex 可直接跑**；仅 manifest/方言不匹配时改 endpoint 正则、webpack/Vite `publicPath`、MPA exclude/cookie |
| **B（运行时）** | Phase 2 后、跑 depth/coverage 前 | `runtime_harvest.js` / `preload.js` + `config.json` | Cookie/localStorage 键、neutralize 成功值、stubs、login 正则、api 前缀、hash/history |

**SPA 强制顺序**（不可交换；Phase 编号优先于「先探索再脚本」）：

| 步骤 | 必须 | 禁止 |
|---|---|---|
| Phase 0 完成后 | 下一条 Bash = `python3 OUTDIR/harvest_static.py <URL> OUTDIR` | curl/grep/Read 主 entry `index-*.js`（通常 >500KB） |
| 门禁 A | 复制脚本 → 按需小改 → **立刻运行** | 先手工提取 API 再决定是否 harvest |
| Phase 1 完成前 | `wc -l` 校验产出；404 改 harvest 重试 | 手写 extract 脚本；对未下载 URL 反复 grep |
| Phase 1b 起 | grep 仅 `OUTDIR/js/*.js` | 用主 bundle 代替 harvest |

- ✅ 复制 `harvest_static.py` → （可选）改 regex → **立即运行**
- ❌ curl 主 bundle → grep 多次 → 写临时 extract → 最后才 harvest
- **MPA**：Phase 0 后下一条 Bash = `python3 OUTDIR/spider_mpa.py ...`

---

## 工具与输出约束

| 约束 | 说明 |
|---|---|
| 大文件 | >100KB 的 `index-*.js` **禁止** Read/grep 进上下文；用 OUTDIR 脚本批处理 |
| grep 输出 | 必须 `\| head -20` 或 `-m 5`；对话只保留 path 摘要，勿贴 bundle 片段 |
| 校验 | 用 `wc -l`、`ls \| wc -l`；勿 Read 整目录 |
| regex 初探 | 可选、≤1 次、仅 ≤50KB 小 chunk 或 HTML；正式静态以 harvest 为准 |
| reference | 配方/模板/排障见 [reference.md](reference.md)，勿重复 inline 全文 |

---

## 执行路线图

```
Phase 0 分类 + OUTDIR
  → 门禁 A → Phase 1 harvest（★ 立刻运行 ★）
  → Phase 1b 参数逆向
  → Phase 2 鉴权三道门 → config.json
  → 门禁 B → Phase 3 运行时 + 参数矩阵
  → Phase 4 权限树（必要时）→ 重跑 Phase 3
  → Phase 5 合并报告 + insert_assets批量插入所有发现的服务、端点api资产，无论如何插入时不允许漏掉已发现的资产
```

按序勾选；**前一项未完成不得进入下一 Phase**。

1. [ ] **Phase 0**：初探 SPA/MPA；创建 `OUTDIR` → [Phase 0](#phase-0--分类)
2. [ ] **门禁 A + Phase 1**：复制脚本 → **立刻** harvest → `wc -l` 校验 → [Phase 1](#phase-1--静态)
3. [ ] **Phase 1b**：锚点扩窗 + 绑定层 → `param_candidates.json` → [Phase 1b](#phase-1b--参数逆向)
4. [ ] **Phase 2**：鉴权三道门 → `config.json` → [Phase 2](#phase-2--鉴权三道门)
5. [ ] **门禁 B**：调整 runtime 脚本 → [Phase 3](#phase-3--运行时)
6. [ ] **Phase 3**：depth / coverage / both；确认进壳；参数触发矩阵 → `param_samples.json`
7. [ ] **Phase 4**（若需要）：权限树 → patch stubs → 重跑 Phase 3 → [Phase 4](#phase-4--权限树还原)
8. [ ] **Phase 5**：合并产出 + 报告 + `insert_assets` → [Phase 5](#phase-5--合并与报告)

---

## Phase 0 — 分类

拉取入口 HTML，**创建 `OUTDIR`**（勿改 skill 内 `scripts/`）：

- **SPA**：空壳 + `<div id=app>` + chunk → Phase 1–5
- **MPA**：SSR + `<form>`、无 endpoint bundle → 门禁 A 后：

```bash
python3 recon/spider_mpa.py <BASE_URL> <OUTDIR> [--cookie "session=..."] [--max 300] [--depth 5] [--exclude "logout|delete|destroy"]
```

产出 `forms.txt`、`links.txt`、`api_inline.txt`。SPA 若 forms ≈ 0 → 切 Phase 1。

---

## Phase 1 — 静态

遵守 [脚本与门禁](#脚本与门禁) · [工具与输出约束](#工具与输出约束)。

```bash
python3 recon/harvest_static.py <BASE_URL> <OUTDIR>
```

harvest：解析 HTML script → webpack/Vite manifest → 下载全部 lazy chunk → 产出 `js/`、`api_static.txt`、`routes.txt`、`chunkmap.txt`。

```bash
wc -l OUTDIR/api_static.txt OUTDIR/routes.txt
ls OUTDIR/js | wc -l
```

- chunk 数 vs manifest：404 须改 harvest 重试，勿手工 curl 逐个 chunk
- `api_static.txt` 过少 → 放宽 OUTDIR 内 endpoint 正则后重跑（见 reference）

### Phase 1b — 参数逆向

path 来自 Phase 1；参数字段须单独 recon。grep 规则见 [工具与输出约束](#工具与输出约束)。

**完成标准**：重要接口能答——字段名、传输位置、类型推断、是否必填、样本值、置信度。

#### 1b.0 — 传输形态

| 形态 | 参数在哪 | 静态优先看 |
|---|---|---|
| REST JSON | body + query | path 锚点旁 `(params\|data\|body)\s*:\s*\{` |
| GraphQL | `variables` | gql 模板、`$page: Int` |
| 传统 form | urlencoded | `<form>`、`FormData` |
| 文件上传 | multipart | `FormData.append` |
| 路径参数 | `/user/:id` | 路由表 + `useParams` / `$route.params` |
| 加密/签名 | 包进 `sign`/`data` | Hook 加密函数入参（reference D 节） |

产出：每接口标注 `transport: query|json|form|graphql|encrypted`。

#### 1b.1 — 锚点扩窗

以已知 path 为锚，扩窗口找组包对象：

```bash
grep -n '"/api/user/list"' OUTDIR/js/*.js | head -20
grep -rhoaE '.{0,120}("/api[^"]+").{0,200}' OUTDIR/js/*.js | head -20
grep -rhoaE '(params|data|body|payload)\s*:\s*\{' OUTDIR/js/*.js | head -20
```

| 包装层 | 参数线索 |
|---|---|
| axios 实例 | `data` / `params` |
| 统一 request | 拦截器注入全局字段 |
| OpenAPI 客户端 | 生成 method 签名 |
| React Query / SWR | hook 第二参数 |
| Vue composable | composable 入参 |

类型残留：`yup`/`zod`/rules、`Form.Item name=`、内嵌 Swagger。

→ `param_candidates.json`：`{ path, fields[], source: "static-callsite", confidence }`

#### 1b.2 — 绑定层

```
Form field → onFinish/handleSubmit → transform → API payload
```

| 绑定源 | 手法 |
|---|---|
| 表单 submit | 跟 submit → transform → API |
| 表格搜索 | `getFieldsValue()` → `params` |
| 路由 | `:id` / `?tab=` |
| 拦截器 | 全局 `tenantId`、分页、sign |
| 枚举 select | `options` → API 枚举值 |

DevTools call stack 从 `fetch`/`XHR.send` 往上追组包函数。

#### 1b.3 — 组包三问（≠ Phase 2 鉴权三门）

| 问 | 要答什么 |
|---|---|
| **组装** | payload 在哪 build、transform 痕迹 |
| **校验** | required、pattern、enum |
| **传输** | path / query / body / multipart / 头 |

拦截器门（Phase 2）顺带读全局注入字段（Authorization、`X-Tenant-Id`、sign）。

#### 1b.4 — 与 Phase 3 衔接

候选字段来自静态/绑定层；**必填/可选/条件依赖**须 Phase 3 参数矩阵 + diff + Phase 5 错误反推。

---

## Phase 2 — 鉴权三道门

已有授权登录会话时，保留真实认证状态并分析真实请求和响应；不注入 fake auth、不 stub 真实鉴权、不覆盖 A/B 会话。以下鉴权门与 mock 配置用于无会话的前端枚举场景。

在 `OUTDIR/js/` grep（带 `head`），写入 `config.json`（配方见 reference）：

| 门 | 问题 | 关键词 |
|---|---|---|
| **渲染门** | 如何判断已登录？ | `isLogin`、`getToken`、Cookie/localStorage |
| **拦截器门** | 什么触发跳 `/login`？ | `response_code`、`errno`、axios interceptor |
| **内容门** | 菜单/权限从哪来？ | `menu`、`permission`、`role`、`acl`、`routes` |

禁止把 localStorage 键名当凭据——须从 chunk/请求链确认。

**出口 = 门禁 B**：结论落到 `config.json`，并改 `OUTDIR/runtime_harvest.js` / `preload.js`。

### Phase 2b — API 观察（可选）

用 OUTDIR 内 `preload.js` 确认会话键名、Authorization、嵌套 API URL：

| 配置 | 产出 |
|---|---|
| `recordDetail: true` | `__API_RECON_DETAIL__` |
| `observe.xhrHeaders: true` | headers 观察 |
| `extractUrlsFromResponse: true` | 响应内子 API |
| `observe.storageReads/cookieReads: true` | 回填 config |
| `neutralizeVueRouter: true` | `__API_RECON_ROUTES__` |

coverage 每轮导出：`__API_RECON_LOG__`、`__API_RECON_DETAIL__`、`__API_RECON_ROUTES__`、`__API_RECON_OBSERVE__`。

---

## Phase 3 — 运行时

已授权真实会话使用真实请求和响应；无会话的前端枚举才使用门禁 B 与 mock 策略。测试权限以本页「授权范围与测试能力」及用户明确授权为准。

`config.json` 设置 `"runtimeMode": "depth" | "coverage" | "both"`（模板见 reference）。

### Hook 与 stub（仅用于无会话的前端枚举）

| 层 | 范围 | 目的 |
|---|---|---|
| L1 精确 | auth/权限/bootstrap stub | 过首屏鉴权 |
| L2 负向修正 | 所有 JSON 响应 | 未登录码 → 成功 |
| L3 兜底 | 未命中 L1 的 `/api` 等 | 空成功体，撑开 UI |

- **depth**：fake auth + `forward` 改业务码 + `stubs`；遍历 `routes`（hash/history）；产出 `runtime_api.json`
- **coverage**：**document-start** 注入 `preload.js`（CDP `addScriptToEvaluateOnNewDocument` 或 Userscript）

验证：`window.__API_RECON_PRELOAD__` 存在；业务 path 不回 `/login`。

```bash
cd recon && npm install
node runtime_harvest.js config.json
```

### 3b — coverage 动态枚举（必做）

1. 主导航/侧栏 — 每项点击，等网络 1–3s
2. Tab — `role=tab`、`.ant-tabs-tab`
3. 表格 — 首行查看/编辑/详情
4. 工具栏 — 导出、筛选、新建（**避免不可逆删除**）
5. 每进模块 — 合并 API/路由
6. SPA — 对 `routes.txt` 未覆盖 path 受控 `pushState`（MPA 禁止）

**参数触发矩阵**（必做）：每模块按操作类型各录一次，**diff 多样本**：

| 操作 | 通常多出的参数 |
|---|---|
| 列表首屏 | 分页 + 默认筛选 |
| 点搜索 | keyword、filter |
| 高级筛选 | 更多 optional |
| 新建/编辑 | 完整 entity |
| 批量/导出/排序 | `ids[]`、`exportType`、`sortField` |

**stub 下 outbound body/headers 可用于接口枚举，但不证明真实后端漏洞**。真实会话测试以实际请求和响应为证据。录制 → `scan_raw.json`、`param_samples.json`、`api_detail.json`。

- **Vue**：`neutralizeVueRouter: true` + document-start preload
- **React**：`routes.txt` + 侧栏点击 + `pushState`
- **both**：先 3a depth，再 3b coverage

---

## Phase 4 — 权限树还原

**触发**：模块页空白 / 每路由仅 bootstrap（如 locale）→ 内容门未过。

| 现象 | 含义 |
|---|---|
| 进壳成功 | 渲染门 + 拦截器门已过 |
| 侧栏缺项/点击空白 | stub shape 或权限码不全 |
| 每路由 API 相同且极少 | `v-if permission` 未通过 |
| `routes.txt` 远少于 bundle | 须从 auth 模块补全 |

```bash
grep -rhoaE '"/api[^"]*(permission|perm|role|menu|acl)[^"]*"' OUTDIR/js/*.js | sort -u | head -30
grep -rhoaE 'userRouteAuth|getResultTree|routeMap|routeLink|menuList|authList' OUTDIR/js/*.js | head -20
```

典型链：`role_permissions`（flat codes）+ `permissions/all`（tree）→ `getResultTree` → `userRouteAuth[CODE].url`。

```bash
python3 recon/extract_route_map.py recon/js recon/
python3 recon/build_perm_tree.py recon/js recon/ --config recon/config.json
```

中间产出：`route_map.json`、`userRouteAuth.json`、`permissions_tree.json`、`*_stub.json`、`perm_codes_all.txt`。

stub 检查：外层 `response_code` 与拦截器门一致；flat codes 与 tree 对齐；`routes` 覆盖 `route_map` 全部 link。

更新 `config.json` 后**重跑 Phase 3**。大型 SPA 可调 `waitUntil`、`routeTimeout`、`perRouteMs`（见 reference A3/I 节）。

---

## Phase 5 — 合并与报告

### 产出表

| 文件 | 阶段 | 内容 |
|---|---|---|
| `js/`、`api_static.txt`、`routes.txt`、`chunkmap.txt` | 1 | 静态 bundle 与 path |
| `param_candidates.json` | 1b | 静态参数字段候选 |
| `config.json` | 2 | 三道门 + runtime 配置 |
| `runtime_api.json` | 3a | depth 详细录制（含 WS/SSE） |
| `param_samples.json`、`scan_raw.json`、`api_detail.json` | 3b | 多样本、点击日志、detail |
| `route_map.json` 等 | 4 | 权限树中间文件（若执行） |
| `params_merged.json` | 5 | 合并参数字段 + 置信度 |
| `api_merged.txt` | 5 | `METHOD /path [params] [static\|runtime\|both]` |
| `site_map.json` | 5 | 路由、API、params、功能点、局限 |
| **insert_assets** | 5 | 将所有服务、端点资产写入资产库 |

### 5b — 参数合并

从 `param_samples.json` diff，**无通用合并脚本**。置信度规则见 reference J7（高/中/低/待触发）。

### 5c — 错误反推

授权范围内可发不完整请求读取 400，分析参数约束；也可按已授权测试计划修改请求验证输入校验与权限隔离：`field 'x' is required`、枚举错误等。注意 `data` 包装、`variables`、加密前 `bizData`。

报告须注明：runtimeMode、静态/运行时 API 数、参数置信度、未覆盖模块、相对参考脚本的 `CHANGES.md` 摘要。

`site_map.json` 建议结构：

```json
{
  "site": "https://example.com",
  "runtimeMode": "both",
  "appType": "vue-spa",
  "routeGuardStrategy": ["nav-neutralize", "L1-auth", "L2-patch", "forward"],
  "apisFromStatic": [],
  "apisFromRuntime": [],
  "apis": [],
  "params": [{ "method": "POST", "path": "/api/user/list", "transport": "json", "fields": [] }],
  "frontendRoutes": [],
  "routesVerifiedByClick": [],
  "featuresTriggered": [],
  "limitations": ""
}
```

更多字段与 grep 配方见 [reference.md](reference.md)。

---

## 通用说明

- **框架无关**：webpack/Vite/Angular lazy load 方法相同
- **传输**：REST/JSON、GraphQL、WebSocket、SSE；gRPC-web 不在范围
- **SSR**：客户端 fetch 可录；RSC/Server Actions 不完全可枚举
- **盲区**：JSVMP、WASM、HMAC/mTLS 强校验 → 静态 + 标注局限
- **参数盲区**：条件联动、hidden params、WASM 组包 → 「待触发」/「不可达」
- **静态是安全网**：runtime 被挡时静态仍能枚举 endpoint

---

## 附加资源

- Grep 配方、`config.json` 模板、排障、Hook、参数逆向 J 节、site_map 模板：**[reference.md](reference.md)**
- 参考脚本路径见 [脚本与门禁](#脚本与门禁) 表
