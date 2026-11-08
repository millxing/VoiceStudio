"""Make disposable cached-voice fixtures from the installed public XTTS model."""
from pathlib import Path
import torch

hub = Path.home() / '.cache/huggingface/hub/models--tts-hub--XTTS-v2'
root = hub / 'snapshots' / (hub / 'refs/main').read_text().strip()
speakers = torch.load(root / 'speakers_xtts.pth', map_location='cpu', weights_only=True)
voice = speakers['Craig Gutsy']
torch.save(dict(gpt_conditioning_latents=voice['gpt_cond_latent'], speaker_embedding=voice['speaker_embedding'],
    metadata=dict(model=dict(name='xtts'), speaker_id='Saved narrator', source_files=['/unavailable/account/original.wav'])), '/tmp/VoiceStudio-cache-fixture.pth')
torch.save({'Narrator A': voice, 'Narrator B': speakers['Ana Florence']}, '/tmp/VoiceStudio-cache-bank.pth')
print('Created disposable voice-cache fixtures under /tmp')
