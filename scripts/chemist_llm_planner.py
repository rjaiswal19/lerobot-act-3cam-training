#!/usr/bin/env python3
"""Short-horizon autonomous chemist demo planner.

The planner composes trained LeRobot skills. It never emits joint targets; it
only selects the next known skill, runs the existing rollout wrapper, verifies,
and then asks for the next skill.
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT_DIR = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = ROOT_DIR / "configs" / "demos" / "chemist_mix.env"
PRIVATE_ENV = ROOT_DIR / ".env"


@dataclass(frozen=True)
class Skill:
    skill_id: str
    task: str
    instruction: str
    duration_s: float
    verify_prompt: str


@dataclass(frozen=True)
class PlannerDecision:
    skill_id: str | None
    reason: str


def parse_bool(value: str | None, default: bool = False) -> bool:
    if value is None or value == "":
        return default
    return value.lower() in {"1", "true", "yes", "on"}


def parse_float(value: str | None, default: float) -> float:
    if value is None or value == "":
        return default
    return float(value)


def parse_int(value: str | None, default: int) -> int:
    if value is None or value == "":
        return default
    return int(value)


def load_env_file(path: Path) -> None:
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key or key in os.environ:
            continue
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        os.environ[key] = value


def build_skills() -> dict[str, Skill]:
    pour_duration = parse_float(os.environ.get("CHEMIST_POUR_DURATION_S"), 35.0)
    swirl_duration = parse_float(os.environ.get("CHEMIST_SWIRL_DURATION_S"), 25.0)
    return {
        "pour_blue_to_green": Skill(
            skill_id="pour_blue_to_green",
            task="pour_blue_to_green",
            instruction="Pick up the blue beaker and pour it into the green beaker",
            duration_s=pour_duration,
            verify_prompt="blue liquid is in the green beaker and the arm is clear",
        ),
        "pour_yellow_to_green": Skill(
            skill_id="pour_yellow_to_green",
            task="pour_yellow_to_green",
            instruction="Pick up the yellow beaker and pour it into the green beaker",
            duration_s=pour_duration,
            verify_prompt="yellow liquid is in the green beaker and the arm is clear",
        ),
        "swirl_green_beaker": Skill(
            skill_id="swirl_green_beaker",
            task="swirl_green_beaker",
            instruction="Pick up the green beaker and swirl it without spilling",
            duration_s=swirl_duration,
            verify_prompt="the green beaker has been swirled and remains upright",
        ),
    }


def legal_next_skill(completed: list[str]) -> str | None:
    completed_set = set(completed)
    pour_skills = ["pour_blue_to_green", "pour_yellow_to_green"]
    remaining_pours = [skill for skill in pour_skills if skill not in completed_set]
    if remaining_pours:
        return remaining_pours[0]
    if "swirl_green_beaker" not in completed_set:
        return "swirl_green_beaker"
    return None


def is_legal_decision(skill_id: str | None, completed: list[str]) -> bool:
    if skill_id is None:
        return legal_next_skill(completed) is None
    completed_set = set(completed)
    if skill_id in completed_set:
        return False
    if skill_id == "swirl_green_beaker":
        return {"pour_blue_to_green", "pour_yellow_to_green"}.issubset(completed_set)
    return skill_id in {"pour_blue_to_green", "pour_yellow_to_green"}


class FixedPlanner:
    def next_decision(
        self,
        goal: str,
        skills: dict[str, Skill],
        completed: list[str],
        last_status: str,
    ) -> PlannerDecision:
        del goal, skills, last_status
        return PlannerDecision(
            skill_id=legal_next_skill(completed),
            reason="fixed single-arm order with verification between skills",
        )


class OpenAIResponsesPlanner:
    def __init__(self, model: str) -> None:
        self.model = model
        self.api_key = os.environ.get("OPENAI_API_KEY", "")
        self.base_url = os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1").rstrip("/")
        if not self.api_key:
            raise RuntimeError("OPENAI_API_KEY is required for CHEMIST_PLANNER_MODE=llm")

    def next_decision(
        self,
        goal: str,
        skills: dict[str, Skill],
        completed: list[str],
        last_status: str,
    ) -> PlannerDecision:
        payload = {
            "model": self.model,
            "instructions": (
                "You are a short-horizon planner for a single-arm robot chemistry demo. "
                "Choose exactly one next skill from the provided skill IDs. "
                "Never invent skills, never output robot joint targets, and keep swirl last. "
                "If all skills are complete, return null for next_skill_id."
            ),
            "input": json.dumps(
                {
                    "goal": goal,
                    "completed_skill_ids": completed,
                    "last_status": last_status,
                    "available_skills": [
                        {
                            "skill_id": skill.skill_id,
                            "instruction": skill.instruction,
                            "verification": skill.verify_prompt,
                        }
                        for skill in skills.values()
                    ],
                    "constraints": [
                        "single arm",
                        "pour both source beakers before swirling the green beaker",
                        "verify after every skill before selecting the next skill",
                    ],
                },
                indent=2,
            ),
            "text": {
                "format": {
                    "type": "json_schema",
                    "name": "chemist_next_skill",
                    "strict": True,
                    "schema": {
                        "type": "object",
                        "additionalProperties": False,
                        "properties": {
                            "next_skill_id": {
                                "type": ["string", "null"],
                                "enum": [
                                    "pour_blue_to_green",
                                    "pour_yellow_to_green",
                                    "swirl_green_beaker",
                                    None,
                                ],
                            },
                            "reason": {"type": "string"},
                        },
                        "required": ["next_skill_id", "reason"],
                    },
                }
            },
            "max_output_tokens": 300,
        }
        data = self._post_json(f"{self.base_url}/responses", payload)
        text = extract_response_text(data)
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError as exc:
            raise RuntimeError(f"LLM planner returned non-JSON output: {text!r}") from exc
        skill_id = parsed.get("next_skill_id")
        reason = parsed.get("reason", "llm decision")
        if not is_legal_decision(skill_id, completed):
            raise RuntimeError(f"LLM planner returned illegal next skill {skill_id!r}")
        return PlannerDecision(skill_id=skill_id, reason=reason)

    def _post_json(self, url: str, payload: dict[str, Any]) -> dict[str, Any]:
        body = json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            url,
            data=body,
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"LLM planner HTTP {exc.code}: {detail}") from exc


def extract_response_text(data: dict[str, Any]) -> str:
    if isinstance(data.get("output_text"), str):
        return data["output_text"]
    chunks: list[str] = []
    for item in data.get("output", []):
        for content in item.get("content", []):
            if content.get("type") in {"output_text", "text"} and isinstance(content.get("text"), str):
                chunks.append(content["text"])
    if chunks:
        return "".join(chunks)
    raise RuntimeError(f"Could not find text in LLM response keys: {sorted(data.keys())}")


def choose_planner(mode: str) -> tuple[Any, str]:
    if mode == "fixed":
        return FixedPlanner(), "fixed"
    if mode == "llm":
        model = os.environ.get("CHEMIST_LLM_MODEL", "gpt-4.1-mini")
        return OpenAIResponsesPlanner(model), f"llm:{model}"
    if mode == "auto" and os.environ.get("OPENAI_API_KEY"):
        model = os.environ.get("CHEMIST_LLM_MODEL", "gpt-4.1-mini")
        return OpenAIResponsesPlanner(model), f"llm:{model}"
    return FixedPlanner(), "fixed"


def print_skill_summary(goal: str, planner_name: str, skills: dict[str, Skill]) -> None:
    print(f"Goal: {goal}")
    print(f"Planner: {planner_name}")
    print("Skills:")
    for skill in skills.values():
        print(f"  - {skill.skill_id}: task={skill.task}, duration_s={skill.duration_s:g}")
    print()


def rollout_env_for_skill(skill: Skill) -> dict[str, str]:
    env = os.environ.copy()
    env.update(
        {
            "TASK": skill.task,
            "TEXT": skill.instruction,
            "POLICY_TYPE": os.environ.get("CHEMIST_POLICY_TYPE", "pi05"),
            "ROLLOUT_FPS": os.environ.get("CHEMIST_ROLLOUT_FPS", "5"),
            "ROLLOUT_DURATION_S": str(skill.duration_s),
            "ROLLOUT_INFERENCE_TYPE": os.environ.get("CHEMIST_ROLLOUT_INFERENCE_TYPE", "rtc"),
            "ROLLOUT_RTC_EXECUTION_HORIZON": os.environ.get("CHEMIST_RTC_EXECUTION_HORIZON", "10"),
            "ROLLOUT_RTC_MAX_GUIDANCE_WEIGHT": os.environ.get(
                "CHEMIST_RTC_MAX_GUIDANCE_WEIGHT", "10.0"
            ),
            "ROLLOUT_RTC_QUEUE_THRESHOLD": os.environ.get("CHEMIST_RTC_QUEUE_THRESHOLD", "30"),
            "ROLLOUT_RETURN_TO_INITIAL_POSITION": os.environ.get(
                "CHEMIST_RETURN_TO_INITIAL_POSITION", "true"
            ),
        }
    )
    policy_path = os.environ.get("CHEMIST_ROLLOUT_POLICY_PATH", "")
    if policy_path:
        env["ROLLOUT_POLICY_PATH"] = policy_path
    return env


def run_skill(skill: Skill, dry_run: bool) -> int:
    command = ["bash", str(ROOT_DIR / "scripts" / "rollout_policy.sh")]
    env = rollout_env_for_skill(skill)
    print(f"Next skill: {skill.skill_id}")
    print(f"Instruction: {skill.instruction}")
    print(f"Command: {shlex.join(command)}")
    if dry_run:
        visible_env = {
            key: env[key]
            for key in (
                "TASK",
                "TEXT",
                "POLICY_TYPE",
                "ROLLOUT_FPS",
                "ROLLOUT_DURATION_S",
                "ROLLOUT_INFERENCE_TYPE",
            )
        }
        print(f"Dry-run environment: {json.dumps(visible_env, sort_keys=True)}")
        return 0
    return subprocess.run(command, cwd=ROOT_DIR, env=env, check=False).returncode


def verify_skill(skill: Skill, verify_mode: str, dry_run: bool) -> str:
    if dry_run or verify_mode == "none":
        return "success"
    if verify_mode != "manual":
        raise ValueError(f"Unsupported verification mode: {verify_mode}")
    print()
    print(f"Verify that {skill.verify_prompt}.")
    while True:
        answer = input("Type y to continue, r to retry this skill, or q to abort: ").strip().lower()
        if answer in {"y", "yes"}:
            return "success"
        if answer in {"r", "retry"}:
            return "retry"
        if answer in {"q", "quit", "abort"}:
            return "abort"


def confirm_start(goal: str, confirm: bool, dry_run: bool, yes: bool) -> None:
    if dry_run or yes or not confirm:
        return
    print("This will move the physical robot through multiple autonomous rollouts.")
    print(f"Goal: {goal}")
    answer = input("Type RUN to start: ").strip()
    if answer != "RUN":
        raise SystemExit("Aborted before robot motion.")


def run_demo(args: argparse.Namespace) -> int:
    goal = args.goal or os.environ.get("CHEMIST_GOAL", "")
    if not goal:
        raise SystemExit("CHEMIST_GOAL is empty.")

    skills = build_skills()
    planner_mode = args.planner or os.environ.get("CHEMIST_PLANNER_MODE", "auto")
    planner, planner_name = choose_planner(planner_mode)
    verify_mode = args.verify or os.environ.get("CHEMIST_VERIFY_MODE", "manual")
    max_retries = args.max_retries
    if max_retries is None:
        max_retries = parse_int(os.environ.get("CHEMIST_MAX_RETRIES"), 1)

    print_skill_summary(goal, planner_name, skills)
    confirm_start(
        goal,
        parse_bool(os.environ.get("CHEMIST_CONFIRM_BEFORE_EXECUTION"), True),
        args.dry_run,
        args.yes,
    )

    completed: list[str] = []
    attempts: dict[str, int] = {}
    last_status = "starting"
    pending_retry: str | None = None

    while True:
        if pending_retry is not None:
            decision = PlannerDecision(
                skill_id=pending_retry,
                reason="retrying the last unverified skill before replanning",
            )
            pending_retry = None
        else:
            try:
                decision = planner.next_decision(goal, skills, completed, last_status)
            except Exception as exc:
                if planner_mode == "llm":
                    raise
                print(f"Planner fallback: {exc}")
                decision = FixedPlanner().next_decision(goal, skills, completed, last_status)

        if decision.skill_id is None:
            print("Demo complete.")
            return 0
        if not is_legal_decision(decision.skill_id, completed):
            raise RuntimeError(f"Planner selected illegal skill {decision.skill_id!r}")

        skill = skills[decision.skill_id]
        print(f"Planner reason: {decision.reason}")
        attempts[skill.skill_id] = attempts.get(skill.skill_id, 0) + 1

        returncode = run_skill(skill, dry_run=args.dry_run)
        if returncode != 0:
            last_status = f"{skill.skill_id} failed with return code {returncode}"
            print(last_status)
        else:
            status = verify_skill(skill, verify_mode, dry_run=args.dry_run)
            if status == "success":
                completed.append(skill.skill_id)
                last_status = f"{skill.skill_id} verified"
                print(f"Verified: {skill.skill_id}")
                print()
                continue
            if status == "abort":
                print("Aborted after verification.")
                return 2
            last_status = f"{skill.skill_id} requested retry"

        if attempts[skill.skill_id] > max_retries:
            print(f"Retry limit exceeded for {skill.skill_id}.")
            return 1
        pending_retry = skill.skill_id
        print(f"Retrying {skill.skill_id} after status: {last_status}")
        time.sleep(1)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--goal", default="")
    parser.add_argument("--planner", choices=["auto", "fixed", "llm"], default="")
    parser.add_argument("--verify", choices=["manual", "none"], default="")
    parser.add_argument("--max-retries", type=int, default=None)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--yes", action="store_true", help="Skip physical-run confirmation prompt.")
    return parser.parse_args()


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(line_buffering=True)
    args = parse_args()
    load_env_file(args.config)
    load_env_file(PRIVATE_ENV)
    return run_demo(args)


if __name__ == "__main__":
    sys.exit(main())
