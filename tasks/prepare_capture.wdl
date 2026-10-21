version 1.0

task PrepareCapture {
  input {
    File? capture_bed
    File ref_fai
    Int capture_padding
    String sex_chromosome_complement
    File script
    File validated
    String docker_image
    String cluster_config
  }
  command <<<
    set -euo pipefail
    test -s ~{validated}
    python3 ~{script} capture --fai ~{ref_fai} --capture-bed '~{default="" capture_bed}' \
      --padding ~{capture_padding} --calling-bed calling_intervals.bed \
      --excluded-tsv excluded_capture_intervals.tsv --summary-json capture_summary.json \
      --analysis-bed analysis_intervals.bed \
      --bqsr-bed bqsr_intervals.bed \
      --sex-chromosome-complement ~{sex_chromosome_complement} \
      --x-diploid-bed x_diploid.bed --has-x-diploid has_x_diploid.txt \
      --x-haploid-bed x_haploid.bed --has-x-haploid has_x_haploid.txt \
      --y-haploid-bed y_haploid.bed --has-y-haploid has_y_haploid.txt \
      --mt-bed mt.bed --has-mt has_mt.txt
  >>>
  output {
    File calling_bed = "calling_intervals.bed"
    File analysis_bed = "analysis_intervals.bed"
    File bqsr_bed = "bqsr_intervals.bed"
    File x_diploid_bed = "x_diploid.bed"
    File x_haploid_bed = "x_haploid.bed"
    File y_haploid_bed = "y_haploid.bed"
    File mt_bed = "mt.bed"
    Boolean has_x_diploid = read_boolean("has_x_diploid.txt")
    Boolean has_x_haploid = read_boolean("has_x_haploid.txt")
    Boolean has_y_haploid = read_boolean("has_y_haploid.txt")
    Boolean has_mt = read_boolean("has_mt.txt")
    File excluded_tsv = "excluded_capture_intervals.tsv"
    File summary = "capture_summary.json"
  }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
  }
}
