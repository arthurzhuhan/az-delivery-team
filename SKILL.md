---
name: az-delivery-team
description: 为项目创建完整的交付团队 Agent（产品负责人、架构师、领域全栈工程师、红队对抗、冒烟测试、UI/UX QA、验收评审）。支持纵向领域切分和对抗式交叉验证。Use when starting a new project, setting up multi-agent delivery, or when user mentions project team, delivery quality, acceptance testing, go-live readiness.
tools: Write, Read, Bash, Glob, AskUserQuestion
---

# Setup Project Team

> **Skill version: 3.1** (2026-04-12)

## 背景

> 教训：代码交付 ≠ 产品交付。工程 Agent 只管代码质量，没人管产品质量；实施 Agent 只管写代码，没人做对抗式检验。

本 Skill 为任意项目创建 **3 层 10+N 角色** 的完整交付团队（N = 领域工程师数量），覆盖从"定义做什么"到"验证做对没"到"能不能上线"的全链路。

### 两阶段模型

本 Skill 服务于**第二阶段（实施 & 交付）**。第一阶段（探讨 & 设计）由人和 Claude 在单会话中完成，产出标准化文档作为第二阶段的输入。

```
第一阶段：探讨 & 设计（人 80% + Claude 20%）
  产出 → 设计文档（形式不限，内容须覆盖下方清单）
          │
交接检查：product-owner（业务侧）+ project-architect（技术侧）
  各出 Readiness Report，都 PASS 才进入第二阶段
  如果是已有代码的项目，额外做代码-文档一致性审查
          │
第二阶段：实施 & 交付（Agents 80% + 人 20%）
  消费 ← 设计文档
  product-owner 有权修改设计细节，但坚守核心目标
  所有变更记录在 CHANGELOG.md
```

### 第二阶段所需内容（第一阶段产出标准）

文件数量不限——可以是 1 个大文档也可以是 10 个小文档。Skill 只检查内容是否覆盖，不规定文件结构。

**必须覆盖（缺了跑不起来）：**

| 内容 | 具体要求 | 谁消费 |
|------|---------|--------|
| 产品核心定义 | 产品是什么、为谁、核心价值、**不可偏离的核心目标** | product-owner（守护）、acceptance-reviewer |
| 核心用户流程 | 3-5 条关键旅程，Given/When/Then 验收标准 | smoke-tester、api-tester、acceptance-reviewer |
| 系统架构 | 技术栈、领域划分、服务边界、数据流 | project-architect、domain-engineer |
| API 契约 | 端点清单：Method/Path/Request/Response/Error | api-tester、domain-engineer |
| 数据模型 | 表结构、字段、关系、索引 | domain-engineer、security-auditor |

**应该覆盖（没有也能跑，但验证质量降级）：**

| 内容 | 具体要求 | 谁消费 |
|------|---------|--------|
| 设计规范 | 色彩 token、排版、组件库、品牌语气 | uiux-qa、domain-engineer |
| 页面清单 & 路由 | URL、用途、访问权限、信息层级 | uiux-qa、launch-readiness |
| 外部依赖清单 | 服务名、env 变量、是否必须、降级策略 | domain-engineer、security-auditor |
| 性能预算 | 目标 LCP/TTFB/bundle、基准设备 | performance-auditor |
| SEO & 合规需求 | 关键词、OG 规范、隐私政策、WCAG 级别 | launch-readiness |

### 核心设计原则

1. **纵向切分**：按业务领域划分全栈工程师，不按前端/后端技术层切分
2. **对抗式验证**：red-team 独立于所有验证 agent，有权挑战任何 PASS，由 acceptance-reviewer 仲裁
3. **共享上下文**：所有 agent 引用同一份 `_context.md`，改项目信息只改一个文件
4. **Product Owner 有修改权**：可修改设计细节，但核心目标不可变，所有变更记录在 `CHANGELOG.md`
5. **内容覆盖优先于文档形式**：不规定文件数量和格式，只检查必须内容是否存在
6. **终审只判不验**：acceptance-reviewer 综合所有报告做判决，不重复执行其他 agent 的检查
7. **浏览器测试在主会话执行**：smoke-tester 和 uiux-qa 需要 Chrome MCP 工具做运行时测试。MCP 工具绑定在主会话，子 agent（`Agent` tool 派发的）无法访问。因此这两个 agent 的浏览器测试阶段必须在主会话中顺序执行，不能委派给子 agent。代码审查阶段仍可并行委派。

