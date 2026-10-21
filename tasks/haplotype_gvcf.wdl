version 1.0

task HaplotypeGvcf {
  input {
    File bam
    File bai
    File ref_fasta
    File ref_fai
    File ref_dict
    File calling_bed
    String sample_id
    Int ploidy = 2
    String docker_image
    String cluster_config
  }
  command <<<
    set -euo pipefail
    ln -s ~{bam} input.bam
    ln -s ~{bai} input.bam.bai
    ln -s ~{ref_fasta} ref.fa
    ln -s ~{ref_fai} ref.fa.fai
    ln -s ~{ref_dict} ref.dict
    gatk --java-options '-Xmx24g' HaplotypeCaller \
      -R ref.fa -I input.bam -L ~{calling_bed} -ERC GVCF --sample-ploidy ~{ploidy} \
      -O ~{sample_id}.g.vcf.gz
    if [ ! -s ~{sample_id}.g.vcf.gz.tbi ]; then
      gatk IndexFeatureFile -I ~{sample_id}.g.vcf.gz
    fi
    test -s ~{sample_id}.g.vcf.gz.tbi
  >>>
  output {
    File gvcf = "${sample_id}.g.vcf.gz"
    File index = "${sample_id}.g.vcf.gz.tbi"
  }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
    systemDisk: "cloud 500"
  }
}
