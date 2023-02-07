version 1.0

import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/2.0.1/workflows/refprep-TB.wdl" as clockwork_ref_prepWF
import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/2.4.0/tasks/combined_decontamination.wdl" as clckwrk_combonation
import "https://raw.githubusercontent.com/aofarrel/clockwork-wdl/2.4.0/tasks/variant_call_one_sample.wdl" as clckwrk_var_call
import "https://raw.githubusercontent.com/aofarrel/SRANWRP/main/tasks/processing_tasks.wdl" as sranwrp_processing
import "https://raw.githubusercontent.com/aofarrel/usher-sampled-wdl/nextstrain/usher_sampled.wdl" as build_treesWF
import "https://raw.githubusercontent.com/aofarrel/parsevcf/1.0.4/vcf_to_diff.wdl" as diff

workflow myco {
	input {
		Array[Array[File]] paired_fastqs
		File typical_tb_masked_regions

		Float   bad_data_threshold = 0.05
		Boolean decorate_tree = false
		File?   input_tree
		Int     min_coverage = 10
		File?   ref_genome_for_tree_building
		Int subsample_cutoff = -1
		Int subsample_seed = 1965
	}

	call clockwork_ref_prepWF.ClockworkRefPrepTB

	Array[Array[File]] pulled_fastqs   = select_all(paired_fastqs)
	scatter(pulled_fastq in pulled_fastqs) {
		call clckwrk_combonation.combined_decontamination_single as decontaminate_one_sample {
			input:
				unsorted_sam = true,
				reads_files = pulled_fastq,
				tarball_ref_fasta_and_index = ClockworkRefPrepTB.tar_indexd_dcontm_ref,
				ref_fasta_filename = "ref.fa",
				subsample_cutoff = subsample_cutoff,
				subsample_seed = subsample_seed
		}

		call clckwrk_var_call.variant_call_one_sample_simple as varcall_with_array {
			input:
				ref_dir = ClockworkRefPrepTB.tar_indexd_H37Rv_ref,
				reads_files = [decontaminate_one_sample.decontaminated_fastq_1, decontaminate_one_sample.decontaminated_fastq_2]
		} # output: varcall_with_array.vcf_final_call_set, varcall_with_array.mapped_to_ref

	}

	Array[File] minos_vcfs_=select_all(varcall_with_array.vcf_final_call_set)
	Array[File] bams_to_ref_=select_all(varcall_with_array.mapped_to_ref)


	scatter(vcfs_and_bams in zip(bams_to_ref_, minos_vcfs_)) {
		call diff.make_mask_and_diff as make_mask_and_diff_ {
			input:
				bam = vcfs_and_bams.left,
				vcf = vcfs_and_bams.right,
				min_coverage = min_coverage,
				tbmf = typical_tb_masked_regions
		}
	}

	call sranwrp_processing.cat_files as cat_diffs {
		input:
			files = make_mask_and_diff_.diff
	}

	if(decorate_tree) {
		call build_treesWF.usher_sampled_diff_to_taxonium as taxman {
			input:
				diffs = make_mask_and_diff_.diff,
				i = input_tree,
				ref = ref_genome_for_tree_building,
				coverage_reports = make_mask_and_diff_.report,
				bad_data_threshold = bad_data_threshold
		}
	}

	output {
		Array[File] minos = minos_vcfs_
		Array[File] masks = make_mask_and_diff_.mask_file
		Array[File] diffs = make_mask_and_diff_.diff
		File? tax_tree = taxman.taxonium_tree
	}
}