## 架构

```
本 Skill 目录结构：
~/.claude/skills/az-delivery-team/
├── SKILL.md              ← 你正在读的文件（编排逻辑）
└── templates/            ← 通用模板（不含任何项目细节）
    ├── product-owner.md
    ├── project-architect.md
    ├── domain-engineer.md      ← 模板，按领域实例化 N 份
    ├── smoke-tester.md
    ├── api-tester.md
    ├── security-auditor.md
    ├── red-team.md
    ├── uiux-qa.md
    ├── performance-auditor.md
    ├── launch-readiness.md
    └── acceptance-reviewer.md

执行后生成：
目标项目/
├── .claude/
│   ├── agents/
│   │   ├── _context.md               ← 共享项目上下文（所有 agent 引用）
│   │   ├── product-owner.md          ← 定义层
│   │   ├── project-architect.md      ← 定义层
│   │   ├── {{domain}}-engineer.md    ← 实施层 × N 个领域
│   │   ├── smoke-tester.md           ← 验证-功能组
│   │   ├── api-tester.md             ← 验证-功能组
│   │   ├── security-auditor.md       ← 验证-安全组
│   │   ├── red-team.md               ← 验证-安全组
│   │   ├── uiux-qa.md               ← 验证-质量组
│   │   ├── performance-auditor.md    ← 验证-质量组
│   │   ├── launch-readiness.md       ← 验证-质量组
│   │   └── acceptance-reviewer.md    ← 终审
│   ├── reports/                       ← 验证报告存放目录
│   │   └── (各 agent 自动写入)
│   ├── AGENTS.md                      ← 团队索引
│   └── CHANGELOG.md                   ← 设计变更日志
```

### 三层结构

```
┌─────────────────────────────────────────────────────┐
│ 第一层：定义（做什么）                                 │
│  product-owner         project-architect             │
│  需求+验收标准          系统设计+领域边界+API契约        │
└──────────────────────┬──────────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────────┐
│ 第二层：实施（怎么做）                                 │
│  {{domain}}-engineer × N（按领域实例化）               │
│  每个全栈负责：前端+后端+API+DB+测试+依赖管理           │
│  遵循 TDD 流程：RED → GREEN → REFACTOR               │
└──────────────────────┬──────────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────────┐
│ 第三层：验证 — 多维度对抗式交叉验证                     │
│                                                       │
│  功能验证组:                                           │
│    smoke-tester    — 核心流程冒烟 + 截图取证            │
│    api-tester      — API 契约/边界/错误码               │
│                                                       │
│  安全对抗组:                                           │
│    security-auditor — OWASP Top 10 + 认证 + 密钥扫描   │
│    red-team    ←──对抗──→ 所有其他验证 agent            │
│                                                       │
│  质量审计组:                                           │
│    uiux-qa          — 视觉走查 + 信息传达 + UX 审查    │
│    performance-auditor — Core Web Vitals + 包体积      │
│    launch-readiness  — SEO + 可访问性 + 合规 + HTTPS   │
│                                                       │
│  终审:                                                 │
│    acceptance-reviewer — 综合全部 7 份报告，仲裁，GO/NO-GO│
└─────────────────────────────────────────────────────┘
```

### 验证前置条件（Phase 2 之前必须检查）

在启动任何验证 agent 之前，编排者必须确认环境就绪：

```
前置条件检查清单：

1. 运行时环境（影响 smoke-tester、uiux-qa）
   □ Docker 是否已启动？运行 `docker compose ps` 确认
   □ 前端页面是否可访问？curl http://localhost:3000
   □ 后端 API 是否可访问？curl http://localhost:8000/api/health
   → 如果未启动：先 `docker compose up -d`，等待健康检查通过
   → 如果无法启动：标记 smoke-tester 和 uiux-qa 为"仅代码审查模式"

2. Chrome MCP 可用性（影响 smoke-tester、uiux-qa 的浏览器测试）
   □ Chrome 浏览器是否在运行？
   □ MCP 扩展是否已连接？调用 tabs_context_mcp 确认
   → 如果不可用：浏览器测试阶段改为 curl + 代码审查
   → 报告中明确标注"⚠️ 未进行浏览器运行时测试"

3. 依赖安装（影响所有验证 agent）
   □ 后端依赖已安装？`cd backend && pip list | head -5`
   □ 前端依赖已安装？`cd frontend && ls node_modules/.package-lock.json`
   → 如果未安装：先安装再验证
```

