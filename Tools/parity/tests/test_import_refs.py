import json
import os
import sys
import tempfile
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import import_refs  # noqa: E402


class ImportRefsTests(unittest.TestCase):
    def test_names_are_parsed_and_indexed(self):
        import tifffile
        with tempfile.TemporaryDirectory() as d:
            px = (np.zeros((4, 6, 3)) + 0.5) * 65535
            names = ["DSC01234__base.tif", "DSC01234__Exposure__-2.5.tif", "DSC01234__Exposure__1.tif", "DSC01234__Temperature__8000.tif",
                     "DSC01234__Contrast2012__50.tif", "DSC01234__combo03.tif", "DSC09999__base.tif", "notes.txt", "DSC01234__Sharpening__75.tif"]
            for n in names:
                if n.endswith(".tif"):
                    tifffile.imwrite(os.path.join(d, n), px.astype(np.uint16))
                else:
                    open(os.path.join(d, n), "w").write("x")
            json.dump({"settings": {"Exposure2012": 0.5, "Vibrance": -20, "Whites2012": 30}}, open(os.path.join(d, "DSC01234__combo03.json"), "w"))
            json.dump({"Temperature": 5150, "Tint": 6, "profile": "Adobe Color"}, open(os.path.join(d, "DSC01234__asshot.json"), "w"))
            data = import_refs.index(d)
            self.assertEqual(data["images"], ["DSC01234", "DSC09999"])
            self.assertEqual(data["counts"], {"images": 2, "base": 2, "singles": 5, "combos": 1})
            self.assertEqual(data["ignored"], ["notes.txt"])
            by_id = {r["id"]: r for r in data["refs"]}
            self.assertEqual(by_id["DSC01234__Exposure__-2.5"]["value"], -2.5)
            self.assertEqual(by_id["DSC01234__Exposure__-2.5"]["settings"], {"Exposure": -2.5})
            self.assertEqual(by_id["DSC01234__Contrast2012__50"]["slider"], "Contrast")
            self.assertEqual(by_id["DSC01234__Sharpening__75"]["slider"], "Sharpness")
            self.assertEqual(by_id["DSC01234__combo03"]["settings"], {"Exposure": 0.5, "Vibrance": -20, "Whites": 30})
            self.assertEqual(by_id["DSC01234__combo03"]["combo"], 3)
            self.assertEqual(by_id["DSC01234__base"]["asShot"]["Temperature"], 5150)
            self.assertNotIn("asShot", by_id["DSC09999__base"])
            self.assertEqual(by_id["DSC01234__base"]["width"], 6)
            self.assertEqual(by_id["DSC01234__base"]["bits"], 16)
            self.assertEqual(data["sliders"]["Exposure"], [-2.5, 1.0])


if __name__ == "__main__":
    unittest.main()
