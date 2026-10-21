#!/usr/bin/env python3
"""Validate hg19 BED inputs and prepare explicit WXS calling/target intervals."""

import argparse
import csv
import json
from pathlib import Path


# GRC GRCh37 coordinates are 1-based inclusive; these are BED half-open.
PAR = {"chrX": [(60000, 2699520), (154931043, 155260560)],
       "chrY": [(10000, 2649520), (59034049, 59363566)]}
SEX_PARTITIONS = ("x_diploid", "x_haploid", "y_haploid")
PARTITIONS = SEX_PARTITIONS + ("mt",)
HG19_CHRM_LENGTH = 16571
WGS_CONTIGS = tuple(f"chr{i}" for i in range(1, 23)) + ("chrX", "chrY", "chrM")


def contigs(fai):
    result = {}
    for line in Path(fai).read_text().splitlines():
        parts = line.split("\t")
        if len(parts) < 2 or parts[0] in result:
            raise ValueError("invalid FASTA index")
        result[parts[0]] = int(parts[1])
    if not result:
        raise ValueError("empty FASTA index")
    return result


def read_bed(path, lengths):
    rows = []
    for number, line in enumerate(Path(path).read_text().splitlines(), 1):
        if not line.strip() or line.startswith(("#", "track", "browser")):
            continue
        parts = line.rstrip("\r").split("\t")
        if len(parts) < 3:
            raise ValueError(f"{path}:{number}: BED needs at least 3 tab-separated columns")
        chrom = parts[0]
        if chrom not in lengths:
            raise ValueError(f"{path}:{number}: contig {chrom} is absent from reference")
        try:
            start, end = int(parts[1]), int(parts[2])
        except ValueError as exc:
            raise ValueError(f"{path}:{number}: non-integer coordinate") from exc
        if not 0 <= start < end <= lengths[chrom]:
            raise ValueError(f"{path}:{number}: invalid/out-of-reference interval")
        name = parts[3] if len(parts) > 3 and parts[3] else f"target_{number}"
        rows.append((chrom, start, end, name))
    if not rows:
        raise ValueError(f"{path}: BED has no intervals")
    return rows


def merge(rows, lengths):
    order = {chrom: i for i, chrom in enumerate(lengths)}
    merged = []
    for chrom, start, end in sorted(rows, key=lambda x: (order[x[0]], x[1], x[2])):
        if merged and merged[-1][0] == chrom and start <= merged[-1][2]:
            merged[-1] = (chrom, merged[-1][1], max(end, merged[-1][2]))
        else:
            merged.append((chrom, start, end))
    return merged


def write_bed(path, rows):
    with open(path, "w") as handle:
        for chrom, start, end in rows:
            handle.write(f"{chrom}\t{start}\t{end}\n")


def autosome(chrom):
    return chrom.startswith("chr") and chrom[3:].isdigit() and 1 <= int(chrom[3:]) <= 22


def intersect(rows, masks, lengths):
    return merge([(c, max(s, a), min(e, b)) for c, s, e in rows
                  for mc, a, b in masks if c == mc and s < b and a < e], lengths)


def subtract(rows, masks, lengths):
    """Return exact half-open pieces of rows not covered by masks."""
    remaining = []
    for chrom, start, end in rows:
        pieces = [(start, end)]
        for mask_chrom, mask_start, mask_end in masks:
            if mask_chrom != chrom:
                continue
            pieces = [(left, right) for a, b in pieces
                      for left, right in ((a, min(b, mask_start)),
                                          (max(a, mask_end), b)) if left < right]
        remaining.extend((chrom, a, b) for a, b in pieces)
    return merge(remaining, lengths)


def sex_masks(lengths, complement):
    if complement not in ("UNKNOWN", "XX", "XY"):
        raise ValueError("sex_chromosome_complement must be UNKNOWN, XX or XY")
    if complement == "UNKNOWN":
        return {key: [] for key in SEX_PARTITIONS}
    if "chrX" not in lengths or lengths["chrX"] != 155270560:
        raise ValueError("sex calling requires hg19 chrX length 155270560 in FAI")
    if complement == "XX":
        return {"x_diploid": [("chrX", 0, lengths["chrX"])],
                "x_haploid": [], "y_haploid": []}
    if "chrY" not in lengths or lengths["chrY"] != 59373566:
        raise ValueError("XY calling requires hg19 chrY length 59373566 in FAI")
    x1, x2 = PAR["chrX"]
    y1, y2 = PAR["chrY"]
    return {"x_diploid": [("chrX", *x1), ("chrX", *x2)],
            "x_haploid": [("chrX", 0, x1[0]), ("chrX", x1[1], x2[0]),
                           ("chrX", x2[1], lengths["chrX"])],
            "y_haploid": [("chrY", 0, y1[0]), ("chrY", y1[1], y2[0]),
                           ("chrY", y2[1], lengths["chrY"])]}


