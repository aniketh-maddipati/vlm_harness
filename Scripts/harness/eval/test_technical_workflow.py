import json
from pathlib import Path
import tempfile
import unittest
from sony_inventory import sessions, freeze_split, private_output, atomic_json
from technical_review import key, import_decisions, summarize
from run_technical import bind_manifest

class WorkflowTests(unittest.TestCase):
    def test_copies_and_bursts_stay_together(self):
        rows=[dict(sha256='a',metadata={'DateTimeOriginal':'2026:01:01 10:00:00'}),
              dict(sha256='a',metadata={'DateTimeOriginal':'2026:01:01 10:00:00'}),
              dict(sha256='b',metadata={'DateTimeOriginal':'2026:01:01 10:00:01'}),
              dict(sha256='c',metadata={})]
        groups=sessions(rows)
        self.assertEqual(groups['a'],groups['b'])
        self.assertEqual(groups['c'],'unknown-date')

    def test_split_rejects_same_shoot_in_both_partitions(self):
        manifest={'files':[dict(session='a',sha256='a'),dict(session='b',sha256='b')]}
        assignments={s:dict(shoot='same',lighting='day',split=v) for s,v in [('a','development'),('b','heldout')]}
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(ValueError): freeze_split(manifest,assignments,d)
            assignments['b']['shoot']='other'
            freeze_split(manifest,assignments,d)
            assignments['a']['lighting']='changed'
            with self.assertRaises(ValueError): freeze_split(manifest,assignments,d)

    def test_private_output_rejects_worktree(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d)/'.git').write_text('gitdir: elsewhere')
            with self.assertRaises(ValueError): private_output(Path(d)/'private')

    def test_every_cache_dependency_invalidates(self):
        args=['raw','pipeline',{'exposure':0},'model']
        original=key(*args)
        for i,replacement in enumerate(['raw2','pipeline2',{'exposure':0.33},'model2']):
            changed=args.copy();changed[i]=replacement
            self.assertNotEqual(original,key(*changed))

    def test_resume_refuses_changed_manifest(self):
        with tempfile.TemporaryDirectory() as d:
            out=Path(d);bind_manifest(out,{'pipeline':'one'})
            bind_manifest(out,{'pipeline':'one'})
            with self.assertRaises(ValueError): bind_manifest(out,{'pipeline':'two'})

    def test_blind_review_is_atomic_and_does_not_guess_pending(self):
        with tempfile.TemporaryDirectory() as d:
            out=Path(d)
            pair=dict(id='p',frame=1,session='s',lighting='unknown',A='technical',B='policy',choice=None,severe=False,reason='')
            project=dict(review_id='r',pairs=[pair],queue=[dict(action='abstain')])
            atomic_json(out/'project.json',project)
            self.assertEqual(summarize(project)['comparisons']['s|unknown|policy']['pending'],1)
            with self.assertRaises(ValueError): import_decisions(out,dict(review_id='foreign',decisions=[]))
            with self.assertRaises(ValueError): import_decisions(out,dict(review_id='r',decisions=[dict(id='p',choice='A',severe=True,reason='')]))
            self.assertEqual(json.loads((out/'project.json').read_text()),project)
            summary=import_decisions(out,dict(review_id='r',decisions=[dict(id='p',choice='tie',severe=False,reason='same pixels')]))
            self.assertEqual(summary['comparisons']['s|unknown|policy']['ties'],1)

if __name__=='__main__': unittest.main()

class CacheTests(unittest.TestCase):
    def test_cache_reuse_invalidation_and_corruption(self):
        from technical_cache import ReviewCache
        with tempfile.TemporaryDirectory() as d:
            cache=ReviewCache(d)
            identity=cache.identity('raw','pipeline',{'exposure':0},'weights-v1')
            pixels=b'\xff\xd8test'
            cache.put(identity,{'hypothesis':'dark'},pixels)
            self.assertEqual(cache.get(identity),({'hypothesis':'dark'},pixels))
            changed=cache.identity('raw','pipeline2',{'exposure':0},'weights-v1')
            self.assertIsNone(cache.get(changed))
            with self.assertRaises(ValueError): cache.put(identity,{'hypothesis':'bright'},pixels)
            (Path(d)/(identity+'.jpg')).write_bytes(b'corrupt')
            with self.assertRaises(ValueError): cache.get(identity)
