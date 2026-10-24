"""Default competition configs are 40 Hz; 50 Hz is explicitly selected."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]

class ConfigRateTests(unittest.TestCase):
    def test_default_and_explicit_rates(self):
        for size in [1, 3, 5, 6]:
            for suffix, rate in [('', 40), ('_svfps50', 50)]:
                with self.subTest(size=size, rate=rate):
                    text=(ROOT/'configs'/f'legacy{size}{suffix}.config').read_text()
                    self.assertEqual(re.findall(r'^\s*setl\s+sv_fps\s+"(\d+)"',text,re.M),[str(rate)])
                    self.assertIn('luascripts/pappaliiga/pappahighlights.lua',text)
                    self.assertIn('luascripts/stats.lua',text)

    def test_obsolete_40_aliases_removed(self):
        for size in [1,3,5,6]:
            self.assertFalse((ROOT/'configs'/f'legacy{size}_svfps40.config').exists())

if __name__=='__main__':
    unittest.main()
