version 1.0

task AlignReads {
  input {
    File r1
    File r2
    String sample_id
    String library_id
    String platform
    File ref_fasta
    File ref_fai
    File ref_dict
    Array[File]+ bwa_index_files
    File validated
    String docker_image
    String cluster_config
    Int threads
  }
  command <<<
    set -euo pipefail
    test -s ~{validated}
    ln -s ~{ref_fasta} ref.fa
    for index in ~{sep=' ' bwa_index_files}; do
      extension="${index##*.}"
      ln -s "$index" "ref.fa.$extension"
    done
    for extension in amb ann bwt pac sa; do test -s "ref.fa.$extension"; done
    rg=$(printf '@RG\tID:%s\tSM:%s\tLB:%s\tPL:%s' \
      '~{sample_id}' '~{sample_id}' '~{library_id}' '~{platform}')
    bwa mem -M -t ~{threads} -R "$rg" ref.fa ~{r1} ~{r2} | \
      samtools sort -@ ~{threads} -o ~{sample_id}.sorted.bam -
    samtools index -@ ~{threads} ~{sample_id}.sorted.bam
  >>>
  output {
    File bam = "${sample_id}.sorted.bam"
    File bai = "${sample_id}.sorted.bam.bai"
  }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
    systemDisk: "cloud 500"
  }
}
