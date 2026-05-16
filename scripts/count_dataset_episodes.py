#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def count_jsonl(path: Path) -> int:
    with path.open("r", encoding="utf-8") as f:
        return sum(1 for line in f if line.strip())


def count_parquet(path: Path) -> int:
    try:
        import pyarrow.parquet as pq

        return pq.ParquetFile(path).metadata.num_rows
    except Exception:
        try:
            import pandas as pd

            return len(pd.read_parquet(path))
        except Exception:
            return 0


def count_dataset_episodes(dataset_dir: Path) -> int:
    if not dataset_dir.exists():
        return 0

    info_json = dataset_dir / "meta" / "info.json"
    if info_json.exists():
        try:
            info = json.loads(info_json.read_text(encoding="utf-8"))
            for key in ("total_episodes", "num_episodes", "num_episodes_recorded"):
                value = info.get(key)
                if isinstance(value, int):
                    return value
            episodes = info.get("episodes")
            if isinstance(episodes, list):
                return len(episodes)
        except Exception:
            pass

    jsonl_candidates = [
        dataset_dir / "meta" / "episodes.jsonl",
        dataset_dir / "meta" / "episodes" / "episodes.jsonl",
    ]
    for path in jsonl_candidates:
        if path.exists():
            return count_jsonl(path)

    episode_dir = dataset_dir / "meta" / "episodes"
    if episode_dir.exists():
        total = 0
        for path in sorted(episode_dir.rglob("*.jsonl")):
            total += count_jsonl(path)
        if total:
            return total

        for path in sorted(episode_dir.rglob("*.parquet")):
            total += count_parquet(path)
        if total:
            return total

    parquet_candidates = [
        dataset_dir / "meta" / "episodes.parquet",
    ]
    for path in parquet_candidates:
        if path.exists():
            return count_parquet(path)

    return 0


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: count_dataset_episodes.py DATASET_DIR", file=sys.stderr)
        return 2

    print(count_dataset_episodes(Path(sys.argv[1]).expanduser()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