**Agent 派发策略（基于前置条件）：**

| Agent | 需要运行时 | 需要 Chrome | 派发方式 |
|-------|-----------|------------|---------|
| api-tester | ❌ | ❌ | 子 agent（可并行） |
| security-auditor | ❌ | ❌ | 子 agent（可并行） |
| red-team | ❌ | ❌ | 子 agent（可并行） |
| performance-auditor | ❌ | ❌ | 子 agent（可并行） |
| launch-readiness | ❌ | ❌ | 子 agent（可并行） |
| smoke-tester | ✅ 代码审查 + ✅ 运行时 | ✅ 浏览器测试 | 代码审查→子 agent；浏览器测试→**主会话顺序执行** |
| uiux-qa | ✅ 代码审查 + ✅ 运行时 | ✅ 浏览器测试 | 代码审查→子 agent；浏览器测试→**主会话顺序执行** |

**推荐执行顺序：**
1. 先并行派发 5 个不需要运行时的子 agent + smoke-tester 和 uiux-qa 的代码审查部分
2. 同时在主会话启动 Docker（如果需要）
3. Docker 就绪后，在主会话用 Chrome 顺序执行 smoke-tester 和 uiux-qa 的浏览器测试
4. 等全部完成后启动 acceptance-reviewer

### 对抗式交叉验证流程

```
domain-engineer 完成实施
       │
       ├──→ 功能验证组（可并行）：
       │     smoke-tester：核心流程能跑通吗？有截图证据吗？
       │     api-tester：API 契约正确吗？
       │
       ├──→ 安全对抗组（可并行）：
       │     security-auditor：有已知漏洞类别吗？
       │     red-team：我能搞坏它吗？能挑战其他 agent 的 PASS 吗？
       │
       ├──→ 质量审计组（可并行）：
       │     uiux-qa：看起来对吗？用户理解得了吗？
       │     performance-auditor：够快吗？
       │     launch-readiness：SEO/可访问性/合规就绪吗？
       │
       └──→ acceptance-reviewer：综合全部 7 份报告
                  │
                  ├── 检查报告完整性：7 份都到齐了吗？
                  ├── 如果任何 agent 之间结论矛盾
                  │   → 必须仲裁：说明采信哪个、为什么
                  ├── 加权评估：安全问题 > 功能问题 > 质量问题
                  └── 给出 GO / CONDITIONAL GO / NO-GO
```

### 报告约定

所有验证 agent 将报告保存到 `.claude/reports/`：

| Agent | 报告文件名 |
|-------|-----------|
| smoke-tester | `smoke-tester.md` |
| api-tester | `api-tester.md` |
| security-auditor | `security-auditor.md` |
| red-team | `red-team.md` |
| uiux-qa | `uiux-qa.md` |
| performance-auditor | `performance-auditor.md` |
| launch-readiness | `launch-readiness.md` |
| acceptance-reviewer | `acceptance-review.md` |

acceptance-reviewer 运行前先检查这个目录，缺失的报告 = 降低判决置信度。

### 迭代验证

验证不是一次性的。NO-GO 之后，修复 → 重跑验证 → 再判决，直到 GO。

```
第 1 轮：验证 → NO-GO（8 个 blocker）
  ↓ domain-engineer 修复
第 2 轮：验证 → NO-GO（3 个 still open, 2 个 new）
  ↓ domain-engineer 修复
第 3 轮：验证 → GO（全部 fixed, 0 new）
```

**每个验证 agent 内置 Issue Tracking：**
- 运行前检查 `.claude/reports/` 是否有旧报告
- 如果有，对比旧报告的 findings，标记每个 issue 的状态：NEW / FIXED / STILL OPEN / REGRESSED
- acceptance-reviewer 聚合所有报告的 Issue Tracking 数据，给出迭代进度统计

**报告覆盖策略：** 报告文件名不变（每轮覆盖），issue 状态变化体现在报告内的 Issue Tracking 表中。

