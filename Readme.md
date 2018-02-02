# GATK3 Human Exome Pipeline

**Please read this important information before running the app.**

## What does this app do?

This app implements the GATK 3.x best practices pipeline for a human exome. It receives human mappings as input, and refines them
(by deduplicating, realigning, and recalibrating them); subsequently, it calls variants using the GATK HaplotypeCaller. It
outputs the refined mappings as well as the called variants. NOTE: This app does not perform variant recalibration.

## What are typical use cases for this app?

Use this app when you have mapped exome reads to the human genome, and want to identify variants (SNPs and indels) using
the GATK 3.x best practices method.

If you have multiple samples, use this app for each sample, and choose the option to generate a gVCF file. Subsequently,
feed all the gVCFs to GATK GenotypeGVCFs in order to generate a multi-sample genotyped VCF.

## What data are required for this app to run?

This app is only a wrapper for the GATK 3.x software, and requires that you appropriately license and obtain that software yourself.
After licensing GATK, you should have received a file with the `GenomeAnalysisTK` prefix and the `.jar` suffix, such as `GenomeAnalysisTK.jar`
or `GenomeAnalysisTK-3.4-0.jar`. Place that file anywhere inside the project where this app will run. The app will search your
project for a file matching the pattern `GenomeAnalysisTK*.jar` and use it.

This app requires a coordinate-sorted BAM file (`*.bam`) with human mappings. No other file inputs are required; the app automatically
detects the reference genome (hg19, GRCh37/b37, or GRCh37+decoy/hs37d5) based on the BAM file header, and uses the appropriate GATK
resources (dbSNP and known indels). If your input mappings happen to be deduplicated already, you can skip the duplication marking step by
choosing the relevant option in the app configuration. You may also want to skip deduplication for certain amplicon protocols (such
as HaloPlex) that always generate reads starting at specific locations (and which would otherwise be marked as duplicate).

You can optionally choose a vendor exome kit from the following supported kits. **IMPORTANT**: Doing so has no effect on the
mappings refinement; deduplication, realignment and recalibration will be performed on the whole input. However, choosing
an exome will limit variation calling to within the kit coordinates (targets) only. By default, a 100bp padding will be
added around each target, and that can be changed in the app configuration. By constraining variation calling to within
the target coordinates (plus whatever padding), you can decrease the time the app requires to run, and often reduce false
positives (which tend to appear in low coverage regions, outside of target coordinates). Choice of a vendor exome kit is
optional, and if not provided, variation calling will be performed across the whole genome.

