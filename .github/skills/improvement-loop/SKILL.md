---
name: improvement-loop
description: Diagnose and fix agent failures using the systematic improvement loop. Use when an agent makes a mistake, misses a requirement, or after any significant task.
---

# Improvement Loop

Every agent miss is a learning opportunity. The goal is to design an environment where the easiest path is the correct one.

## The loop

1. Capture the miss: what did the agent do, what should it have done, and what did reality say?
2. Diagnose what it could not see: missing observability, instructions, tooling, guardrails, or verification.
3. Choose the smallest useful primitive.
4. Encode it as a version-controlled artifact.
5. Promote repeated or high-risk misses into gates.

## Primitive map

| Diagnosis | Artifact |
| --- | --- |
| Missing project knowledge | Update `AGENTS.md`, `README.md`, or `docs/` |
| Missing queue knowledge | Update `AGENTS.md` or relevant product docs |
| Missing verification | Add or improve a test, script, checklist, or CI gate |
| Too much freedom | Add a guardrail or require human approval |
| Missing runtime visibility | Add logging, diagnostics, screenshots, or debug commands |

## Promotion rule

If the same class of miss happens twice, consider promoting the fix from guidance to a gate. Good gates are cheap, deterministic, and tied to real risk.
