version 1.0

task MakeDelivery {
  input {
    File gvcf
    File index
    File calling_bed
    File analysis_bed
    File? capture_bed
    File capture_summary
    File? target_bed
    String sex_chromosome_complement
    File? x_diploid_gvcf
    File? x_diploid_index
    File? x_haploid_gvcf
    File? x_haploid_index
    File? y_haploid_gvcf
    File? y_haploid_index
    File? mt_vcf
    File? mt_index
    File fastp_json
    File duplicate_metrics
    String sample_id
    File script
    String docker_image
    String cluster_config
  }
  command <<<
    set -euo pipefail
    python3 ~{script} --sample-id '~{sample_id}' --gvcf ~{gvcf} \
      --index ~{index} --calling-bed ~{calling_bed} \
      --analysis-bed ~{analysis_bed} \
      --capture-bed '~{default="" capture_bed}' --capture-summary ~{capture_summary} \
      --target-bed '~{default="" target_bed}' \
      --sex-chromosome-complement ~{sex_chromosome_complement} \
      --x-diploid-gvcf '~{default="" x_diploid_gvcf}' --x-diploid-index '~{default="" x_diploid_index}' \
      --x-haploid-gvcf '~{default="" x_haploid_gvcf}' --x-haploid-index '~{default="" x_haploid_index}' \
      --y-haploid-gvcf '~{default="" y_haploid_gvcf}' --y-haploid-index '~{default="" y_haploid_index}' \
      --mt-vcf '~{default="" mt_vcf}' --mt-index '~{default="" mt_index}' \
      --duplicate-metrics ~{duplicate_metrics} \
      --fastp-json ~{fastp_json} \
      --qc-json ~{sample_id}.qc.json --manifest-json ~{sample_id}.run_manifest.json
  >>>
  output {
    File qc_json = "${sample_id}.qc.json"
    File manifest_json = "${sample_id}.run_manifest.json"
  }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
  }
}
