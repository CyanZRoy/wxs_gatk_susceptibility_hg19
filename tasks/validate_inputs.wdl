version 1.0

task ValidateInputs {
  input {
    File identity_lines
    File fastq_r1
    File fastq_r2
    Array[File]+ bwa_index_files
    Int capture_padding
    String docker_image
    String cluster_config
  }
  command <<<
    set -euo pipefail
    test -s ~{fastq_r1}
    test -s ~{fastq_r2}
    test ~{length(bwa_index_files)} -eq 5
    test ~{capture_padding} -ge 0
    python3 -c 'import pathlib,re,sys; v=pathlib.Path(sys.argv[1]).read_text().splitlines(); assert len(v)==3, "identity field count"; assert all(re.fullmatch(r"[A-Za-z0-9_.-]+",x) for x in v)' ~{identity_lines}
    printf 'ok\n' > validated.txt
  >>>
  output { File marker = "validated.txt" }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
  }
}
