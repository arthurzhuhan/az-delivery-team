# Delivery Team

![Delivery Team](hero.webp)

An autonomous multi-agent delivery system for Claude Code. Throw in a design doc, go to sleep, wake up to a GO/NO-GO report.

## How It Works

```
Design Doc ──> delivery.sh
                  |
          Phase 0: Readiness Check
          Product Owner + Architect review design
          PO decomposes into Stories
          You review the Story list (or --auto-approve-stories)
                  |
          Phase 1: Implementation (Story-by-Story)
          One Story per claude invocation (fresh context)
          TDD: test first, then implement
          Cross-domain: parallel by domain, serial within
                  |
          Phase 2: Verification (7 agents in parallel)
          smoke-tester | api-tester | security-auditor
          red-team | uiux-qa | performance-auditor | launch-readiness
                  |
          Phase 3: Acceptance Review
          Synthesize 7 reports, arbitrate conflicts
          GO ──> done!
          NO-GO ──> findings become FIX Stories ──> back to Phase 1
```

## The Team (3 Layers, 10+N Roles)

### Layer 1: Define (what to build)
| Agent | Role |
|-------|------|
| product-owner | Guards core goals, decomposes design into Stories, logs all changes |
| project-architect | System design, domain boundaries, cross-domain coordination |

### Layer 2: Implement (how to build)
| Agent | Role |
|-------|------|
| {domain}-engineer x N | Full-stack engineer per business domain (TDD workflow) |

### Layer 3: Verify (adversarial cross-validation)
| Agent | Role |
|-------|------|
| smoke-tester | Core flow testing + screenshot evidence |
| api-tester | API contract / boundary / error code testing |
| security-auditor | OWASP Top 10 + secrets scan + dependency audit |
| red-team | Adversarial attacks + challenges any agent's PASS |
| uiux-qa | Layout + information architecture + UX review |
| performance-auditor | Core Web Vitals + bundle size + API latency |
| launch-readiness | SEO + accessibility + compliance + HTTPS |
| acceptance-reviewer | Synthesizes all 7 reports, arbitrates conflicts, GO/NO-GO |

## Quick Start

### 1. Install the skill

```bash
# Copy to your Claude Code skills directory
cp -r . ~/.claude/skills/az-delivery-team/
```

### 2. Set up a project

In Claude Code, run:
```
/az-delivery-team
```

Answer the prompts (project info, domain split). The skill creates agent files in your project's `.claude/agents/` directory.

### 3. Run the delivery loop

```bash
# Interactive mode (review stories before implementation)
./delivery.sh

# Full auto mode
./delivery.sh --auto-approve-stories

# Custom max rounds
./delivery.sh --max-rounds 3
```

## Key Concepts

### Fresh Context Per Story

Each Story is implemented by a fresh `claude` invocation with zero context carryover. Memory persists only through files:
- `delivery.json` — task state (which Stories pass/fail)
- `progress.txt` — accumulated codebase knowledge (patterns, gotchas)
- `.claude/reports/` — verification reports with issue tracking
- Git history — code changes

### Adversarial Verification

Seven verification agents work independently. Their conclusions CAN contradict each other. The red-team agent has the right to challenge any other agent's PASS. The acceptance-reviewer arbitrates conflicts and makes the final call.

### Self-Healing Loop

NO-GO findings automatically become new FIX Stories. The loop continues until GO or max rounds. Stories that fail 3+ times get marked `blocked` for human intervention.

### Story Review Checkpoint

After Phase 0, the script pauses to let you review the Story list before implementation begins. Edit `delivery.json` if needed, then press Enter. Skip with `--auto-approve-stories`.

## State File: delivery.json

```json
{
  "project": "MyProject",
  "designDocs": ["docs/design.md"],
  "maxRounds": 5,
  "currentPhase": "phase0",
  "round": 1,
  "stories": [
    {
      "id": "US-001",
      "domain": "orders",
      "title": "Add order creation endpoint",
      "passes": false,
      "source": "prd",
      "failCount": 0,
      "blocked": false
    }
  ],
  "verification": {
    "reports": { "smoke-tester": null, ... },
    "verdict": null
  }
}
```

## Safety Features

