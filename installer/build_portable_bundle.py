#!/usr/bin/env python3

import argparse
import json
import shutil
from pathlib import Path


INCLUDE_DIRS = ["docs", "installer", "scripts", "tests", "vm"]
INCLUDE_FILES = [
    ".env.example",
    "README.md",
    "RUNBOOK.md",
    "WINDOWS_WSL2_DOCKER_CODEX_PROMPT.md",
    "compose.yaml",
]


def copy_tree(src: Path, dst: Path) -> None:
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)


def copy_file(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--output-root", default=None)
    parser.add_argument("--bundle-name", default="openclaw-portable-bundle")
    parser.add_argument("--wsl-x64")
    parser.add_argument("--wsl-arm64")
    parser.add_argument("--docker-x64")
    parser.add_argument("--docker-arm64")
    parser.add_argument("--docker-images-x64-root")
    parser.add_argument("--docker-images-arm64-root")
    parser.add_argument("--ollama-model-archive-x64")
    parser.add_argument("--ollama-model-archive-arm64")
    parser.add_argument("--weixin-plugin-archive-x64")
    parser.add_argument("--weixin-plugin-archive-arm64")
    parser.add_argument("--zip", action="store_true")
    args = parser.parse_args()

    project_root = Path(args.project_root).resolve()
    output_root = Path(args.output_root).resolve() if args.output_root else (project_root / "dist" / args.bundle_name)

    if output_root.exists():
        shutil.rmtree(output_root)
    output_root.mkdir(parents=True, exist_ok=True)

    for rel in INCLUDE_DIRS:
        copy_tree(project_root / rel, output_root / rel)

    for rel in INCLUDE_FILES:
        copy_file(project_root / rel, output_root / rel)

    payload_x64 = output_root / "installer" / "payload" / "x64"
    payload_arm64 = output_root / "installer" / "payload" / "arm64"
    payload_x64.mkdir(parents=True, exist_ok=True)
    payload_arm64.mkdir(parents=True, exist_ok=True)

    optional_payloads = [
        (args.wsl_x64, payload_x64 / "wsl.msi"),
        (args.wsl_arm64, payload_arm64 / "wsl.msi"),
        (args.docker_x64, payload_x64 / "DockerDesktopInstaller.exe"),
        (args.docker_arm64, payload_arm64 / "DockerDesktopInstaller.exe"),
    ]

    for src, dst in optional_payloads:
        if src:
            copy_file(Path(src).resolve(), dst)

    directory_payloads = [
        (args.docker_images_x64_root, payload_x64 / "images"),
        (args.docker_images_arm64_root, payload_arm64 / "images"),
    ]

    for src, dst in directory_payloads:
        if src:
            copy_tree(Path(src).resolve(), dst)

    archive_payloads = [
        (args.ollama_model_archive_x64, payload_x64 / "ollama-models" / Path(args.ollama_model_archive_x64).name if args.ollama_model_archive_x64 else None),
        (args.ollama_model_archive_arm64, payload_arm64 / "ollama-models" / Path(args.ollama_model_archive_arm64).name if args.ollama_model_archive_arm64 else None),
        (args.weixin_plugin_archive_x64, payload_x64 / "npm" / Path(args.weixin_plugin_archive_x64).name if args.weixin_plugin_archive_x64 else None),
        (args.weixin_plugin_archive_arm64, payload_arm64 / "npm" / Path(args.weixin_plugin_archive_arm64).name if args.weixin_plugin_archive_arm64 else None),
    ]

    for src, dst in archive_payloads:
        if src and dst:
            copy_file(Path(src).resolve(), dst)

    manifest_path = output_root / "installer" / "BundleManifest.json"
    manifest = json.loads(manifest_path.read_text())
    manifest["builtBundleRoot"] = str(output_root)
    manifest["packagedPayloads"] = {
        "x64": sorted(str(p.relative_to(payload_x64)).replace("\\", "/") for p in payload_x64.rglob("*") if p.is_file()),
        "arm64": sorted(str(p.relative_to(payload_arm64)).replace("\\", "/") for p in payload_arm64.rglob("*") if p.is_file()),
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

    if args.zip:
        archive = shutil.make_archive(str(output_root), "zip", root_dir=output_root.parent, base_dir=output_root.name)
        print(archive)
    else:
        print(output_root)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
