import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import numpy as np
import soundfile as sf
from audio_decode import load_reference_audio


class InstallationTests(unittest.TestCase):
    def test_downloader_requires_consent_before_creating_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "engine"
            result = subprocess.run([sys.executable, "-B", str(Path(__file__).with_name("install_engine.py")), str(root)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(root.exists())
            self.assertIn(b"Accept the Coqui", result.stderr)

    def test_stereo_reference_is_mono_resampled_and_clipped(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ref.wav"
            sf.write(path, np.full((24000, 2), 1.2), 24000, subtype="FLOAT")
            result = load_reference_audio(path, 22050)
            self.assertEqual(tuple(result.shape), (1, 22050))
            self.assertLessEqual(float(result.max()), 1)

    def test_bundled_ffmpeg_decodes_m4a_without_torchcodec(self):
        import imageio_ffmpeg
        with tempfile.TemporaryDirectory() as directory:
            wav = Path(directory) / "ref.wav"
            m4a = Path(directory) / "ref.m4a"
            sf.write(wav, np.sin(np.arange(24000) * 0.1) * 0.2, 24000)
            subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-v", "error", "-i", str(wav), str(m4a)], check=True)
            result = load_reference_audio(m4a, 22050)
            self.assertGreater(result.shape[1], 20000)
            self.assertGreater(float(result.abs().max()), 0.01)
            self.assertNotIn("torchcodec", sys.modules)


if __name__ == "__main__":
    unittest.main()
