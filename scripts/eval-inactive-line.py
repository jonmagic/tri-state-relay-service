#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import tempfile

def command_exists(cmd):
    return subprocess.run(["sh", "-c", f"command -v {cmd}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0

def extract_json(text):
    start = text.find('{')
    end = text.rfind('}')
    if start >= 0 and end > start:
        return text[start:end+1]
    return text.strip()

def run_cmd(cmd_args, cwd=None):
    try:
        result = subprocess.run(cmd_args, cwd=cwd, capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        return (e.stdout + e.stderr).strip()

def run_candidate(tool, input_text, root):
    combine_prompt_path = os.path.join(root, 'docs/prompts/combine-inactive-line.md')
    if tool == 'apfel':
        return run_cmd(['apfel', '--system-file', combine_prompt_path, '--max-tokens', '160', '--temperature', '0', '--output', 'plain', input_text], cwd=root)
    elif tool == 'llm':
        with open(combine_prompt_path, 'r') as f:
            combine_prompt = f.read()
        return run_cmd(['llm', 'prompt', input_text, '--system', combine_prompt, '--no-stream', '--no-log'], cwd=root)
    raise Exception(f"unsupported tool: {tool}")

def run_judge(tool, fixture, candidate_text, root):
    judge_input = json.dumps({"fixture": fixture, "candidateText": candidate_text})
    evaluator_prompt_path = os.path.join(root, 'docs/prompts/evaluate-inactive-line.md')
    
    if tool == 'apfel':
        output = run_cmd(['apfel', '--system-file', evaluator_prompt_path, '--max-tokens', '120', '--temperature', '0', '--output', 'plain', judge_input], cwd=root)
    else:
        with open(evaluator_prompt_path, 'r') as f:
            evaluator_prompt = f.read()
        output = run_cmd(['llm', 'prompt', judge_input, '--system', evaluator_prompt, '--no-stream', '--no-log'], cwd=root)
        
    try:
        return json.loads(extract_json(output))
    except:
        return {"score": 0, "verdict": "reject", "reason": f"invalid judge output: {output[:120]}"}

def validate_candidate(candidate_text, expect):
    errors = []
    try:
        candidate = json.loads(extract_json(candidate_text))
    except:
        return {"ok": False, "errors": ["candidate is not valid JSON"]}
        
    for key in ['action', 'type', 'priority', 'message']:
        if key not in candidate:
            errors.append(f"missing {key}")
            
    if candidate.get('action') not in ['drop', 'replace', 'promote']:
        errors.append('invalid action')
    if candidate.get('action') != expect.get('action'):
        errors.append(f"expected action {expect.get('action')}")
    if 'type' in expect and candidate.get('type') != expect.get('type'):
        errors.append(f"expected type {expect.get('type')}")
    if 'priority' in expect and candidate.get('priority') != expect.get('priority'):
        errors.append(f"expected priority {expect.get('priority')}")
    if not isinstance(candidate.get('message'), str):
        errors.append('message is not a string')
    elif len(candidate.get('message')) > 160:
        errors.append('message is longer than 160 chars')
        
    for text in expect.get('mustInclude', []):
        if text.lower() not in candidate.get('message', '').lower():
            errors.append(f"message missing {text}")
            
    for text in expect.get('mustAvoid', []):
        if text.lower() in candidate.get('message', '').lower():
            errors.append(f"message includes {text}")
            
    return {"ok": len(errors) == 0, "errors": errors, "candidate": candidate}

def main():
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    fixtures_path = os.path.join(root, 'evals/inactive-line-fixtures.json')
    output_path = os.path.join(root, 'evals/results/inactive-line-results.json')
    
    with open(fixtures_path, 'r') as f:
        fixtures = json.load(f)
        
    requested_tools = [t.strip() for t in os.environ.get('TSRS_EVAL_TOOLS', 'apfel,llm').split(',') if t.strip()]
    judge_tool = os.environ.get('TSRS_EVAL_JUDGE', 'apfel')
    results = []
    
    for fixture in fixtures:
        for tool in requested_tools:
            if not command_exists(tool):
                results.append({"fixture": fixture['id'], "tool": tool, "ok": False, "error": "tool not found"})
                continue
                
            input_text = json.dumps(fixture['input'])
            candidate_text = run_candidate(tool, input_text, root)
            contract = validate_candidate(candidate_text, fixture['expect'])
            
            if command_exists(judge_tool):
                judge = run_judge(judge_tool, fixture, candidate_text, root)
            else:
                judge = {"score": 0, "verdict": "reject", "reason": "judge tool not found"}
                
            is_ok = contract['ok'] and judge.get('verdict') == 'keep' and int(judge.get('score', 0)) >= 7
            
            results.append({
                "fixture": fixture['id'],
                "tool": tool,
                "ok": is_ok,
                "contract": contract,
                "judge": judge,
                "candidateText": candidate_text
            })
            
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'w') as f:
        json.dump(results, f, indent=2)
        f.write('\n')
        
    print('| Scenario | Tool | Contract | Judge | Score | Candidate |')
    print('| --- | --- | --- | --- | ---: | --- |')
    
    for item in results:
        contract_str = 'pass' if item.get('contract', {}).get('ok') else 'fail'
        judge_str = item.get('judge', {}).get('verdict', 'n/a')
        score = item.get('judge', {}).get('score', 0)
        
        msg = item.get('error')
        if not msg and 'contract' in item and 'candidate' in item['contract']:
            msg = item['contract']['candidate'].get('message')
        if not msg:
            msg = item.get('candidateText')
            
        msg_str = str(msg).replace('|', '\\|')
        print(f"| {item['fixture']} | {item['tool']} | {contract_str} | {judge_str} | {score} | {msg_str} |")
        
    print(f"\nWrote {output_path}")

if __name__ == '__main__':
    main()
