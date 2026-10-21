version 1.0

task TrimReads {
  input {
    File r1
    File r2
    String sample_id
    File validated
    String docker_image
    String cluster_config
    Int threads
  }
  command <<<
    set -euo pipefail
    test -s ~{validated}
    fastp --thread ~{threads} -i ~{r1} -I ~{r2} \
      -o ~{sample_id}.R1.trimmed.fq.gz -O ~{sample_id}.R2.trimmed.fq.gz \
      -j ~{sample_id}.fastp.json -h ~{sample_id}.fastp.html
  >>>
  output {
    File trimmed_r1 = "${sample_id}.R1.trimmed.fq.gz"
    File trimmed_r2 = "${sample_id}.R2.trimmed.fq.gz"
    File report_json = "${sample_id}.fastp.json"
    File report_html = "${sample_id}.fastp.html"
  }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
    systemDisk: "cloud 200"
  }
}