### 项目类型适配

Step 1 收集的项目类型会影响 Step 4 生成哪些 agent。不是所有项目都需要全部 agent。

| Agent | Web 全栈 | API 服务 | 移动端 | 静态站点 |
|-------|---------|---------|-------|---------|
| product-owner | ✅ | ✅ | ✅ | ✅ |
| project-architect | ✅ | ✅ | ✅ | ✅ |
| domain-engineer | ✅ | ✅ | ✅ | ✅ |
| smoke-tester | ✅ | ✅ 仅 API 测试 | ✅ | ✅ 仅页面可达性 |
| api-tester | ✅ | ✅ | ✅ | ❌ 无 API |
| security-auditor | ✅ | ✅ | ✅ | ⚠️ 仅依赖扫描 |
| red-team | ✅ | ✅ | ✅ | ⚠️ 范围缩小 |
| uiux-qa | ✅ | ❌ 无 UI | ✅ | ✅ |
| performance-auditor | ✅ | ✅ 聚焦 API 延迟 | ✅ | ✅ 聚焦页面加载 |
| launch-readiness | ✅ | ⚠️ 跳过 SEO | ✅ | ✅ |

**标记说明：**
- ✅ = 正常生成
- ❌ = 不生成该 agent
- ⚠️ = 生成但在 `_context.md` 中注明跳过的部分

在 `_context.md` 中添加一行：`项目类型: [type]`，agent 根据此字段自动调整检查范围。

### _context.md 维护

`_context.md` 分为**稳定区**和**动态区**：

**稳定区（setup 时写入，很少变）：**
- 项目名称和简介
- 项目类型
- 技术栈
- 领域划分表
- 设计文档路径

**动态区（标注"从代码读取"，不硬编码）：**
- API 端点列表 → 注明"从 `app/api/` 或路由文件读取"
- 页面路由列表 → 注明"从 `app/` 目录结构读取"
- 环境变量清单 → 注明"从 `.env.example` 读取"

**维护责任：**
- product-owner 在修改设计文档时同步更新 `_context.md` 的稳定区
- `_context.md` 顶部包含 `Last Updated: [date]` 字段
- 如果 agent 发现 `_context.md` 的 Last Updated 超过 30 天，在报告中标记一个 WARNING

### 跨域协调

多域项目中，跨域决策和接口变更需要一个共享的协调记录。

**文件：** `.claude/agents/_cross-domain.md`

**格式：**
```markdown
# Cross-Domain Coordination Log

## Active Decisions
| Date | Decision | Affected Domains | Decided By | Status |
|------|----------|-----------------|------------|--------|
| 2026-04-11 | Auth token format changed to JWT | auth, core, billing | project-architect | Active |

## Interface Changes
| Date | Changed By | Interface | What Changed | Downstream Domains | Notified? |
|------|-----------|-----------|-------------|-------------------|-----------|
| 2026-04-11 | auth-engineer | POST /api/auth/login response | Added `refresh_token` field | core, billing | Yes |
```

**使用规则：**
- **project-architect** 在做跨域决策时写入 Active Decisions
- **domain-engineer** 在修改被其他域消费的接口时写入 Interface Changes
- **domain-engineer** 开工前必读此文件，检查是否有影响自己域的变更
- 如果需要同时修改多个域，由 project-architect 协调顺序

## 工作流

### Step 1: 确认项目信息与执行模式

使用 AskUserQuestion 收集（合并为 1-2 个问题，尽量自动检测、预填）：

```
🏗️ 项目团队设置

请确认以下信息：

1️⃣ 项目目录：[auto-detect from cwd]
2️⃣ 项目名称和简介：
3️⃣ 项目类型：Web 全栈 / 移动端 / API 服务 / 其他
4️⃣ 技术栈：
   例：Next.js + FastAPI + PostgreSQL
5️⃣ 设计文档路径（可以是一个文件也可以是多个）：
6️⃣ 部署地址（如已部署）：
7️⃣ 是否已有代码？（是/否）
   如果是：已有代码覆盖了哪些功能？
```

**额外必须确认执行模式（影响流程走向）：**

