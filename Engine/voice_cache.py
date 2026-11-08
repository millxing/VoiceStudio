"""Restricted XTTS cached-voice reader; never enables arbitrary pickle loading."""
from pathlib import Path
import os
import zipfile

import torch

MAX_BYTES = 64 * 1024 * 1024
LATENT_KEYS = ("gpt_conditioning_latents", "gpt_cond_latent", "gpt_cond_latents")


def _pair(value):
    if isinstance(value, dict):
        metadata = value.get("metadata", {})
        if isinstance(metadata, dict):
            model = metadata.get("model", {})
            name = model.get("name") if isinstance(model, dict) else model
            if name and str(name).lower() not in ("xtts", "xtts_v2", "xtts-v2"):
                raise ValueError("This cached voice belongs to a different model, not XTTS.")
        latent = next((value[key] for key in LATENT_KEYS if key in value), None)
        embedding = value.get("speaker_embedding")
    elif isinstance(value, (tuple, list)) and len(value) == 2:
        latent, embedding = value
    else:
        raise ValueError("No XTTS voice-conditioning tensors were found.")
    if type(latent) is not torch.Tensor or type(embedding) is not torch.Tensor:
        raise ValueError("The cached voice must contain XTTS conditioning and speaker tensors.")
    for tensor in (latent, embedding):
        if tensor.layout != torch.strided or not tensor.is_floating_point() or not torch.isfinite(tensor).all():
            raise ValueError("The cached voice contains invalid tensor values.")
    if latent.ndim == 2:
        latent = latent.unsqueeze(0)
    if embedding.ndim == 1:
        embedding = embedding[None, :, None]
    elif embedding.ndim == 2:
        embedding = embedding.unsqueeze(-1)
    if latent.ndim != 3 or latent.shape[0] != 1 or latent.shape[2] != 1024 or not 1 <= latent.shape[1] <= 128:
        raise ValueError("The conditioning tensor has an unsupported XTTS shape; expected [1, steps, 1024].")
    if tuple(embedding.shape) != (1, 512, 1):
        raise ValueError("The speaker tensor has an unsupported XTTS shape; expected [1, 512, 1].")
    if not torch.count_nonzero(latent) or not torch.count_nonzero(embedding):
        raise ValueError("The cached voice contains empty conditioning data.")
    return latent.detach().to(device="cpu", dtype=torch.float32).contiguous(), embedding.detach().to(device="cpu", dtype=torch.float32).contiguous()


def read_cache(path):
    path = Path(path)
    if path.stat().st_size > MAX_BYTES:
        raise ValueError("This file is larger than 64 MB. Import a cached voice, not a model checkpoint.")
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            if sum(info.file_size for info in archive.infolist()) > MAX_BYTES:
                raise ValueError("This archive is too large for an XTTS cached voice.")
    try:
        value = torch.load(path, map_location="cpu", weights_only=True)
    except Exception as error:
        raise ValueError("Unable to read this cached voice with restricted loading. Use a tensor-only XTTS voice cache or import the original reference audio.") from error
    if isinstance(value, (list, tuple)) or isinstance(value, dict) and any(key in value for key in LATENT_KEYS):
        _pair(value)
        return {"": value}
    if isinstance(value, dict):
        voices = {}
        for name, entry in value.items():
            if not isinstance(name, str):
                continue
            try:
                _pair(entry)
                voices[name] = entry
            except ValueError:
                continue
        if voices:
            return voices
    raise ValueError("This is not an XTTS cached voice. Import reference audio, or choose a full model folder in Settings > Engine.")


def cache_entries(path):
    voices = read_cache(path)
    entries = []
    for key, value in voices.items():
        metadata = value.get("metadata", {}) if isinstance(value, dict) else {}
        name = key or (metadata.get("speaker_id") if isinstance(metadata, dict) else None) or Path(path).stem
        entries.append({"id": key, "name": str(name)})
    return sorted(entries, key=lambda entry: entry["name"].casefold())


def load_voice(path, entry=""):
    voices = read_cache(path)
    if entry not in voices:
        raise ValueError("Choose a saved speaker from this voice file.")
    return _pair(voices[entry])


def convert_voice(source, entry, destination):
    latent, embedding = load_voice(source, entry)
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(".partial.pth")
    try:
        # Retain only validated tensors, not pickle metadata or external paths.
        torch.save({"gpt_conditioning_latents": latent, "speaker_embedding": embedding}, temporary)
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)
