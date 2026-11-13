"""Counterexamples target semantic guards after verifying the original seal.

Mutated in-memory records stand in for a resealed outer archive. No original
artifact changes, producers, SDK validation, or native pipelines are involved.
"""
from pathlib import Path
from tempfile import TemporaryDirectory
import json, tarfile, unittest
import verify

BASE=Path(__file__).resolve().parent

class DerivedReceiptControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        receipt=json.loads((BASE/'receipt.json').read_text())
        for name,want in receipt['files'].items():
            raw=(BASE/name).read_bytes()
            verify.require({'bytes':len(raw),'sha256':verify.sha(raw)}==want,'outer file '+name)
        with tarfile.open(BASE/'records.tar.xz') as tar:
            cls.records={m.name:tar.extractfile(m).read() for m in tar if m.isfile()}
        manifest=json.loads((BASE/'record-manifest.json').read_text())
        verify.require(set(cls.records)==set(manifest),'original record inventory')
        for name,raw in cls.records.items():
            verify.require({'bytes':len(raw),'sha256':verify.sha(raw)}==manifest[name],'original record '+name)
        with TemporaryDirectory(dir=BASE.parent) as temporary:
            verify.verify_records(cls.records,temporary)

    def rejected(self,record,edit,guard):
        records=self.records.copy();value=json.loads(records[record]);edit(value)
        records[record]=(json.dumps(value,ensure_ascii=False)+'\n').encode()
        with TemporaryDirectory(dir=BASE.parent) as temporary:
            with self.assertRaisesRegex(ValueError,guard):
                verify.verify_records(records,temporary)

    def test_lossy_rewrite_claimed_equal(self):
        self.rejected('probe-report.json',lambda r:r['cases']['notes-and-link']['rewrites']['runs'].__setitem__('semanticProjectionEqual',True),'derived semantic equality')

    def test_raw_save_part_claim_changed(self):
        self.rejected('probe-report.json',lambda r:r['cases']['plain']['rewrites']['save'].__setitem__('allPartBytesEqual',False),'derived part equality')

    def test_mutated_rewrite_claimed_byte_equal(self):
        self.rejected('probe-report.json',lambda r:r['cases']['notes-and-link']['rewrites']['runs'].__setitem__('allPartBytesEqual',True),'derived part equality')

    def changed_input(self,key,value):
        self.rejected('retained-pair-report.json',lambda r:r['cases']['word']['inputs']['parser'].__setitem__(key,value),'retained derived observation: '+key)

    def test_pair_text_array(self): self.changed_input('crispTexts',['fabricated'])
    def test_pair_run_text_array(self): self.changed_input('crispRunText',['fabricated'])
    def test_pair_clean_claim(self): self.changed_input('crispClean',False)
    def test_pair_issue_claim(self): self.changed_input('crispIssues',['fabricated'])
    def test_pair_pandoc_digest(self): self.changed_input('pandocCanonicalSha256','0'*64)
    def test_pair_pandoc_exit(self): self.changed_input('pandocExitCode',9)

    def changed_comparison(self,key):
        def edit(report):
            row=report['cases']['word']['comparison'];row[key]=not row[key]
        self.rejected('retained-pair-report.json',edit,'retained derived comparison: '+key)

    def test_pair_text_equality(self): self.changed_comparison('crispTextArraysEqual')
    def test_pair_run_equality(self): self.changed_comparison('crispRunTextArraysEqual')
    def test_pair_pandoc_equality(self): self.changed_comparison('pandocAstEqual')
    def test_pair_summary_equality(self): self.changed_comparison('projectionSummariesEqual')

    def test_pandoc_record_contradicts_raw_output(self):
        records=self.records.copy();name='retained-pairs/word.parser.json'
        detail=json.loads(records[name]);detail['pandoc']['meta']['fabricated']={'t':'MetaString','c':'fabricated'}
        records[name]=(json.dumps(detail,ensure_ascii=False)+'\n').encode()
        report=json.loads(records['retained-pair-report.json'])
        report['cases']['word']['inputs']['parser']['recordSha256']=verify.sha(records[name])
        records['retained-pair-report.json']=(json.dumps(report,ensure_ascii=False)+'\n').encode()
        with TemporaryDirectory(dir=BASE.parent) as temporary:
            with self.assertRaisesRegex(ValueError,'retained Pandoc result binding'):
                verify.verify_records(records,temporary)

if __name__=='__main__': unittest.main(verbosity=2)
