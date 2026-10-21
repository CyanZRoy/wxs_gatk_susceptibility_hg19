version 1.0

task ApplyRecalibration {
  input {
    File bam
    File bai
    File table
    File ref_fasta
    File ref_fai
    File ref_dict
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
    gatk --java-options '-Xmx24g' ApplyBQSR \
      -R ref.fa -I input.bam --bqsr-recal-file ~{table} \
      -O ~{sample_id}.recal.bam
    samtools index ~{sample_id}.recal.bam
  >>>
  output {
    File bam = "${sample_id}.recal.bam"
    File bai = "${sample_id}.recal.bam.bai"
  }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
    systemDisk: "cloud 500"
  }
}
