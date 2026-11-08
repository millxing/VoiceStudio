"""Persistent local XTTS worker. stdout is JSONL; diagnostics go to stderr."""
import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
import traceback

PROTOCOL = sys.stdout
sys.stdout = sys.stderr


def emit(event, **values):
    PROTOCOL.write(json.dumps(dict(event=event, **values), ensure_ascii=False) + "\n")
    PROTOCOL.flush()


def split_text(text, fits):
    """Keep all non-whitespace text, respect sentence breaks, bound each chunk."""
    remaining = text.strip()
    chunks = []
    while remaining:
        if fits(remaining):
            chunks.append(remaining)
            break
        lo, hi = 1, min(len(remaining), 1000)
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if fits(remaining[:mid]):
                lo = mid
            else:
                hi = mid - 1
        end = lo
        prefix = remaining[:end]
        breaks = list(re.finditer(r"[.!?。！？]\s*|\n+", prefix))
        if breaks and breaks[-1].end() >= end // 3:
            end = breaks[-1].end()
        else:
            spaces = list(re.finditer(r"\s+", prefix))
            if spaces and spaces[-1].start() >= end // 2:
                end = spaces[-1].start()
        piece = remaining[:end].strip()
        if not piece or not fits(piece):
            raise ValueError("A portion of this script cannot be tokenized within the model limit.")
        chunks.append(piece)
        remaining = remaining[end:].strip()
    return chunks


