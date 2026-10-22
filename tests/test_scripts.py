import csv
import gzip
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ScriptsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        (self.path / "ref.fa.fai").write_text("chr1\t100\t0\t0\t0\nchr2\t100\t0\t0\t0\nchrX\t155270560\t0\t0\t0\nchrY\t59373566\t0\t0\t0\nchrM\t16571\t0\t0\t0\n")
        (self.path / "capture.bed").write_text("chr1\t10\t20\nchr1\t25\t30\nchrX\t1\t5\n")

    def run_intervals(self, *args):
        return subprocess.run([sys.executable, str(ROOT / "scripts/intervals.py"), *map(str, args)],
                              cwd=self.path, capture_output=True, text=True)

    def capture(self, complement="UNKNOWN", capture_bed="capture.bed"):
        capture_arg = ("--capture-bed", capture_bed) if capture_bed is not None else ()
        return self.run_intervals("capture", "--fai", "ref.fa.fai", *capture_arg,
                                  "--padding", "5", "--calling-bed", "calling.bed",
                                  "--analysis-bed", "analysis.bed", "--sex-chromosome-complement", complement,
                                  "--bqsr-bed", "bqsr.bed", "--mt-bed", "mt.bed", "--has-mt", "has_mt.txt",
                                  "--x-diploid-bed", "x_diploid.bed", "--has-x-diploid", "has_x_diploid.txt",
                                  "--x-haploid-bed", "x_haploid.bed", "--has-x-haploid", "has_x_haploid.txt",
                                  "--y-haploid-bed", "y_haploid.bed", "--has-y-haploid", "has_y_haploid.txt",
                                  "--excluded-tsv", "excluded.tsv", "--summary-json", "summary.json")

    def targets(self, complement="UNKNOWN", capture_bed="capture.bed"):
        capture_arg = ("--capture-bed", capture_bed) if capture_bed is not None else ()
        return self.run_intervals("targets", "--fai", "ref.fa.fai", *capture_arg,
                                  "--calling-bed", "calling.bed", "--target-bed", "targets.bed",
                                  "--in-scope-bed", "in_scope.bed", "--status-tsv", "status.tsv",
                                  "--has-in-scope", "has.txt", "--sex-chromosome-complement", complement,
                                  "--mt-bed", "mt.bed", "--mt-in-scope-bed", "mt_target.bed", "--has-mt", "target_has_mt.txt",
                                  "--x-diploid-bed", "x_diploid.bed", "--x-diploid-in-scope-bed", "x_diploid_target.bed", "--has-x-diploid", "target_has_x_diploid.txt",
                                  "--x-haploid-bed", "x_haploid.bed", "--x-haploid-in-scope-bed", "x_haploid_target.bed", "--has-x-haploid", "target_has_x_haploid.txt",
                                  "--y-haploid-bed", "y_haploid.bed", "--y-haploid-in-scope-bed", "y_haploid_target.bed", "--has-y-haploid", "target_has_y_haploid.txt")

    def test_capture_padding_merge_and_excluded_sex_contig(self):
        result = self.capture()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.path / "calling.bed").read_text(), "chr1\t5\t35\n")
        self.assertEqual((self.path / "has_mt.txt").read_text(), "false\n")
        self.assertIn("chrX\t1\t5\tComplementUnspecified", (self.path / "excluded.tsv").read_text())

    def test_target_scope_keeps_partial_and_outside_requests(self):
        self.assertEqual(self.capture().returncode, 0)
        (self.path / "targets.bed").write_text("chr1\t8\t12\tinside\nchr1\t32\t40\tpartial\nchr2\t1\t2\toutside\nchrX\t1\t2\tsex\n")
        result = self.targets()
        self.assertEqual(result.returncode, 0, result.stderr)
        with open(self.path / "status.tsv") as handle:
            rows = list(csv.DictReader(handle, delimiter="\t"))
        self.assertEqual([row["status"] for row in rows],
                         ["InScope", "PartiallyInScope", "OutOfAnalysisScope", "ComplementUnspecified"])
        self.assertEqual([row["in_scope_bases"] for row in rows], ["4", "3", "0", "0"])
        self.assertEqual((self.path / "has.txt").read_text(), "true\n")

    def test_invalid_bed_fails_before_calling(self):
        (self.path / "capture.bed").write_text("chr1\t20\t10\n")
        result = self.capture()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid/out-of-reference", result.stderr)

    def test_xx_calls_x_diploid_and_excludes_y(self):
        (self.path / "capture.bed").write_text("chr1\t10\t20\nchrX\t2699518\t2699522\nchrY\t3000000\t3000010\n")
        result = self.capture("XX")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.path / "x_diploid.bed").read_text(), "chrX\t2699513\t2699527\n")
        self.assertEqual((self.path / "x_haploid.bed").read_text(), "")
        self.assertEqual((self.path / "y_haploid.bed").read_text(), "")
        self.assertIn("chrY\t3000000\t3000010\tAbsentInXX", (self.path / "excluded.tsv").read_text())

    def test_xy_par_boundary_and_y_par_are_partitioned(self):
        (self.path / "capture.bed").write_text(
            "chr1\t10\t20\nchrX\t2699518\t2699522\n"
            "chrY\t2649518\t2649522\n")
        result = self.capture("XY")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.path / "x_diploid.bed").read_text(), "chrX\t2699513\t2699520\n")
        self.assertEqual((self.path / "x_haploid.bed").read_text(), "chrX\t2699520\t2699527\n")
        self.assertEqual((self.path / "y_haploid.bed").read_text(), "chrY\t2649520\t2649527\n")
        (self.path / "targets.bed").write_text(
            "chrX\t2699518\t2699522\tx_boundary\nchrY\t2649518\t2649522\ty_boundary\n"
            "chrY\t10001\t10002\ty_par\n")
        result = self.targets("XY")
        self.assertEqual(result.returncode, 0, result.stderr)
        with open(self.path / "status.tsv") as handle:
            rows = list(csv.DictReader(handle, delimiter="\t"))
        self.assertEqual([(r["status"], r["in_scope_bases"]) for r in rows],
                         [("InScope", "4"), ("PartiallyInScope", "2"), ("ParOnYExcluded", "0")])
        self.assertEqual((self.path / "x_diploid_target.bed").read_text(), "chrX\t2699518\t2699520\n")
        self.assertEqual((self.path / "x_haploid_target.bed").read_text(), "chrX\t2699520\t2699522\n")
        self.assertIn("chrY\t2649518\t2649520\tParOnYExcluded", (self.path / "excluded.tsv").read_text())
        self.assertEqual(json.loads((self.path / "summary.json").read_text())["excluded_intervals"], 1)

    def test_xy_y_par_only_is_excluded_exactly(self):
        (self.path / "capture.bed").write_text("chr1\t10\t20\nchrY\t10000\t10010\n")
        result = self.capture("XY")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.path / "y_haploid.bed").read_text(), "")
        self.assertIn("chrY\t10000\t10010\tParOnYExcluded", (self.path / "excluded.tsv").read_text())
        (self.path / "targets.bed").write_text("chrY\t10001\t10002\tpar\nchrY\t9995\t10002\tmixed\n")
        result = self.targets("XY")
        self.assertEqual(result.returncode, 0, result.stderr)
        with open(self.path / "status.tsv") as handle:
            rows = list(csv.DictReader(handle, delimiter="\t"))
        self.assertEqual([row["status"] for row in rows], ["ParOnYExcluded", "OutOfAnalysisScope"])

    def test_sex_calling_rejects_non_hg19_lengths(self):
        (self.path / "ref.fa.fai").write_text("chr1\t100\t0\t0\t0\nchrX\t100\t0\t0\t0\n")
        result = self.capture("XX")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("hg19 chrX length", result.stderr)

    def test_mitochondrial_capture_and_target_are_independent_of_sex(self):
        (self.path / "capture.bed").write_text("chr1\t10\t20\nchrM\t16568\t16571\n")
        result = self.capture()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.path / "mt.bed").read_text(), "chrM\t16563\t16571\n")
        self.assertEqual((self.path / "has_mt.txt").read_text(), "true\n")
        self.assertIn("chrM\t16563\t16571", (self.path / "analysis.bed").read_text())
        self.assertNotIn("chrM", (self.path / "bqsr.bed").read_text())
        (self.path / "targets.bed").write_text("chrM\t16566\t16571\tmt_inside\nchrM\t1\t3\tmt_outside\n")
        result = self.targets()
        self.assertEqual(result.returncode, 0, result.stderr)
        with open(self.path / "status.tsv") as handle:
            rows = list(csv.DictReader(handle, delimiter="\t"))
        self.assertEqual([row["status"] for row in rows], ["InScope", "OutOfAnalysisScope"])
        self.assertEqual((self.path / "mt_target.bed").read_text(), "chrM\t16566\t16571\n")
        self.assertEqual((self.path / "target_has_mt.txt").read_text(), "true\n")

    def test_mitochondrial_capture_requires_hg19_chrM(self):
        (self.path / "ref.fa.fai").write_text("chr1\t100\t0\t0\t0\nchrM\t16569\t0\t0\t0\n")
        (self.path / "capture.bed").write_text("chr1\t10\t20\nchrM\t1\t5\n")
        result = self.capture()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("hg19 chrM length 16571", result.stderr)

    def test_wgs_without_capture_uses_full_primary_contigs(self):
        (self.path / "ref.fa.fai").write_text(
            "".join(f"chr{i}\t100\t0\t0\t0\n" for i in range(1, 23)) +
            "chrX\t155270560\t0\t0\t0\nchrY\t59373566\t0\t0\t0\nchrM\t16571\t0\t0\t0\n")
        result = self.capture(capture_bed=None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len((self.path / "calling.bed").read_text().splitlines()), 22)
        self.assertEqual((self.path / "mt.bed").read_text(), "chrM\t0\t16571\n")
        self.assertEqual((self.path / "has_x_diploid.txt").read_text(), "false\n")
        self.assertIn("chrX\t0\t155270560\tComplementUnspecified", (self.path / "excluded.tsv").read_text())
        summary = json.loads((self.path / "summary.json").read_text())
        self.assertEqual(summary["analysis_mode"], "WGS")
        self.assertIsNone(summary["capture_intervals"])
        self.assertIsNone(summary["capture_padding_bp"])
        (self.path / "targets.bed").write_text("chr2\t1\t3\tgenome_target\nchrM\t1\t3\tmt_target\n")
        result = self.targets(capture_bed=None)
        self.assertEqual(result.returncode, 0, result.stderr)
        with open(self.path / "status.tsv") as handle:
            rows = list(csv.DictReader(handle, delimiter="\t"))
        self.assertEqual([row["status"] for row in rows], ["InScope", "InScope"])
        self.assertEqual([row["outside_capture"] for row in rows], ["not_applicable", "not_applicable"])
        result = self.capture("XY", capture_bed=None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.path / "x_diploid.bed").read_text(),
                         "chrX\t60000\t2699520\nchrX\t154931043\t155260560\n")
        self.assertIn("chrY\t2649520\t59034049", (self.path / "y_haploid.bed").read_text())

    def test_wgs_requires_primary_reference_contigs(self):
        result = self.capture(capture_bed=None)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("WGS requires primary hg19 contigs", result.stderr)

    def test_all_targets_outside_scope_has_no_genotype_branch(self):
        self.assertEqual(self.capture().returncode, 0)
        (self.path / "targets.bed").write_text("chr2\t1\t2\toutside\n")
        result = self.targets()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.path / "in_scope.bed").read_text(), "")
        self.assertEqual((self.path / "has.txt").read_text(), "false\n")

    def test_delivery_stays_unreleased_with_mitochondrial_vcf(self):
        (self.path / "capture.bed").write_text("chr1\t10\t20\nchrM\t1\t5\n")
        self.assertEqual(self.capture().returncode, 0)
        with gzip.open(self.path / "sample.g.vcf.gz", "wt") as handle:
            handle.write("##fileformat=VCFv4.2\n##ALT=<ID=NON_REF,Description=\"Any\">\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tS1\nchr1\t6\t.\tA\t<NON_REF>\t.\t.\tEND=10\tGT\t0/0\n")
        (self.path / "sample.g.vcf.gz.tbi").write_bytes(b"index")
        with gzip.open(self.path / "sample.mt.vcf.gz", "wt") as handle:
            handle.write("##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tS1\n")
        (self.path / "sample.mt.vcf.gz.tbi").write_bytes(b"index")
        (self.path / "fastp.json").write_text(json.dumps({"summary": {"after_filtering": {"total_reads": 2}}}))
        (self.path / "duplicates.txt").write_text("metrics\n")
        command = [
            sys.executable, str(ROOT / "scripts/delivery.py"), "--sample-id", "S1",
            "--gvcf", "sample.g.vcf.gz", "--index", "sample.g.vcf.gz.tbi",
            "--calling-bed", "calling.bed", "--capture-bed", "capture.bed",
            "--analysis-bed", "analysis.bed",
            "--capture-summary", "summary.json", "--fastp-json", "fastp.json",
            "--mt-vcf", "sample.mt.vcf.gz", "--mt-index", "sample.mt.vcf.gz.tbi",
            "--duplicate-metrics", "duplicates.txt", "--qc-json", "qc.json",
            "--manifest-json", "manifest.json",
        ]
        result = subprocess.run(command, cwd=self.path, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        qc = json.loads((self.path / "qc.json").read_text())
        self.assertFalse(qc["ready_for_import_test"])
        self.assertFalse(qc["ready_for_report"])
        self.assertEqual(qc["analysis_mode"], "WXS")
        self.assertEqual(qc["total_targets"], None)
        self.assertEqual(qc["fastp_after_filtering"]["total_reads"], 2)
        self.assertEqual(qc["mitochondrial_vcf"], "sample.mt.vcf.gz")
        manifest = json.loads((self.path / "manifest.json").read_text())
        self.assertIn("mt_vcf", manifest["files_sha256"])
        with gzip.open(self.path / "sample.mt.vcf.gz", "wt") as handle:
            handle.write("##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tS1\n"
                         "chr1\t1\t.\tA\tG\t.\tPASS\t.\tGT\t1\n")
        result = subprocess.run(command, cwd=self.path, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("non-chrM", result.stderr)

    def test_wgs_delivery_without_capture_bed(self):
        (self.path / "ref.fa.fai").write_text(
            "".join(f"chr{i}\t100\t0\t0\t0\n" for i in range(1, 23)) +
            "chrX\t155270560\t0\t0\t0\nchrY\t59373566\t0\t0\t0\nchrM\t16571\t0\t0\t0\n")
        self.assertEqual(self.capture(capture_bed=None).returncode, 0)
        with gzip.open(self.path / "sample.g.vcf.gz", "wt") as handle:
            handle.write("##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tS1\n"
                         "chr1\t1\t.\tA\t<NON_REF>\t.\t.\tEND=100\tGT\t0/0\n")
        with gzip.open(self.path / "sample.mt.vcf.gz", "wt") as handle:
            handle.write("##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tS1\n")
        (self.path / "sample.g.vcf.gz.tbi").write_bytes(b"index")
        (self.path / "sample.mt.vcf.gz.tbi").write_bytes(b"index")
        (self.path / "fastp.json").write_text("{}")
        (self.path / "duplicates.txt").write_text("metrics\n")
        result = subprocess.run([
            sys.executable, str(ROOT / "scripts/delivery.py"), "--sample-id", "S1",
            "--gvcf", "sample.g.vcf.gz", "--index", "sample.g.vcf.gz.tbi",
            "--calling-bed", "calling.bed", "--analysis-bed", "analysis.bed",
            "--capture-summary", "summary.json", "--fastp-json", "fastp.json",
            "--mt-vcf", "sample.mt.vcf.gz", "--mt-index", "sample.mt.vcf.gz.tbi",
            "--duplicate-metrics", "duplicates.txt", "--qc-json", "qc.json",
            "--manifest-json", "manifest.json",
        ], cwd=self.path, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        qc = json.loads((self.path / "qc.json").read_text())
        manifest = json.loads((self.path / "manifest.json").read_text())
        self.assertEqual(qc["analysis_mode"], "WGS")
        self.assertEqual(manifest["analysis_mode"], "WGS")
        self.assertIsNone(manifest["capture_bed_role"])
        self.assertNotIn("capture_bed", manifest["files_sha256"])


if __name__ == "__main__":
    unittest.main()
