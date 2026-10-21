version 1.0

task QualimapQc {
  input {
    File bam
    File bai
    File? capture_bed
    String sample_id
    String docker_image
    String cluster_config
    Int threads
  }
  command <<<
    set -euo pipefail
    ln -s ~{bam} input.bam
    ln -s ~{bai} input.bam.bai
    if [ -n '~{default="" capture_bed}' ]; then
      awk 'BEGIN{OFS="\t"} !/^#/ && NF>=3 {print $1,$2,$3,".",0,"."}' '~{default="" capture_bed}' > capture.gff.bed
      qualimap bamqc -bam input.bam -gff capture.gff.bed -nt ~{threads} \
        --java-mem-size=24G -outformat PDF:HTML -outdir report
    else
      qualimap bamqc -bam input.bam -nt ~{threads} \
        --java-mem-size=24G -outformat PDF:HTML -outdir report
    fi
    tar -czf ~{sample_id}.qualimap.tar.gz report
  >>>
  output { File archive = "${sample_id}.qualimap.tar.gz" }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
    systemDisk: "cloud 500"
  }
}
