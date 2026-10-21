version 1.0

task MarkDuplicates {
  input {
    File bam
    File bai
    String sample_id
    String docker_image
    String cluster_config
  }
  command <<<
    set -euo pipefail
    ln -s ~{bam} input.bam
    ln -s ~{bai} input.bam.bai
    gatk --java-options '-Xmx24g' MarkDuplicatesSpark \
      -I input.bam -O ~{sample_id}.dedup.bam -M ~{sample_id}.duplicates.txt
    samtools index ~{sample_id}.dedup.bam
  >>>
  output {
    File bam = "${sample_id}.dedup.bam"
    File bai = "${sample_id}.dedup.bam.bai"
    File metrics = "${sample_id}.duplicates.txt"
  }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
    systemDisk: "cloud 500"
  }
}