| 模式 | 适用场景 | 流程 |
|------|---------|------|
| **仅检验** | 已有项目质量审计、上线前评估 | Setup → 验证(Phase 2) → 终审(Phase 3) → 输出报告并结束 |
| **检验+修复** | 已有项目质量提升 | Setup → 验证 → 终审 → 如果 NO-GO：修复 → 重新验证 → 循环直到 GO |
| **完整交付** | 新项目从零开始 | Phase 0 → Phase 1(实施) → Phase 2(验证) → Phase 3(终审) → 循环 |

如果用户说"质量检验/审计/评估"，默认**仅检验**模式。
如果用户说"质量检验并修复"或"做到 GO"，默认**检验+修复**模式。
如果用户说"交付/实施/开发"，默认**完整交付**模式。

### Step 2: 确认领域划分

使用 AskUserQuestion 收集领域信息：

```
📐 领域划分

按业务领域划分全栈工程师（不是按前端/后端）。
每个领域的工程师负责该领域的全部代码：前端页面、后端API、数据库、测试。

请定义 2-4 个领域：

例（电商项目）：
- orders: 订单系统（下单、支付、退款、物流）
- catalog: 商品目录（商品、分类、搜索、推荐）
- accounts: 账户系统（注册、登录、个人中心、权限）

每个领域请提供：
- 领域名称（英文，用于 agent 文件名）
- 一句话描述
- 拥有的功能/页面/API
- 依赖的其他领域
- 关键文件/目录
```

### Step 3: 创建共享上下文 `_context.md`

在目标项目的 `.claude/agents/` 下创建 `_context.md`。注意区分稳定区和动态区：

```markdown
# Project Context
> Last Updated: [date]

## 稳定区（直接写入）
- 项目名称：
- 项目类型：[Web 全栈 / API 服务 / 移动端 / 静态站点]
- 技术栈：
- 设计文档路径：
- 部署地址：
- 核心用户流程：（3-5 条）
- 领域划分表：

## 动态区（从代码读取，不硬编码）
- API 端点列表：从 `[路由目录]` 读取
- 页面路由列表：从 `[app 目录]` 读取
- 环境变量清单：从 `.env.example` 读取
- 目录结构：运行 `ls` 或 `tree` 获取
```

所有 agent 的模板中都有一行：
> 读取 `.claude/agents/_context.md` 了解项目全貌。

### Step 4: 创建 Agent 文件

1. 读取 `templates/` 目录下的 11 个模板
2. **根据项目类型裁剪 agent 集合**（参见上方"项目类型适配"矩阵）：
   - 标记为 ❌ 的 agent 不生成
   - 标记为 ⚠️ 的 agent 正常生成，但在 `_context.md` 中注明跳过的部分
3. 对于 `domain-engineer.md` 模板：按 Step 2 的领域数量实例化 N 份
   - 替换 `{{DOMAIN}}` 为领域名
   - 替换 `{{DOMAIN_DESCRIPTION}}` 等占位符为领域具体信息
4. 对于其他模板：注入项目上下文引用
5. 写入目标项目的 `.claude/agents/` 目录
6. 创建 `.claude/agents/_cross-domain.md`（跨域协调日志，参见上方"跨域协调"）
7. 创建 `.claude/reports/` 目录（空目录，验证 agent 写入报告用）
8. 创建 `.claude/CHANGELOG.md`（空文件，供 product-owner 记录设计变更）

### Step 5: 交接检查（Phase 0）

创建完 agent 文件后，**先跑交接检查再开始实施**：

1. 运行 **product-owner** agent — 业务侧 Readiness Check：
   - 核心目标是否清晰、不含歧义？
   - 用户流程是否有可测试的验收标准？
   - 有没有"没人决定过"的隐含假设？

2. 运行 **project-architect** agent — 技术侧 Readiness Check：
   - 架构是否可落地？技术栈是否明确？
   - API 契约是否够详细让 api-tester 测试？
   - 数据模型是否有遗漏？领域边界是否清楚？

3. **如果是已有代码的项目，额外检查：**
   - 代码实现与文档描述是否一致？（drift 检测）
   - 哪些设计决策已体现在代码中但未写入文档？（隐性知识提取）
   - 现有代码的技术债务和约束是什么？

两人各出 Readiness Report → **都 PASS 才开始实施**。如果任一 FAIL，先修补设计文档。

