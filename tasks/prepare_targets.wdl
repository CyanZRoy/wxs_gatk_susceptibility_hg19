version 1.0

task PrepareTargets {
  input {
    File target_bed
    File? capture_bed
    File calling_bed
    File x_diploid_bed
    File x_haploid_bed
    File y_haploid_bed
    File mt_bed
    String sex_chromosome_complement
    File ref_fai
    File script
    String docker_image
    String cluster_config
  }
  command <<<
    set -euo pipefail
    python3 ~{script} targets --fai ~{ref_fai} --target-bed ~{target_bed} \
      --capture-bed '~{default="" capture_bed}' --calling-bed ~{calling_bed} \
      --in-scope-bed target_in_scope.bed --status-tsv target_scope.tsv \
      --has-in-scope has_in_scope.txt \
      --sex-chromosome-complement ~{sex_chromosome_complement} \
      --x-diploid-bed ~{x_diploid_bed} --x-diploid-in-scope-bed x_diploid_target.bed --has-x-diploid has_x_diploid.txt \
      --x-haploid-bed ~{x_haploid_bed} --x-haploid-in-scope-bed x_haploid_target.bed --has-x-haploid has_x_haploid.txt \
      --y-haploid-bed ~{y_haploid_bed} --y-haploid-in-scope-bed y_haploid_target.bed --has-y-haploid has_y_haploid.txt \
      --mt-bed ~{mt_bed} --mt-in-scope-bed mt_target.bed --has-mt has_mt.txt
  >>>
  output {
    File in_scope_bed = "target_in_scope.bed"
    File status_tsv = "target_scope.tsv"
    Boolean has_in_scope = read_boolean("has_in_scope.txt")
    File x_diploid_in_scope_bed = "x_diploid_target.bed"
    File x_haploid_in_scope_bed = "x_haploid_target.bed"
    File y_haploid_in_scope_bed = "y_haploid_target.bed"
    File mt_in_scope_bed = "mt_target.bed"
    Boolean has_x_diploid = read_boolean("has_x_diploid.txt")
    Boolean has_x_haploid = read_boolean("has_x_haploid.txt")
    Boolean has_y_haploid = read_boolean("has_y_haploid.txt")
    Boolean has_mt = read_boolean("has_mt.txt")
  }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
  }
}
