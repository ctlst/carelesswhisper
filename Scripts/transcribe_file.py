#!/usr/bin/env python3
import argparse
import json
import os
import sys


def default_model_dir() -> str:
    configured = os.environ.get("LOCALWHISPER_MODEL_DIR")
    if configured:
        return configured
    script_dir = os.path.abspath(os.path.dirname(__file__))
    if os.path.basename(script_dir) == "Resources":
        return os.path.join(script_dir, ".models", "whisper")
    project_root = os.path.abspath(os.path.join(script_dir, ".."))
    return os.path.join(project_root, ".models", "whisper")


def main() -> int:
    parser = argparse.ArgumentParser(description="Transcribe an audio file with local Whisper.")
    parser.add_argument("audio_path")
    parser.add_argument("--model", default=os.environ.get("LOCALWHISPER_MODEL", "base"))
    parser.add_argument("--language", default=os.environ.get("LOCALWHISPER_LANGUAGE", "auto"))
    args = parser.parse_args()

    try:
        import whisper
    except ImportError:
        print(json.dumps({
            "success": False,
            "error": "openai-whisper is not installed. Run: python3 -m pip install -r requirements.txt"
        }))
        return 2

    try:
        model_dir = default_model_dir()
        os.makedirs(model_dir, exist_ok=True)
        model = whisper.load_model(args.model, download_root=model_dir)
        kwargs = {}
        if args.language and args.language != "auto":
            kwargs["language"] = args.language
        result = model.transcribe(args.audio_path, **kwargs)
        print(json.dumps({
            "success": True,
            "text": result.get("text", "").strip(),
            "language": result.get("language", "unknown")
        }))
        return 0
    except Exception as exc:
        print(json.dumps({"success": False, "error": str(exc)}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
