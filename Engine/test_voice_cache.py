import os
from pathlib import Path
import tempfile
import unittest

import torch
from voice_cache import cache_entries, convert_voice, load_voice, MAX_BYTES


class UnsafeObject:
    def __init__(self, marker):
        self.marker = marker

    def __reduce__(self):
        return os.system, (f'touch {self.marker}',)


class VoiceCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source = self.root / 'voice.pth'
        self.latent = torch.randn(1, 32, 1024)
        self.embedding = torch.randn(1, 512, 1)

    def tearDown(self):
        self.temp.cleanup()

    def save(self, value):
        torch.save(value, self.source)
        return self.source

    def test_coqui_cache_metadata_and_normalization(self):
        self.save(dict(gpt_conditioning_latents=self.latent, speaker_embedding=self.embedding,
            metadata=dict(model=dict(name='xtts'), speaker_id='My narrator', source_files=['/old/account/ref.wav'])))
        self.assertEqual(cache_entries(self.source), [dict(id='', name='My narrator')])
        target = self.root / 'normalized.pth'
        before = self.source.read_bytes()
        convert_voice(self.source, '', target)
        normalized = torch.load(target, weights_only=True)
        self.assertEqual(set(normalized), {'gpt_conditioning_latents', 'speaker_embedding'})
        self.assertTrue(torch.equal(normalized['gpt_conditioning_latents'], self.latent))
        self.assertEqual(before, self.source.read_bytes())

    def test_legacy_keys_and_pairs(self):
        for value in [dict(gpt_cond_latent=self.latent, speaker_embedding=self.embedding),
                      dict(gpt_cond_latents=self.latent, speaker_embedding=self.embedding),
                      (self.latent, self.embedding), [self.latent[0], self.embedding[0, :, 0]]]:
            with self.subTest(type=type(value)):
                latent, embedding = load_voice(self.save(value))
                self.assertEqual(tuple(latent.shape), (1, 32, 1024))
                self.assertEqual(tuple(embedding.shape), (1, 512, 1))

    def test_speaker_bank_selection(self):
        a = dict(gpt_cond_latent=self.latent, speaker_embedding=self.embedding)
        b = dict(gpt_cond_latent=self.latent * 2, speaker_embedding=self.embedding)
        self.save({'Alice': a, 'Bob': b, 'metadata': {'description': 'not a voice'}})
        self.assertEqual([e['name'] for e in cache_entries(self.source)], ['Alice', 'Bob'])
        with self.assertRaises(ValueError): load_voice(self.source)
        latent, _ = load_voice(self.source, 'Bob')
        self.assertTrue(torch.equal(latent, self.latent * 2))

    def test_bad_inputs_are_rejected(self):
        invalid = [dict(model={'weights': torch.ones(3)}),
            dict(gpt_conditioning_latents=torch.zeros(1, 32, 1024), speaker_embedding=self.embedding),
            dict(gpt_conditioning_latents=torch.ones(1, 32, 512), speaker_embedding=self.embedding),
            dict(gpt_conditioning_latents=self.latent, speaker_embedding=torch.ones(1, 256, 1)),
            dict(gpt_conditioning_latents=self.latent * float('nan'), speaker_embedding=self.embedding),
            dict(gpt_conditioning_latents=self.latent, speaker_embedding=self.embedding, metadata={'model': {'name': 'other'}})]
        for value in invalid:
            with self.subTest(value=list(value)):
                with self.assertRaises(ValueError): cache_entries(self.save(value))

    def test_pickle_code_is_never_executed(self):
        marker = self.root / 'executed'
        self.save(UnsafeObject(marker))
        with self.assertRaises(ValueError): cache_entries(self.source)
        self.assertFalse(marker.exists())

    def test_large_checkpoint_is_rejected(self):
        with self.source.open('wb') as f: f.truncate(MAX_BYTES + 1)
        with self.assertRaisesRegex(ValueError, '64 MB'): cache_entries(self.source)


if __name__ == '__main__':
    unittest.main()