### Step 6: 创建项目 AGENTS.md 索引

在项目 `.claude/` 下创建 `AGENTS.md`：

```markdown
# Project Team

> Skill version: 3.0 | Generated: [date]

## 团队结构

### 第一层：定义（2 人）
| Agent | 角色 | 何时使用 |
|-------|------|---------|
| product-owner | 产品负责人 | 开工前定义需求和验收标准 |
| project-architect | 项目架构师 | 架构决策、跨域协调 |

### 第二层：实施（N 人）
| Agent | 角色 | 何时使用 |
|-------|------|---------|
| {{domain}}-engineer | {{domain}} 全栈工程师 | 该领域的功能开发（TDD） |

### 第三层：验证（8 人，3 组 + 终审）

#### 功能验证组
| Agent | 角色 | 维度 |
|-------|------|------|
| smoke-tester | 冒烟测试 + 截图取证 | 核心流程能跑通吗？有证据吗？ |
| api-tester | API 测试 | 契约/边界/错误码正确吗？ |

#### 安全对抗组
| Agent | 角色 | 维度 |
|-------|------|------|
| security-auditor | 安全审计 | OWASP Top 10 + 密钥扫描 |
| red-team | 红队对抗 | 攻击 + 质疑 + 交叉验证全部 agent |

#### 质量审计组
| Agent | 角色 | 维度 |
|-------|------|------|
| uiux-qa | UI/UX 审查 | 布局 + 信息传达 + 用户体验 |
| performance-auditor | 性能审计 | Core Web Vitals + 包体积 |
| launch-readiness | 上线就绪 | SEO + 可访问性 + 合规 |

#### 终审
| Agent | 角色 | 维度 |
|-------|------|------|
| acceptance-reviewer | 验收仲裁 | 综合全部 7 份报告，GO/NO-GO |

## 执行节奏

```
Phase 0: 交接检查
  product-owner + project-architect → Readiness Report
  都 PASS 才继续

Phase 1: 实施
  {{domain}}-engineer × N（按领域并行）

Phase 2: 验证（3 组可并行）
  ┌─ 功能验证组: smoke-tester + api-tester
  ├─ 安全对抗组: security-auditor + red-team
  └─ 质量审计组: uiux-qa + performance-auditor + launch-readiness

Phase 3: 终审
  acceptance-reviewer → 读取 .claude/reports/ 下全部 7 份报告
  → GO / CONDITIONAL GO / NO-GO
```

## 报告目录

所有验证报告保存在 `.claude/reports/`。
acceptance-reviewer 运行前检查报告完整性，缺失的报告会降低判决置信度。

## 交叉验证规则

1. 验证层 7 个 agent 独立工作，结论可以矛盾
2. red-team 有权挑战任何其他 agent 的 PASS 判定
3. 矛盾时由 acceptance-reviewer 仲裁并说明理由
4. 仲裁加权：安全问题 > 功能问题 > 质量问题
5. 任何 agent 发现核心流程 FAIL = 阻塞项，不可忽略

## 与插件 Agent 的关系

插件的通用 agent（code-reviewer、security-reviewer、tdd-guide 等）
负责代码层面的质量。以上项目 agent 负责产品交付质量。两者互补，不替代。
domain-engineer 可在实施中调用这些全局 agent。
```

### Step 7: 输出总结 + 交付脚本

1. 拷贝 `delivery.sh` 到项目根目录并设为可执行
2. 创建 `.claude/delivery.json`（从 `delivery.json.example` 复制，填入项目名和设计文档路径）
3. 创建 `.claude/progress.txt`（空模板，含 Codebase Patterns 占位段）

输出：

