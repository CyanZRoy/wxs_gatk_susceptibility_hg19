version 1.0

task GenotypeTargetRegions {
  input {
    File gvcf
    File index
    File ref_fasta
    File ref_fai
    File ref_dict
    File in_scope_bed
    String sample_id
    Int ploidy = 2
    String docker_image
    String cluster_config
  }
  command <<<
    set -euo pipefail
    ln -s ~{gvcf} input.g.vcf.gz
    ln -s ~{index} input.g.vcf.gz.tbi
    ln -s ~{ref_fasta} ref.fa
    ln -s ~{ref_fai} ref.fa.fai
    ln -s ~{ref_dict} ref.dict
    gatk --java-options '-Xmx24g' GenotypeGVCFs \
      -R ref.fa -V input.g.vcf.gz -L ~{in_scope_bed} \
      --sample-ploidy ~{ploidy} \
      --include-non-variant-sites true \
      -O ~{sample_id}.target_regions.all_sites.vcf.gz
    if [ ! -s ~{sample_id}.target_regions.all_sites.vcf.gz.tbi ]; then
      gatk IndexFeatureFile -I ~{sample_id}.target_regions.all_sites.vcf.gz
    fi
    test -s ~{sample_id}.target_regions.all_sites.vcf.gz.tbi
  >>>
  output {
    File vcf = "${sample_id}.target_regions.all_sites.vcf.gz"
    File index = "${sample_id}.target_regions.all_sites.vcf.gz.tbi"
  }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
    systemDisk: "cloud 150"
  }
}
