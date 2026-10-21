version 1.0

task Fastqc {
  input {
    File r1
    File r2
    String sample_id
    String docker_image
    String cluster_config
    Int threads
  }
  command <<<
    set -euo pipefail
    ln -s ~{r1} R1.fq.gz
    ln -s ~{r2} R2.fq.gz
    mkdir reports
    fastqc -t ~{threads} -o reports R1.fq.gz R2.fq.gz
    mv reports/R1_fastqc.html ~{sample_id}.R1.fastqc.html
    mv reports/R2_fastqc.html ~{sample_id}.R2.fastqc.html
  >>>
  output {
    File html_r1 = "${sample_id}.R1.fastqc.html"
    File html_r2 = "${sample_id}.R2.fastqc.html"
  }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
    systemDisk: "cloud 120"
  }
}
