"""Download and validate an isolated XTTS install; acceptance must be explicit."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("--accept-cpml", action="store_true")
    args = parser.parse_args()
    if not args.accept_cpml:
        parser.error("Accept the Coqui Public Model License before downloading XTTS.")
    root = args.root.resolve()
    os.environ["HF_HOME"] = str(root / "HuggingFace")
    os.environ["HF_XET_CACHE"] = str(root / "Cache" / "Xet")
    os.environ["XDG_CACHE_HOME"] = str(root / "Cache")
    os.environ["NUMBA_CACHE_DIR"] = str(root / "Cache" / "Numba")
    os.environ["HF_HUB_CACHE"] = str(root / "Models")
    os.environ["COQUI_TOS_AGREED"] = "1"
    os.environ["TOKENIZERS_PARALLELISM"] = "false"
    os.environ.pop("PYTORCH_ENABLE_MPS_FALLBACK", None)
    from TTS.utils.manage import ModelManager
    print("Downloading XTTS-v2 model…", flush=True)
    checkpoint, _, _ = ModelManager(output_prefix=root / "Metadata").download_model(
        "tts_models/multilingual/multi-dataset/xtts_v2")
    folder = checkpoint.parent
    for name in ("model.pth", "config.json", "vocab.json"):
        if not (folder / name).is_file():
            raise RuntimeError(f"Model download is missing {name}")
    print("Checking the model and generating test speech…", flush=True)
    import torch
    from TTS.api import TTS
    from audio_decode import configure_decoder, load_reference_audio
    configure_decoder()
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    tts = TTS(model_path=str(folder / "model.pth"), config_path=str(folder / "config.json")).to(device)
    model = tts.synthesizer.tts_model
    voice = next(iter(model.speaker_manager.speakers.values()))
    output = model.inference("The speech engine is ready.", "en", voice["gpt_cond_latent"].to(device),
                             voice["speaker_embedding"].to(device))
    import numpy as np
    import soundfile as sf
    audio = np.asarray(output["wav"])
    if not audio.size or not np.isfinite(audio).all() or np.max(np.abs(audio)) < 0.001:
        raise RuntimeError("The speech check produced invalid audio")
    sample = root / "installation-check.wav"
    sf.write(sample, audio, 24000)
    decoded = load_reference_audio(sample, 22050)
    # Exercise reference conditioning as well as the built-in voice path.
    model.get_conditioning_latents(audio_path=[str(sample)])
    assert decoded.shape[1] > 0
    receipt = {"python": sys.executable, "modelFolder": str(folder), "device": device,
               "licenseSHA256": hashlib.sha256(Path(__file__).with_name("XTTS-MODEL-LICENSE.txt").read_bytes()).hexdigest()}
    temporary = root / "receipt.tmp"
    temporary.write_text(json.dumps(receipt))
    temporary.replace(root / "receipt.json")
    print("Speech engine verified.", flush=True)


if __name__ == "__main__":
    main()
