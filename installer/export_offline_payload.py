#!/usr/bin/env python3

import argparse
import json
import shutil
import subprocess
import tarfile
from pathlib import Path


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True)


def image_archive_name(image: str) -> str:
    return image.replace("/", "_").replace(":", "_") + ".tar"


def export_image(image: str, output_dir: Path) -> str:
    archive_name = image_archive_name(image)
    archive_path = output_dir / archive_name
    run(["docker", "pull", image])
    run(["docker", "save", "-o", str(archive_path), image])
    return archive_name


def create_model_archive(source_models_dir: Path, output_dir: Path) -> str:
    archive_path = output_dir / "ollama-models.tar.gz"
    with tarfile.open(archive_path, "w:gz") as tar:
        tar.add(source_models_dir, arcname=".")
    return archive_path.name


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--openclaw-image", default="openclaw/openclaw:latest")
    parser.add_argument("--ollama-image", default="ollama/ollama:latest")
    parser.add_argument("--helper-image", action="append", default=["alpine/socat:1.8.0.3"])
    parser.add_argument("--weixin-plugin-npm-spec", default="@tencent-weixin/openclaw-weixin")
    parser.add_argument("--model")
    parser.add_argument("--ollama-models-dir")
    args = parser.parse_args()

    output_root = Path(args.output_root).resolve()
    images_dir = output_root / "images"
    models_dir = output_root / "ollama-models"
    npm_dir = output_root / "npm"
    output_root.mkdir(parents=True, exist_ok=True)
    images_dir.mkdir(parents=True, exist_ok=True)
    models_dir.mkdir(parents=True, exist_ok=True)
    npm_dir.mkdir(parents=True, exist_ok=True)

    archives = []
    for image in [args.openclaw_image, args.ollama_image, *args.helper_image]:
        archives.append(export_image(image, images_dir))

    model_archive_name = None
    if args.ollama_models_dir:
        source = Path(args.ollama_models_dir).resolve()
        if not source.is_dir():
            raise SystemExit(f"Ollama models directory not found: {source}")
        model_archive_name = create_model_archive(source, models_dir)

    result = subprocess.run(
        ["npm", "pack", "--silent", args.weixin_plugin_npm_spec],
        cwd=npm_dir,
        check=True,
        capture_output=True,
        text=True,
    )
    weixin_archive = result.stdout.strip().splitlines()[-1]

    manifest = {
        "images": archives,
        "model": args.model,
        "modelArchive": model_archive_name,
        "weixinPlugin": {
            "npmSpec": args.weixin_plugin_npm_spec,
            "archive": weixin_archive,
        },
    }
    (output_root / "offline-payload.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(output_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
