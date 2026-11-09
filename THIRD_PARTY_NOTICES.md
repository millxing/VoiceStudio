# Third-party notices

VoiceStudio's app source is licensed under the MIT license in [LICENSE](LICENSE).
The project includes portions of the BAMA macOS app template, copyright 2026
Dave Ebbelaar, also under MIT; that attribution is retained in LICENSE.

## Speech engine and model

The installer downloads these components separately. The app's MIT license does
not replace their licenses, and model weights, voice caches, personal reference
recordings and generated speech are not included in this source repository.

- [Coqui TTS](https://github.com/coqui-ai/TTS) and the maintained
  [coqui-tts package](https://github.com/idiap/coqui-ai-TTS) have their own
  source/dependency licenses. The current engine package is under MPL-2.0.
- XTTS-v2 model terms are the **Coqui Public Model License (CPML)**. They restrict
  model and output use to non-commercial purposes. See the bundled
  [model license](Engine/XTTS-MODEL-LICENSE.txt) and
  [upstream license](https://huggingface.co/coqui/XTTS-v2/blob/main/LICENSE.txt).
  Every user must explicitly accept these terms in setup before downloading.
- [uv](https://github.com/astral-sh/uv) is distributed under MIT or Apache-2.0.
  The installer downloads a pinned release and verifies its archive checksum.
- Python, PyTorch, imageio-ffmpeg, the FFmpeg executable it supplies, and other
  packages retain their individual licenses. Package metadata and notices are
  installed with their distributions; FFmpeg's applicable notices are available
  through its packaged executable's `-L` option.

VoiceStudio is an independent application and is not affiliated with Coqui,
XTTS-UI, or the maintainers of those projects. Use voice references for which
you have permission.