def run():
    import numpy as np
    import soundfile as sf
    import torch
    from TTS.api import TTS

    device = sys.argv[1] if len(sys.argv) > 1 else "mps"
    folder = sys.argv[2] if len(sys.argv) > 2 else ""
    if device == "mps" and not torch.backends.mps.is_available():
        raise RuntimeError("Apple GPU is unavailable. Select CPU in Settings > Engine.")
    emit("status", message="Loading XTTS model…")
    if folder:
        root = Path(folder)
        for name in ("config.json", "model.pth", "vocab.json"):
            if not (root / name).is_file():
                raise ValueError(f"The model folder is missing {name}.")
        if json.loads((root / "config.json").read_text()).get("model") != "xtts":
            raise ValueError("This folder is not an XTTS model. Choose a folder with an XTTS config.json.")
        tts = TTS(model_path=str(root / "model.pth"), config_path=str(root / "config.json")).to(device)
    else:
        # No automatic license acceptance: installation's existing agreement is used.
        # stdin is reserved for protocol commands; do not consume one as a TOS answer.
        from TTS.utils.manage import ModelManager
        manager = ModelManager()
        item, fullname, _ = manager._set_model_item("tts_models/multilingual/multi-dataset/xtts_v2")
        if not manager.tos_agreed(item, manager.output_prefix / fullname):
            raise RuntimeError("XTTS model terms have not been accepted in this account. Run the model downloader interactively first; see the app README.")
        tts = TTS("tts_models/multilingual/multi-dataset/xtts_v2").to(device)
    model = tts.synthesizer.tts_model
    rate = int(tts.synthesizer.output_sample_rate)
    # Key conditioning by file contents, so editing a reference never uses stale latents.
    conditioning = {}
    speaker_manager = getattr(model, "speaker_manager", None)
    speakers = list(speaker_manager.speakers) if speaker_manager else []
    languages = list(model.config.languages)
    emit("ready", device=device, speakers=speakers, languages=languages, sample_rate=rate)
    for line in sys.stdin:
        request = None
        partial = None
        try:
            request = json.loads(line)
            if request.get("command") == "quit":
                return
            if request.get("command") != "generate":
                raise ValueError("Unknown worker command.")
            text = request["text"].strip()
            if not text:
                raise ValueError("The script is empty.")
            language = request["language"]
            if language not in languages:
                raise ValueError(f"Language {language} is not supported by this model.")
            speed = float(request["speed"])
            if not 0.1 <= speed <= 1.99:
                raise ValueError("Speed must be between 0.10 and 1.99.")
            torch.manual_seed(int(request["seed"]))
            started = time.perf_counter()
            with torch.inference_mode():
                refs = request.get("references", [])
                cached_voice = request.get("cached_voice")
                if cached_voice:
                    from voice_cache import load_voice
                    key = "cache:" + hashlib.sha256(Path(cached_voice).read_bytes()).hexdigest()
                    if key not in conditioning:
                        if len(conditioning) >= 16:
                            conditioning.pop(next(iter(conditioning)))
                        conditioning[key] = load_voice(cached_voice)
                    latent, embedding = conditioning[key]
                elif refs:
                    fingerprint = hashlib.sha256()
                    for filename in refs:
                        p = Path(filename)
                        fingerprint.update(str(p).encode())
                        with p.open("rb") as reference_file:
                            for block in iter(lambda: reference_file.read(1024 * 1024), b""):
                                fingerprint.update(block)
                    key = fingerprint.hexdigest()
                    if key not in conditioning:
                        emit("progress", id=request["id"], message="Preparing voice reference…")
                        if len(conditioning) >= 16:
                            conditioning.pop(next(iter(conditioning)))
                        conditioning[key] = model.get_conditioning_latents(audio_path=refs)
                    latent, embedding = conditioning[key]
                else:
                    speaker = request["speaker"]
                    if speaker not in speakers:
                        raise ValueError(f"Built-in voice {speaker} is unavailable in this model. Choose another voice.")
                    latent, embedding = model.speaker_manager.speakers[speaker].values()
                limit = int(model.args.gpt_max_text_tokens) - 4
                char_limit = model.tokenizer.char_limits.get(language.split("-")[0], 250)
                fits = lambda value: len(value) <= char_limit and len(model.tokenizer.encode(value.lower(), lang=language)) < limit
                chunks = split_text(text, fits)
                destination = Path(request["output"])
                destination.parent.mkdir(parents=True, exist_ok=True)
                partial = destination.with_suffix(".partial.wav")
                frames = 0
                with sf.SoundFile(partial, mode="w", samplerate=rate, channels=1, subtype="PCM_16") as audio_file:
                    for index, chunk in enumerate(chunks):
                        emit("progress", id=request["id"], current=index + 1, total=len(chunks), message=f"Generating part {index + 1} of {len(chunks)}…")
                        result = model.inference(chunk, language, latent, embedding,
                            temperature=model.config.temperature,
                            length_penalty=model.config.length_penalty,
                            repetition_penalty=model.config.repetition_penalty,
                            top_k=model.config.top_k, top_p=model.config.top_p, speed=speed,
                            enable_text_splitting=False)
                        wav = np.asarray(result["wav"], dtype=np.float32)
                        if not wav.size or not np.isfinite(wav).all() or np.max(np.abs(wav)) < 1e-6:
                            raise RuntimeError("The model produced invalid or silent audio. Try a new take or a different reference.")
                        if index:
                            pause = np.zeros(int(rate * 0.18), dtype=np.float32)
                            audio_file.write(pause)
                            frames += len(pause)
                        audio_file.write(wav)
                        frames += len(wav)
                if device == "mps":
                    torch.mps.synchronize()
                os.replace(partial, destination)
                emit("complete", id=request["id"], duration=frames / rate, seconds=time.perf_counter() - started, chunks=len(chunks), file=str(destination))
        except Exception as error:
            if partial:
                partial.unlink(missing_ok=True)
            traceback.print_exc()
            emit("error", id=request.get("id") if isinstance(request, dict) else None, message=str(error))


if __name__ == "__main__":
    try:
        with contextlib.redirect_stdout(sys.stderr):
            if len(sys.argv) > 1 and sys.argv[1] == "--inspect-cache":
                from voice_cache import cache_entries
                emit("cache", entries=cache_entries(sys.argv[2]))
            elif len(sys.argv) > 1 and sys.argv[1] == "--convert-cache":
                from voice_cache import convert_voice
                convert_voice(sys.argv[2], sys.argv[3], sys.argv[4])
                emit("converted")
            else:
                run()
    except Exception as error:
        traceback.print_exc()
        emit("fatal", message=str(error))
        raise SystemExit(1)
