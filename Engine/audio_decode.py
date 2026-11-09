"""Reference decoding without a system FFmpeg shared-library dependency."""
import subprocess


def load_reference_audio(path, sampling_rate):
    import numpy as np
    import soundfile as sf
    import torch
    from torchaudio.functional import resample
    try:
        samples, rate = sf.read(str(path), dtype="float32", always_2d=True)
        audio = torch.from_numpy(samples.mean(axis=1).copy()).unsqueeze(0)
        if rate != sampling_rate:
            audio = resample(audio, rate, sampling_rate)
    except (sf.LibsndfileError, RuntimeError):
        import imageio_ffmpeg
        result = subprocess.run(
            [imageio_ffmpeg.get_ffmpeg_exe(), "-nostdin", "-v", "error", "-i", str(path),
             "-f", "f32le", "-ac", "1", "-ar", str(sampling_rate), "pipe:1"],
            capture_output=True, timeout=120, check=True)
        audio = torch.from_numpy(np.frombuffer(result.stdout, dtype="<f4").copy()).unsqueeze(0)
    if not audio.numel() or not torch.isfinite(audio).all():
        raise ValueError("Reference audio is empty or contains invalid samples.")
    return audio.clamp(-1, 1)


def configure_decoder():
    # Coqui 0.28's XTTS helper otherwise loads torchcodec and system FFmpeg libraries.
    import TTS.tts.models.xtts as xtts
    xtts.load_audio = load_reference_audio
