#!/bin/bash

# The following line causes bash to exit at any point if there is any error
# and to output each line as it is executed -- useful for debugging
set -e -x -o pipefail


#
# Fetch inputs
#
mark-section "downloading inputs"
dx-download-all-inputs --parallel

# move and rename GATK jar file
mv ~/in/gatk_jar_file/* ~/GenomeAnalysisTK.jar

# Show the java version the worker is using
echo $(java -version)

#
# Use java7 as the default java version. 
# If java7 doesn't work with the GATK version (3.6 and above) then switch to java8 and try again.
#
update-alternatives --set java /usr/lib/jvm/java-7-openjdk-amd64/jre/bin/java
java -jar GenomeAnalysisTK.jar -version || (update-alternatives --set java /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java && java -jar GenomeAnalysisTK.jar -version)

#
# Calculate 80% of memory size, for java
#
head -n1 /proc/meminfo | awk '{print int($2*0.8/1024)}' >.mem_in_mb.txt
java="java -Xmx$(<.mem_in_mb.txt)m"


#
# Detect and download the appropriate human genome and related reference files
#
mark-section "detecting reference genome"
samtools view -H "$sorted_bam_path" | grep ^@SQ | cut -f1-3 | md5sum | cut -c1-32 >.genome-fingerprint.txt
case "$(<.genome-fingerprint.txt)" in
  9220d59b0d7a55a43b22cad4a87f6797)
    genome=b37
    subgenome=b37
    ;;
  45340a8b2bb041655c6f6d4f9985944f)
    genome=b37
    subgenome=hs37d5
    ;;
  2f23b2f7c9731db07f0d1c8f9bc8c9d9)
    genome=hg19
    subgenome=hg19
    ;;
  53a8d91e94b765bd69c104611a2f796c)
    genome=grch38
    subgenome=grch38 # No alt analysis
    dx-jobutil-report-error "The GRCh38 reference genome is not supported by this app."
    ;;
  *)
    echo "Non-matching human genome. The input BAM contains the following chromosomes (names and sizes):"
    samtools view -H "$sorted_bam_path" | grep ^@SQ | cut -f1-3
    dx-jobutil-report-error "The reference genome of the input BAM file did not match any of the known human ones. Additional diagnostic information has been provided in the job log."
    ;;
esac

mark-section "downloading reference genome"
APPDATA=project-B6JG85Z2J35vb6Z7pQ9Q02j8
dx cat "$APPDATA:/misc/gatk_resource_archives/${subgenome}.fasta-index.tar.gz" | tar zxf -


# If BED file is given to limit variant calling add to region_opts. (-e returns true if the file exists)
if [[ -e $bedfile_path ]]; then
    echo "BED file provided to limit variant calling to specified regions"
    region_opts=("-L" "$bedfile_path")
        if [[ "$padding" != "0" ]]
            then
                echo "BED file intervals will be padded by $padding bases"
                region_opts+=("-ip" "$padding")
        else
            echo "Padding set to 0 so BED file intervals will not be extended"
        fi
else
    echo "BED file not provided so limit variant calling not restricted. padding argument not relevant"
fi

#echo $region_opts

# Fetch GATK resources (these have been prepared in archives)
mark-section "fetching GATK resources"
dx cat "$APPDATA:/misc/gatk_resource_archives/gatk.resources.${genome}.tar" | tar xf -
known1="1000G_phase1.indels.${genome}.vcf.gz"
known2="Mills_and_1000G_gold_standard.indels.${genome}.vcf.gz"
dbsnp="dbsnp_137.${genome}.vcf.gz"

#
# Run Picard MarkDuplicates
#
if [[ "$skip_markduplicates" != "true" ]]
then
  mark-section "marking duplicates - creates indexed sorted BAM"
  $java -jar picard.jar MarkDuplicates I="$sorted_bam_path" O=deduplicated.bam M=output.metrics CREATE_INDEX=true VALIDATION_STRINGENCY=SILENT $extra_md_options
  rm -f "$sorted_bam_path"
  realign_input="deduplicated.bam"
else
  mark-section "indexing input mappings"
  samtools index "$sorted_bam_path"
  realign_input="$sorted_bam_path"
fi

#
# Run GATK indel realignment
#
mark-section "realigning indels"
$java -jar GenomeAnalysisTK.jar -nt `nproc` -T RealignerTargetCreator -R genome.fa -I "$realign_input" -o realign.intervals -known $known1 -known $known2 $extra_rtc_options
$java -jar GenomeAnalysisTK.jar -T IndelRealigner -R genome.fa -I "$realign_input" -targetIntervals realign.intervals -known $known1 -known $known2 -o realigned.bam $extra_ir_options
rm -f "$realign_input"

#
# Run GATK base recalibration
#
mark-section "recalibrating base quality scores"
$java -jar GenomeAnalysisTK.jar -nct `nproc` -T BaseRecalibrator -R genome.fa -I realigned.bam -o recal.grp -knownSites $dbsnp -knownSites $known1 -knownSites $known2 $extra_br_options
$java -jar GenomeAnalysisTK.jar -nct `nproc` -T PrintReads -R genome.fa -I realigned.bam -BQSR recal.grp -o recal.bam $extra_pr_options
rm -f realigned.bam

#
# Run GATK HaplotypeCaller
#
## App has options to output VCF, gVCF or both
# if just VCF
if [[ "$output_format" == "vcf" ]]; then
  $java -jar GenomeAnalysisTK.jar -nct `nproc` -T HaplotypeCaller -R genome.fa -o output.vcf.gz --dbsnp $dbsnp -I recal.bam "${region_opts[@]}" $extra_hc_options
  # only index VCF if it doesn't already exist (-e returns true if the file exists)
  if [[ ! -e output.vcf.gz.tbi ]]; then
    mark-section "indexing vcf"
    tabix -p vcf output.vcf.gz
  fi
# if not vcf output gVCF
else
  $java -jar GenomeAnalysisTK.jar -nct `nproc` -T HaplotypeCaller -R genome.fa -o output.g.vcf.gz --dbsnp $dbsnp -I recal.bam -ERC GVCF -variant_index_type LINEAR -variant_index_parameter 128000 "${region_opts[@]}" $extra_hc_options
  # only index VCF if it doesn't already exist (-e returns true if the file exists)
  if [[ ! -e output.g.vcf.gz.tbi ]]; then
    mark-section "indexing gvcf"
    tabix -p vcf output.g.vcf.gz
  fi
  # if output is both repeat, for VCF
  if [[ "$output_format" == "both" ]]; then
    $java -jar GenomeAnalysisTK.jar -nt `nproc` --dbsnp $dbsnp -T GenotypeGVCFs -R genome.fa -o output.vcf.gz -V output.g.vcf.gz $extra_gg_options
    # only index VCF if it doesn't already exist (-e returns true if the file exists)
    if [[ ! -e output.vcf.gz.tbi ]]; then
      mark-section "indexing vcf"
      tabix -p vcf output.vcf.gz
    fi
  fi
fi


mark-section "uploading results"
# make output folders
mkdir -p ~/out/bam/output/ ~/out/bai/output/ ~/out/outputmetrics/QC/ ~/out/vcf/output/ ~/out/vcf_tbi/output/  ~/out/gvcf/output/ ~/out/gvcf_tbi/output/

# move and rename output files
mv recal.bam ~/out/bam/output/"$sorted_bam_prefix".refined.bam
mv recal.bai ~/out/bai/output/"$sorted_bam_prefix".refined.bam.bai

# test if mark duplicates was requested before trying to move mark duplicates output metrics
if [[ "$skip_markduplicates" != "true" ]]
then
    mv output.metrics ~/out/outputmetrics/QC/"$sorted_bam_prefix".output.metrics
fi

if [[ "$output_format" != "gvcf" ]]; then
  mv output.vcf.gz ~/out/vcf/output/"$sorted_bam_prefix".vcf.gz
  mv output.vcf.gz.tbi ~/out/vcf_tbi/output/"$sorted_bam_prefix".vcf.gz.tbi
fi

if [[ "$output_format" != "vcf" ]]; then
  mv output.g.vcf.gz ~/out/gvcf/output/"$sorted_bam_prefix".g.vcf.gz
  mv output.g.vcf.gz.tbi ~/out/gvcf_tbi/output/"$sorted_bam_prefix".g.vcf.gz.tbi
fi

#
# Upload results
#
dx-upload-all-outputs --parallel
mark-success