```
✅ 已创建项目交付团队（3 层 10+N 角色）：

📋 定义层：
  1. product-owner        — 需求定义 + 验收标准 + Story 拆解
  2. project-architect     — 系统设计 + 领域边界

🔧 实施层：
  3. {{domain}}-engineer   — {{domain}} 领域全栈工程师（TDD）
  ...（列出所有领域）

🔍 验证层 — 功能验证组：
  N. smoke-tester         — 核心流程冒烟 + 截图取证
  N. api-tester           — API 契约/边界测试

🛡️ 验证层 — 安全对抗组：
  N. security-auditor     — OWASP Top 10 + 密钥扫描
  N. red-team             — 对抗式攻击 + 全员交叉验证

✨ 验证层 — 质量审计组：
  N. uiux-qa            — 布局 + 信息传达 + 用户体验
  N. performance-auditor  — 性能 + Core Web Vitals
  N. launch-readiness     — SEO + 可访问性 + 合规

⚖️ 终审：
  N. acceptance-reviewer  — 综合 7 份报告，仲裁冲突，GO/NO-GO + findings→Story 转化

共享上下文：.claude/agents/_context.md
状态文件：.claude/delivery.json
进度日志：.claude/progress.txt
报告目录：.claude/reports/
团队索引：.claude/AGENTS.md

>>> 两种交付方式：

  🤖 自动交付（推荐）：
    ./delivery.sh [--max-rounds 5]
    全自动运行 Phase 0→1→2→3，NO-GO 自动修复→重验。

  🖐️ 手动交付：
    按原有方式逐个调度 agent。
    Phase 0 → Phase 1 → Phase 2 → Phase 3
```

## 版本与迁移

### 当前版本

Skill version: **3.1** (2026-04-12)

每个生成的 `AGENTS.md` 文件会标注生成时使用的 Skill 版本。

### 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 3.1 | 2026-04-12 | 三项设计修复：(1) Chrome MCP 限制 — 浏览器测试必须在主会话执行，不可委派子 agent；(2) 执行模式选择 — 区分"仅检验""检验+修复""完整交付"三种模式；(3) 验证前置条件检查 — 启动验证前确认 Docker/Chrome/依赖是否就绪，附 agent 派发策略矩阵 |
| 3.0 | 2026-04-12 | 自动交付循环（delivery.sh + delivery.json）：Phase 状态机自动编排；Ralph 式 Story 粒度实施循环（fresh context per Story）；跨域并行调度；NO-GO findings 自动转化为 FIX Story；progress.txt 知识沉淀；断点恢复；不收敛检测（failCount + blocked）；手动/自动两种模式共存 |
| 2.1 | 2026-04-11 | 迭代验证机制（所有验证 agent 支持 Issue Tracking：NEW/FIXED/STILL OPEN/REGRESSED）；项目类型适配矩阵（按类型裁剪 agent）；_context.md 拆分稳定区/动态区 + Last Updated + 维护责任；跨域协调协议（_cross-domain.md + domain-engineer 必读 + project-architect 维护） |
| 2.0 | 2026-04-11 | 合并 e2e-evidence 入 smoke-tester；visual-qa 升级为 uiux-qa（+信息传达+UX）；acceptance-reviewer 改为纯综合判决；red-team 交叉验证扩展到全部 agent；domain-engineer 增加 TDD + self-review；全部 model 升级为 opus；新增报告目录约定；新增 Phase 0 交接检查步骤；新增版本管理 |
| 1.0 | 初始 | 3 层 12 角色初始版本 |

### 迁移已有项目

如果已有项目使用旧版本 agent 文件：

1. 检查差异：对比项目 `.claude/agents/` 中的文件与最新 `templates/`
2. 重点关注：
   - `visual-qa.md` → 应替换为 `uiux-qa.md`
   - `e2e-evidence.md` → 应删除（能力已合并入 `smoke-tester.md`）
   - `acceptance-reviewer.md` → 应更新（职责从"验证+判决"变为"纯判决"）
   - 所有 agent 的 `model` 字段 → 应从 `sonnet` 改为 `opus`
3. 创建 `.claude/reports/` 目录（旧版本没有）
4. 更新 `.claude/AGENTS.md` 中的版本号和团队结构

#### 2.1 → 3.0 迁移

1. 拷贝 `delivery.sh` 到项目根目录：`cp ~/.claude/skills/az-delivery-team/delivery.sh ./`
2. 创建 `.claude/delivery.json`（参考 `delivery.json.example`，填入项目信息）
3. 创建 `.claude/progress.txt`
4. 更新 `product-owner.md`：追加 Story Decomposition (Delivery Mode) 段落
5. 更新 `acceptance-reviewer.md`：追加 Findings → Story Conversion (Delivery Mode) 段落
6. 更新 `domain-engineer.md`：追加 Task Acquisition (Delivery Mode) 段落
7. 其余 agent 文件不需要变更
