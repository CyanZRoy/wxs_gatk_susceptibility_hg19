version 1.0

task SelectMtTargetVariants {
  input {
    File vcf
    File index
    File ref_fasta
    File ref_fai
    File ref_dict
    File in_scope_bed
    String sample_id
    String docker_image
    String cluster_config
  }
  command <<<
    set -euo pipefail
    ln -s ~{vcf} input.vcf.gz
    ln -s ~{index} input.vcf.gz.tbi
    ln -s ~{ref_fasta} ref.fa
    ln -s ~{ref_fai} ref.fa.fai
    ln -s ~{ref_dict} ref.dict
    gatk --java-options '-Xmx24g' SelectVariants \
      -R ref.fa -V input.vcf.gz -L ~{in_scope_bed} \
      -O ~{sample_id}.mt.target_regions.vcf.gz
    if [ ! -s ~{sample_id}.mt.target_regions.vcf.gz.tbi ]; then
      gatk IndexFeatureFile -I ~{sample_id}.mt.target_regions.vcf.gz
    fi
    test -s ~{sample_id}.mt.target_regions.vcf.gz.tbi
  >>>
  output {
    File vcf = "${sample_id}.mt.target_regions.vcf.gz"
    File index = "${sample_id}.mt.target_regions.vcf.gz.tbi"
  }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
    systemDisk: "cloud 150"
  }
}