| Feature | How |
|---------|-----|
| Breakpoint recovery | `currentPhase` persisted in JSON — restart picks up where it left off |
| Stall detection | 3 consecutive batches with zero progress → force into verification |
| Non-convergence | `failCount >= 3` → mark story as `blocked`, skip it |
| Git rollback | Tags `delivery-round-N-start` before each round; rolls back code (preserving state) on total failure |
| Story review gate | Pause after Phase 0 for human review (bypass with `--auto-approve-stories`) |
| Report validation | Phase 2 → Phase 3 only if verification reports were actually produced |

## Project Structure

```
az-delivery-team/
├── SKILL.md                    # Skill definition (Claude Code reads this)
├── delivery.sh                 # The autonomous loop orchestrator
├── delivery.json.example       # State file template
├── README.md                   # You are here
└── templates/                  # Agent prompt templates
    ├── product-owner.md
    ├── project-architect.md
    ├── domain-engineer.md      # Instantiated N times (one per domain)
    ├── smoke-tester.md
    ├── api-tester.md
    ├── security-auditor.md
    ├── red-team.md
    ├── uiux-qa.md
    ├── performance-auditor.md
    ├── launch-readiness.md
    └── acceptance-reviewer.md
```

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)
- `jq` (`brew install jq` on macOS)
- A git repository for your project

## License

MIT

---

# Delivery Team (中文说明)

一个基于 Claude Code 的自主多 Agent 交付系统。扔一个设计文档进去，去睡觉，醒来看 GO/NO-GO 报告。

## 工作原理

```
设计文档 ──> delivery.sh
                |
        Phase 0: 交接检查
        PO + 架构师审查设计文档
        PO 将设计拆解为 Story 列表
        你审核 Story（或 --auto-approve-stories 跳过）
                |
        Phase 1: 实施（逐 Story 循环）
        每个 Story 一次 claude 调用（干净上下文）
        TDD：先写测试，再实现
        跨域并行，域内串行
                |
        Phase 2: 验证（7 个 Agent 并行）
        冒烟测试 | API 测试 | 安全审计
        红队对抗 | UI/UX QA | 性能审计 | 上线就绪
                |
        Phase 3: 终审
        综合 7 份报告，仲裁冲突
        GO ──> 完成！
        NO-GO ──> findings 变成 FIX Story ──> 回到 Phase 1
```

## 团队结构（3 层 10+N 角色）

### 第一层：定义（做什么）
- **product-owner** — 守护核心目标，拆解 Story，记录变更
- **project-architect** — 系统设计，领域边界，跨域协调

### 第二层：实施（怎么做）
- **{domain}-engineer x N** — 按业务领域划分的全栈工程师（TDD）

### 第三层：验证（对抗式交叉验证）
- **smoke-tester** — 核心流程冒烟 + 截图取证
- **api-tester** — API 契约 / 边界 / 错误码
- **security-auditor** — OWASP Top 10 + 密钥扫描
- **red-team** — 攻击 + 质疑任何 Agent 的 PASS
- **uiux-qa** — 布局 + 信息传达 + UX 审查
- **performance-auditor** — Core Web Vitals + 包体积
- **launch-readiness** — SEO + 可访问性 + 合规
- **acceptance-reviewer** — 综合 7 份报告，仲裁，GO/NO-GO

## 快速开始

```bash
# 1. 安装 skill
cp -r . ~/.claude/skills/az-delivery-team/

# 2. 在 Claude Code 中初始化项目
/az-delivery-team

# 3. 运行交付循环
./delivery.sh                          # 交互模式（审核 Story）
./delivery.sh --auto-approve-stories   # 全自动模式
./delivery.sh --max-rounds 3           # 自定义最大轮次
```

## 核心设计

- **每个 Story = 全新上下文** — 避免 LLM 上下文窗口膨胀导致质量下降
- **对抗式验证** — 7 个独立 Agent，结论可以矛盾，红队可以挑战任何 PASS
- **自愈循环** — NO-GO findings 自动变成 FIX Story，循环直到 GO
- **卡住检测** — 连续 3 批无进展 → 强制验证；failCount >= 3 → 标记 blocked
- **断点恢复** — 中断后重跑自动从上次 Phase 继续
- **Git 回滚** — 每轮开始打 tag，全部 blocked 时回滚代码（保留状态文件）

