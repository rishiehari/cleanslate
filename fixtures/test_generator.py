import tempfile
import unittest
from pathlib import Path
try:
    from generate_synthetic_photos import generate
except ImportError:
    generate = None

@unittest.skipUnless(generate is not None, 'Pillow required')
class FixtureGeneratorTests(unittest.TestCase):
    def test_count_and_semantic_cases(self):
        with tempfile.TemporaryDirectory() as tmp:
            rows = generate(Path(tmp), scenes=3)
            self.assertEqual(len(rows),24)
            types = {x['relation_to_base'] for x in rows}
            self.assertIn('unique_text',types)
            self.assertIn('unique_expression',types)
            self.assertIn('unique_subject',types)
            for idx in range(3):
                base=rows[idx*8]
                copy=rows[idx*8+1]
                altered=rows[idx*8+5]
                self.assertEqual(base['sha256'],copy['sha256'])
                self.assertNotEqual(base['sha256'],altered['sha256'])

    def test_deterministic(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            x=generate(Path(a), scenes=2)
            y=generate(Path(b), scenes=2)
            self.assertEqual(x,y)

if __name__ == '__main__': unittest.main()
