"""Boundary tests for chunking, independent of PyTorch or model downloads."""
import unittest
from worker import split_text


class ChunkTests(unittest.TestCase):
    def test_preserves_text_and_bounds(self):
        for text in ["Hello world. " * 100, "字" * 1700, "unbroken" * 1000,
                     "First paragraph.\n\nSecond paragraph! " * 50,
                     "A sentence with emojis 👋🏼 and accents café. " * 100]:
            with self.subTest(text=text[:30]):
                chunks = split_text(text, lambda part: len(part) <= 120)
                self.assertTrue(all(0 < len(chunk) <= 120 for chunk in chunks))
                self.assertEqual("".join("".join(chunks).split()), "".join(text.split()))

    def test_empty(self):
        self.assertEqual(split_text(" \n ", lambda part: True), [])


if __name__ == "__main__":
    unittest.main()