| Identifier | Marketing Name |
| --- | --- |
| agilent_sureselect_human_all_exon_50mb | Agilent SureSelect Human All Exon 50Mb |
| agilent_sureselect_human_all_exon_v1 | Agilent SureSelect Human All Exon V1 |
| agilent_sureselect_human_all_exon_v2 | Agilent SureSelect Human All Exon V2 |
| agilent_sureselect_human_all_exon_v4 | Agilent SureSelect Human All Exon V4 |
| agilent_sureselect_human_all_exon_v4_plus_utrs | Agilent SureSelect Human All Exon V4+UTRs |
| agilent_sureselect_human_all_exon_v5 | Agilent SureSelect Human All Exon V5 |
| agilent_sureselect_human_all_exon_v5_plus_utrs | Agilent SureSelect Human All Exon V5+UTRs |
| agilent_sureselect_human_all_exon_v6 | Agilent SureSelect Human All Exon V6 |
| agilent_sureselect_human_kinome_v1 | Agilent SureSelect Human Kinome V1 |
| haloplex_arrhythmia_ilm | HaloPlex Arrhythmia ILM |
| haloplex_cancer_research_panel_ilm | HaloPlex Cancer Research Panel ILM |
| haloplex_cardiomyopathy_ilm | HaloPlex Cardiomyopathy ILM |
| haloplex_chromosome_x_ilm | HaloPlex Chromosome-X ILM |
| haloplex_connective_tissue_disorder_ilm | HaloPlex Connective Tissue Disorder ILM |
| haloplex_exome | HaloPlex Exome |
| haloplex_iccg_ilm | HaloPlex ICCG ILM |
| haloplex_noonan_syndrome_ilm | HaloPlex Noonan Syndrome ILM |
| illumina_nextera_exome | Illumina Nextera Exome Enrichment Kit |
| illumina_nextera_rapid_capture_exome | Illumina Nextera Rapid Capture Exome |
| illumina_nextera_rapid_capture_expanded_exome | Illumina Nextera Rapid Capture Expanded Exome |
| illumina_truseq_exome | Illumina TruSeq Exome Enrichment Kit |
| nimblegen_seqcap_ez_50mb_human_utr_design | NimbleGen SeqCap EZ Designs: 50Mb Human UTR Design |
| nimblegen_seqcap_ez_comprehensive_cancer_design | NimbleGen SeqCap EZ Designs: Comprehensive Cancer Design |
| nimblegen_seqcap_ez_exome_utr | NimbleGen SeqCap EZ Exome +UTR |
| nimblegen_seqcap_ez_exome_v2 | NimbleGen SeqCap EZ Exome v2.0 |
| nimblegen_seqcap_ez_exome_v3 | NimbleGen SeqCap EZ Exome v3.0 |
| nimblegen_seqcap_ez_neurology_panel_design | NimbleGen SeqCap EZ Designs: Neurology Panel Design |
| vcrome_v2.1 | SeqCap EZ HGSC VCRome |

* * *

If you would like to see some other kit included in this list, do not hesitate to contact us at support@dnanexus.com.

## What does this app output?

This app outputs the refined (deduplicated, realigned, and recalibrated) mappings in BAM format (`*.bam`), as well
as the associated BAM index (`*.bai`).

The app also outputs a _genotyped_ VCF file (`*.vcf.gz`) and its associated tabix index (`*.vcf.gz.tbi`), or an
intermediate gVCF file (`*.g.vcf.gz`) and its associated tabix index (`*.g.vcf.gz.tbi`), or all of the above. This
behavior depends on the "Output format" option. The option works as follows:

* When set to `vcf`, the app runs GATK HaplotypeCaller in regular (_genotyped_ VCF) mode; this calls variants
and outputs only the locations of variation.
* When set to `gvcf`, the app runs GATK HaplotypeCaller in gVCF mode; this outputs information for all locations,
including sections which lack variation. The gVCF is an intermediate file that can be later used as input to
GATK GenotypeGVCFs, which can take multiple gVCF files (from multiple samples) and genotype them, creating a
cohort-level genotyped VCF. For more information, consult [this GATK article](http://gatkforums.broadinstitute.org/discussion/3893/calling-variants-on-cohorts-of-samples-using-the-haplotypecaller-in-gvcf-mode).
* When set to `both`, the app runs GATK HaplotypeCaller in gVCF mode, producing a gVCF file. Subsequently, it
runs GATK GenotypeGVCFs to genotype the gVCF into a regular VCF.

## How does this app work?

This app performs the following steps:

- Detects and downloads the GATK3 jar file from your project.
- Fetches your BAM input file and detects the human reference genome used.
- Based on the detected human genome, and on your choice of vendor exome kit, fetches additional data resources.
- Runs Picard MarkDuplicates to mark duplicates (unless configured to skip this step).
- Runs GATK RealignerTargetCreator and GATK IndelRealigner to realign indels.
- Runs GATK BaseRecalibrator and GATK PrintReads to recalibrate base quality scores.
- Runs GATK HaplotypeCaller (in VCF or gVCF mode) and optionally GATK GenotypeGVCFs.

The HaplotypeCaller step is performed only within target coordinates (with added padding), if a vendor exome kit is chosen.
