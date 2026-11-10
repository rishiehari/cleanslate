import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from PIL import Image
from generate_synthetic_photos import generate, generate_bursts, BURST_FRAMES

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

class BurstModeTests(unittest.TestCase):
    EXIF_IFD, DATETIME_ORIGINAL = 0x8769, 36867

    def taken(self, path):
        with Image.open(path) as img:
            return datetime.strptime(img.getexif().get_ifd(self.EXIF_IFD)[self.DATETIME_ORIGINAL], '%Y:%m:%d %H:%M:%S')

    def test_frame_count_and_labels(self):
        with tempfile.TemporaryDirectory() as tmp:
            rows = generate_bursts(Path(tmp), 3)
            self.assertEqual(len(rows), 3 * BURST_FRAMES)
            self.assertEqual(len(list(Path(tmp).glob('burst_*/frame*.jpg'))), 24)
            for b in range(3):
                labels = [r['relation_to_base'] for r in rows[b*8:(b+1)*8]]
                self.assertEqual(labels.count('unique_expression'), 1)
                self.assertEqual(labels.count('unique_subject'), 1)
                self.assertEqual(labels.count('burst_redundant'), 6)
                self.assertEqual(labels[5], 'unique_expression')
                self.assertEqual(labels[7], 'unique_subject')

    def test_exif_one_second_apart_within_each_burst(self):
        with tempfile.TemporaryDirectory() as tmp:
            rows = generate_bursts(Path(tmp), 2)
            for b in range(2):
                times = [self.taken(Path(tmp)/r['asset_id']) for r in rows[b*8:(b+1)*8]]
                self.assertEqual([(y - x).total_seconds() for x, y in zip(times, times[1:])], [1.0] * 7)
            first_of_second = self.taken(Path(tmp)/rows[8]['asset_id'])
            last_of_first = self.taken(Path(tmp)/rows[7]['asset_id'])
            self.assertGreater((first_of_second - last_of_first).total_seconds(), 60, 'bursts are far apart in time')

    def test_frames_differ_but_stay_similar_and_are_deterministic(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            x = generate_bursts(Path(a), 1)
            y = generate_bursts(Path(b), 1)
            self.assertEqual(x, y)
            self.assertEqual(len({r['sha256'] for r in x}), BURST_FRAMES, 'every frame is a different file')
            self.assertTrue(all(r['is_native_burst_simulation'] == 'false' for r in x))

    def test_zero_bursts_changes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(generate_bursts(Path(tmp), 0), [])

    def test_default_generation_unchanged_by_burst_support(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(len(generate(Path(tmp), scenes=2)), 16)
            self.assertFalse(list(Path(tmp).glob('burst_*')))

if __name__ == '__main__': unittest.main()
