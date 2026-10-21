#!/usr/bin/env python3
"""Check a GATK gVCF test package and record conservative release metadata."""

import argparse
import gzip
import hashlib
import json
from pathlib import Path


def digest(path):
    hasher = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def check_gvcf(path, sample_id):
    with gzip.open(path, "rt") as handle:
        first = handle.readline()
        if not first.startswith("##fileformat=VCF"):
            raise ValueError(f"gVCF has no VCF fileformat header: {path}")
        sample_header = None
        records = 0
        symbolic_allele = False
        for line in handle:
            if line.startswith("#CHROM"):
                sample_header = line.rstrip("\n").split("\t")
            elif not line.startswith("#"):
                records += 1
                fields = line.split("\t", 5)
                symbolic_allele |= len(fields) > 4 and "<NON_REF>" in fields[4]
        if sample_header is None or len(sample_header) != 10 or sample_header[-1] != sample_id:
            raise ValueError(f"gVCF must have exactly the requested sample: {path}")
        if not records or not symbolic_allele:
            raise ValueError(f"gVCF has no reference-confidence records: {path}")


def check_mitochondrial_vcf(path, sample_id):
    with gzip.open(path, "rt") as handle:
        if not handle.readline().startswith("##fileformat=VCF"):
            raise ValueError(f"mitochondrial VCF has no VCF fileformat header: {path}")
        samples = None
        for line in handle:
            if line.startswith("#CHROM"):
                samples = line.rstrip("\n").split("\t")
                break
        if samples is None or len(samples) != 10 or samples[-1] != sample_id:
            raise ValueError(f"mitochondrial VCF must have exactly the requested sample: {path}")
        for line in handle:
            fields = line.rstrip("\n").split("\t")
            if len(fields) != 10 or fields[0] != "chrM":
                raise ValueError(f"mitochondrial VCF has a non-chrM or malformed record: {path}")
            try:
                position = int(fields[1])
            except ValueError as exc:
                raise ValueError(f"mitochondrial VCF has a non-integer position: {path}") from exc
            if not 1 <= position <= 16571:
                raise ValueError(f"mitochondrial VCF has an out-of-reference position: {path}")


def main():
    parser = argparse.ArgumentParser()
    for key in ("sample-id", "gvcf", "index", "calling-bed", "analysis-bed",
                "capture-summary", "fastp-json", "duplicate-metrics", "qc-json", "manifest-json"):
        parser.add_argument("--" + key, required=True)
    parser.add_argument("--capture-bed", default="")
    parser.add_argument("--target-bed", default="")
    parser.add_argument("--sex-chromosome-complement", default="UNKNOWN")
    for partition in ("x-diploid", "x-haploid", "y-haploid"):
        parser.add_argument("--" + partition + "-gvcf", default="")
        parser.add_argument("--" + partition + "-index", default="")
    parser.add_argument("--mt-vcf", default="")
    parser.add_argument("--mt-index", default="")
    args = parser.parse_args()
    files = {key: Path(getattr(args, key.replace("-", "_"))) for key in
             ("gvcf", "index", "calling-bed", "analysis-bed", "capture-summary",
              "fastp-json", "duplicate-metrics")}
    if args.capture_bed:
        files["capture_bed"] = Path(args.capture_bed)
    if args.target_bed:
        files["target_bed"] = Path(args.target_bed)
    partitions = {}
    for partition in ("x_diploid", "x_haploid", "y_haploid"):
        gvcf = getattr(args, partition + "_gvcf")
        index = getattr(args, partition + "_index")
        if bool(gvcf) != bool(index):
            raise ValueError(f"{partition} gVCF/index must be supplied together")
        if gvcf:
            files[partition + "_gvcf"] = Path(gvcf)
            files[partition + "_index"] = Path(index)
            partitions[partition] = str(gvcf)
    if bool(args.mt_vcf) != bool(args.mt_index):
        raise ValueError("mitochondrial VCF/index must be supplied together")
    if args.mt_vcf:
        files["mt_vcf"] = Path(args.mt_vcf)
        files["mt_index"] = Path(args.mt_index)
    for key, path in files.items():
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"{key} is missing or empty: {path}")
    check_gvcf(files["gvcf"], args.sample_id)
    for partition in partitions:
        check_gvcf(files[partition + "_gvcf"], args.sample_id)
    if args.mt_vcf:
        check_mitochondrial_vcf(files["mt_vcf"], args.sample_id)
    with open(files["fastp-json"]) as handle:
        fastp = json.load(handle)
    with open(files["capture-summary"]) as handle:
        capture = json.load(handle)
    analysis_mode = "WXS" if args.capture_bed else "WGS"
    if capture.get("analysis_mode") != analysis_mode:
        raise ValueError("analysis mode disagrees with capture summary")
    if capture.get("sex_chromosome_complement") != args.sex_chromosome_complement:
        raise ValueError("sex chromosome complement disagrees with capture summary")
    expected = capture.get("calling_intervals_by_partition", {})
    for partition in ("x_diploid", "x_haploid", "y_haploid"):
        if bool(expected.get(partition, 0)) != (partition in partitions):
            raise ValueError(f"{partition} gVCF does not match calling intervals")
    if bool(expected.get("mt", 0)) != bool(args.mt_vcf):
        raise ValueError("mitochondrial VCF does not match calling intervals")
    output_mode = ("gvcf_with_target_region_intermediate" if args.target_bed
                   else "gvcf_test_package")
    qc = {
        "schema_version": "0.1.0", "sample_id": args.sample_id,
        "analysis_mode": analysis_mode,
        "output_mode": output_mode, "format_precheck_passed": True,
        "ready_for_import_test": False,
        "ready_for_report": False,
        "import_blockers": ["Index query and full sample QC have not been validated"],
        "report_blockers": ["Clinical target list and assay-specific QC are not validated"],
        "total_targets": None, "called_targets": None,
        "fastp_after_filtering": fastp.get("summary", {}).get("after_filtering"),
        "capture": capture,
        "sex_chromosome_complement": args.sex_chromosome_complement,
        "sex_gvcf_partitions": sorted(partitions),
        "mitochondrial_vcf": str(files["mt_vcf"]) if args.mt_vcf else None,
    }
    manifest = {
        "schema_version": "0.1.0", "workflow": "WxsGermlineHg19",
        "sample_id": args.sample_id, "assembly": "hg19_ucsc",
        "output_mode": output_mode, "analysis_mode": analysis_mode,
        "capture_bed_role": "capture_assay_regions" if args.capture_bed else None,
        "target_bed": str(files["target_bed"]) if args.target_bed else None,
        "supported_contigs": capture["supported_contigs"],
        "sex_chromosome_complement": args.sex_chromosome_complement,
        "sex_gvcf_partitions": partitions,
        "mitochondrial_vcf": str(files["mt_vcf"]) if args.mt_vcf else None,
        "files_sha256": {key: digest(path) for key, path in files.items()},
        "capture": capture,
    }
    Path(args.qc_json).write_text(json.dumps(qc, ensure_ascii=False, indent=2) + "\n")
    Path(args.manifest_json).write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
