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
    call_dir="$PWD"
    input_path() {
      case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "$call_dir" "$1" ;;
      esac
    }
    stage_file() {
      cp -f "$(input_path "$1")" "$2"
    }
    copy_task_logs() {
      for log in script stdout stderr; do
        if [ -f "$call_dir/$log" ]; then
          cp -f "$call_dir/$log" "$call_dir/$log.txt" || true
        fi
      done
    }
    trap copy_task_logs EXIT
    local_work=$(mktemp -d /tmp/wxs-task-XXXXXX)
    mkdir -p "$local_work/tmp"
    export TMPDIR="$local_work/tmp" TMP="$local_work/tmp" TEMP="$local_work/tmp"
    export _JAVA_OPTIONS="-Djava.io.tmpdir=$TMPDIR"
    cd "$local_work"
    stage_file "~{bam}" input.bam
    stage_file "~{bai}" input.bam.bai
    stage_file "~{ref_fasta}" ref.fa
    stage_file "~{ref_fai}" ref.fa.fai
    stage_file "~{ref_dict}" ref.dict
    stage_file "~{calling_bed}" calling.bed
    gatk --java-options '-Xmx24g' Mutect2 \
      -R ref.fa -I input.bam -L calling.bed --mitochondria-mode \
      -O ~{sample_id}.mt.unfiltered.vcf.gz
    gatk --java-options '-Xmx24g' FilterMutectCalls \
      -R ref.fa -V ~{sample_id}.mt.unfiltered.vcf.gz \
      --stats ~{sample_id}.mt.unfiltered.vcf.gz.stats \
      --mitochondria-mode -O ~{sample_id}.mt.vcf.gz
    if [ ! -s ~{sample_id}.mt.vcf.gz.tbi ]; then
      gatk IndexFeatureFile -I ~{sample_id}.mt.vcf.gz
    fi
    test -s ~{sample_id}.mt.vcf.gz.tbi
    cp -f ~{sample_id}.mt.unfiltered.vcf.gz ~{sample_id}.mt.unfiltered.vcf.gz.stats ~{sample_id}.mt.vcf.gz ~{sample_id}.mt.vcf.gz.tbi "$call_dir"/
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
