version 1.0

task BaseRecalibrate {
  input {
    File bam
    File bai
    File ref_fasta
    File ref_fai
    File ref_dict
    File dbsnp_vcf
    File dbsnp_index
    File mills_vcf
    File mills_index
    File calling_bed
    String sample_id
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
    ln -s ~{dbsnp_vcf} dbsnp.vcf
    ln -s ~{dbsnp_index} dbsnp.vcf.idx
    ln -s ~{mills_vcf} mills.vcf
    ln -s ~{mills_index} mills.vcf.idx
    gatk --java-options '-Xmx24g' BaseRecalibrator \
      -R ref.fa -I input.bam --known-sites dbsnp.vcf --known-sites mills.vcf \
      -L ~{calling_bed} -O ~{sample_id}.recal.table
  >>>
  output { File table = "${sample_id}.recal.table" }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
    systemDisk: "cloud 500"
  }
}