def check_mitochondrial_reference(lengths, rows):
    if any(row[0] == "chrM" for row in rows) and lengths.get("chrM") != HG19_CHRM_LENGTH:
        raise ValueError("mitochondrial calling requires hg19 chrM length 16571 in FAI")


def whole_genome_rows(lengths):
    missing = [chrom for chrom in WGS_CONTIGS if lengths.get(chrom, 0) <= 0]
    if missing:
        raise ValueError("WGS requires primary hg19 contigs in FAI: " + ", ".join(missing))
    return [(chrom, 0, lengths[chrom], f"wgs_{chrom}") for chrom in WGS_CONTIGS]


def prepare_capture(args):
    lengths = contigs(args.fai)
    if args.padding < 0:
        raise ValueError("padding cannot be negative")
    mode = "WXS" if args.capture_bed else "WGS"
    rows = read_bed(args.capture_bed, lengths) if args.capture_bed else whole_genome_rows(lengths)
    padding = args.padding if args.capture_bed else 0
    check_mitochondrial_reference(lengths, rows)
    masks = sex_masks(lengths, args.sex_chromosome_complement)
    autosomal = [row for row in rows if autosome(row[0])]
    x_rows = [row for row in rows if row[0] == "chrX" and
              args.sex_chromosome_complement in ("XX", "XY")]
    y_rows = [row for row in rows if row[0] == "chrY" and
              args.sex_chromosome_complement == "XY"]
    mt_rows = [row for row in rows if row[0] == "chrM"]
    y_supported = intersect([(c, s, e) for c, s, e, _ in y_rows],
                            masks["y_haploid"], lengths)
    raw_supported = [(c, s, e) for c, s, e, _ in autosomal + x_rows + mt_rows] + y_supported
    padded = [(c, max(0, s - padding), min(lengths[c], e + padding))
              for c, s, e in raw_supported]
    auto_calling = merge([row for row in padded if autosome(row[0])], lengths)
    if not auto_calling:
        raise ValueError("analysis scope has no supported autosomal intervals")
    write_bed(args.calling_bed, auto_calling)
    partitions = {key: intersect(padded, mask, lengths) for key, mask in masks.items()}
    partitions["mt"] = merge([row for row in padded if row[0] == "chrM"], lengths)
    for key in PARTITIONS:
        write_bed(getattr(args, key + "_bed"), partitions[key])
        Path(getattr(args, "has_" + key)).write_text(str(bool(partitions[key])).lower() + "\n")
    write_bed(args.bqsr_bed, merge(auto_calling + [region for key in SEX_PARTITIONS
                                                  for region in partitions[key]], lengths))
    included = [row for row in rows if autosome(row[0]) or
                row[0] == "chrM" or
                (row[0] == "chrX" and args.sex_chromosome_complement in ("XX", "XY")) or
                (row[0] == "chrY" and args.sex_chromosome_complement == "XY" and
                 intersect([(row[0], row[1], row[2])], masks["y_haploid"], lengths))]
    excluded = []
    for chrom, start, end, _ in rows:
        if autosome(chrom) or chrom == "chrM" or (chrom == "chrX" and args.sex_chromosome_complement in ("XX", "XY")):
            continue
        if chrom == "chrY" and args.sex_chromosome_complement == "XY":
            excluded.extend((c, s, e, "ParOnYExcluded") for c, s, e in
                            subtract([(chrom, start, end)], masks["y_haploid"], lengths))
        else:
            reason = ("ComplementUnspecified" if chrom in PAR and args.sex_chromosome_complement == "UNKNOWN"
                      else "AbsentInXX" if chrom == "chrY" and args.sex_chromosome_complement == "XX"
                      else "UnsupportedContig")
            excluded.append((chrom, start, end, reason))
    analysis = merge(auto_calling + [region for group in partitions.values() for region in group], lengths)
    write_bed(args.analysis_bed, analysis)
    with open(args.excluded_tsv, "w", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t")
        writer.writerow(["chrom", "start", "end", "reason"])
        for chrom, start, end, reason in excluded:
            writer.writerow([chrom, start, end, reason])
    Path(args.summary_json).write_text(json.dumps({
        "assembly": "hg19_ucsc", "analysis_mode": mode,
        "capture_padding_bp": padding if mode == "WXS" else None,
        "capture_intervals": len(rows) if mode == "WXS" else None,
        "included_intervals": len(included),
        "excluded_intervals": len(excluded),
        "sex_chromosome_complement": args.sex_chromosome_complement,
        "supported_contigs": "chr1-chr22" + (",chrX" if args.sex_chromosome_complement != "UNKNOWN" else "") +
                             (",chrY_nonPAR" if args.sex_chromosome_complement == "XY" else "") +
                             (",chrM" if partitions["mt"] else ""),
        "calling_intervals_by_partition": {"autosomal": len(auto_calling),
                                           **{key: len(value) for key, value in partitions.items()}},
        "par_policy": ("XY chrX PAR diploid; chrY PAR excluded as duplicate reference sequence"
                       if args.sex_chromosome_complement == "XY" else
                       "XX chrX diploid; chrY excluded" if args.sex_chromosome_complement == "XX" else
                       "sex chromosomes excluded until complement is specified"),
        "mitochondrial_policy": "chrM Mutect2 mitochondrial mode intermediate; heteroplasmy and NuMT filtering unvalidated",
    }, indent=2) + "\n")


def prepare_targets(args):
    lengths = contigs(args.fai)
    sex_masks(lengths, args.sex_chromosome_complement)
    targets = read_bed(args.target_bed, lengths)
    check_mitochondrial_reference(lengths, targets)
    names = [row[3] for row in targets]
    if len(names) != len(set(names)):
        raise ValueError("target BED has duplicate target IDs")
    def optional_bed(path):
        if not Path(path).read_text().strip():
            return []
        return merge([(c, s, e) for c, s, e, _ in read_bed(path, lengths)], lengths)
    calling = {"autosomal": optional_bed(args.calling_bed)}
    calling.update({key: optional_bed(getattr(args, key + "_bed")) for key in PARTITIONS})
    capture = (merge([(c, s, e) for c, s, e, _ in read_bed(args.capture_bed, lengths)], lengths)
               if args.capture_bed else [])
    overlaps = {key: [] for key in calling}
    with open(args.status_tsv, "w", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t")
        writer.writerow(["target_id", "chrom", "start", "end", "in_scope_bases",
                         "outside_capture", "status"])
        for chrom, start, end, name in targets:
            target_pieces = []
            for key, regions in calling.items():
                matching = [(chrom, max(start, s), min(end, e))
                            for c, s, e in regions if c == chrom and s < end and e > start]
                overlaps[key].extend(matching)
                target_pieces.extend(matching)
            pieces = merge(target_pieces, lengths)
            bases = sum(min(end, e) - max(start, s) for _, s, e in pieces)
            outside_capture = (not any(c == chrom and s <= start and e >= end
                                       for c, s, e in capture) if args.capture_bed else None)
            status = ("UnsupportedContig" if not autosome(chrom) and chrom not in PAR and chrom != "chrM" else
                      "ComplementUnspecified" if chrom in PAR and args.sex_chromosome_complement == "UNKNOWN" else
                      "AbsentInXX" if chrom == "chrY" and args.sex_chromosome_complement == "XX" else
                      "ParOnYExcluded" if chrom == "chrY" and bases == 0 and
                      args.sex_chromosome_complement == "XY" and
                      any(s <= start and end <= e for s, e in PAR["chrY"]) else
                      "OutOfAnalysisScope" if bases == 0 else
                      "PartiallyInScope" if bases < end - start else "InScope")
            writer.writerow([name, chrom, start, end, bases,
                             str(outside_capture).lower() if outside_capture is not None else "not_applicable", status])
    for key, pieces in overlaps.items():
        clean = merge([p for p in pieces if p[1] < p[2]], lengths)
        if key != "autosomal":
            write_bed(getattr(args, key + "_in_scope_bed"), clean)
            Path(getattr(args, "has_" + key)).write_text(str(bool(clean)).lower() + "\n")
    write_bed(args.in_scope_bed, merge(overlaps["autosomal"], lengths))
    Path(args.has_in_scope).write_text(str(bool(overlaps["autosomal"])).lower() + "\n")


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    capture = sub.add_parser("capture")
    capture.add_argument("--fai", required=True)
    capture.add_argument("--capture-bed", default="")
    capture.add_argument("--padding", type=int, required=True)
    capture.add_argument("--calling-bed", required=True)
    capture.add_argument("--excluded-tsv", required=True)
    capture.add_argument("--summary-json", required=True)
    capture.add_argument("--analysis-bed", required=True)
    capture.add_argument("--bqsr-bed", required=True)
    capture.add_argument("--sex-chromosome-complement", default="UNKNOWN")
    for key in PARTITIONS:
        capture.add_argument("--" + key.replace("_", "-") + "-bed", required=True)
        capture.add_argument("--has-" + key.replace("_", "-"), required=True)
    targets = sub.add_parser("targets")
    targets.add_argument("--fai", required=True)
    targets.add_argument("--capture-bed", default="")
    targets.add_argument("--calling-bed", required=True)
    targets.add_argument("--target-bed", required=True)
    targets.add_argument("--in-scope-bed", required=True)
    targets.add_argument("--status-tsv", required=True)
    targets.add_argument("--has-in-scope", required=True)
    targets.add_argument("--sex-chromosome-complement", default="UNKNOWN")
    for key in PARTITIONS:
        targets.add_argument("--" + key.replace("_", "-") + "-bed", required=True)
        targets.add_argument("--" + key.replace("_", "-") + "-in-scope-bed", required=True)
        targets.add_argument("--has-" + key.replace("_", "-"), required=True)
    args = parser.parse_args()
    (prepare_capture if args.command == "capture" else prepare_targets)(args)


if __name__ == "__main__":
    main()
