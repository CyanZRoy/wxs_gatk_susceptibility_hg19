version 1.0

task MitochondrialVariants {
  input {
    File bam
    File bai
    File ref_fasta
    File ref_fai
    File ref_dict
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
    gatk --java-options '-Xmx24g' Mutect2 \
      -R ref.fa -I input.bam -L ~{calling_bed} --mitochondria-mode \
      -O ~{sample_id}.mt.unfiltered.vcf.gz
    gatk --java-options '-Xmx24g' FilterMutectCalls \
      -R ref.fa -V ~{sample_id}.mt.unfiltered.vcf.gz \
      --stats ~{sample_id}.mt.unfiltered.vcf.gz.stats \
      --mitochondria-mode -O ~{sample_id}.mt.vcf.gz
    if [ ! -s ~{sample_id}.mt.vcf.gz.tbi ]; then
      gatk IndexFeatureFile -I ~{sample_id}.mt.vcf.gz
    fi
    test -s ~{sample_id}.mt.vcf.gz.tbi
  >>>
  output {
    File unfiltered_vcf = "${sample_id}.mt.unfiltered.vcf.gz"
    File stats = "${sample_id}.mt.unfiltered.vcf.gz.stats"
    File vcf = "${sample_id}.mt.vcf.gz"
    File index = "${sample_id}.mt.vcf.gz.tbi"
  }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
    systemDisk: "cloud 150"
  }
}
