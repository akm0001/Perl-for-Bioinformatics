#!/usr/bin/env perl

use strict;
use warnings;
use Carp;
use Getopt::Long;
use IO::Routine;
use Data::Dumper;

my ($LASTCHANGEDBY) = q$LastChangedBy: konganti $ =~ m/.+?\:(.+)/;
my ($LASTCHANGEDDATE) = q$LastChangedDate: 2017-09-29 17:45:27 -0500 (Fri, 29 September 2017)  $ =~ m/.+?\:(.+)/;
my ($VERSION) = q$LastChangedRevision: 2708 $ =~ m/.+?\:\s*(.*)\s*.*/;
my $AUTHORFULLNAME = 'Kranti Konganti';

# Declare initial global variables
my ($quiet, $help, $coords2, $final_gtf, $infernal_tbl);

my $is_valid_option = GetOptions ('help|?'            => \$help,
                                  'quiet'             => \$quiet,
				  'tbl-infernal=s'    => \$infernal_tbl,
				  'final-gtf=s'       => \$final_gtf
                                  );

# Print info if not quiet
my $io = IO::Routine->new($help, $quiet);

$io->this_script_info($io->file_basename($0),
                      $VERSION,
                      $AUTHORFULLNAME,
                      $LASTCHANGEDBY,
                      $LASTCHANGEDDATE, '',
		      $quiet);
		      
# Check for the validity of options
$io->verify_options([$is_valid_option,
		     $infernal_tbl, $final_gtf]);

$io->c_time('Verifying file [ ' .
	    $io->file_basename($infernal_tbl, 'suffix') .
	    ' ]...');

$io->verify_files([$infernal_tbl, $final_gtf],
		  ['INFERNAL-TBL', 'FINAL-GTF']);

my $gtf_fh = $io->open_file('<', $final_gtf);
my $inf_fh = $io->open_file('<', $infernal_tbl);

$coords2 = {};

while (my $line = <$gtf_fh>) {
    chomp $line;
    next if ($line =~ m/^#/ || $line =~ m/\ttranscript\t/);
    my @gtf_fields = split(/\t/, $line);
    (my $tr_id) = ($gtf_fields[8] =~ m/transcript_id\s+\"(.+?)\"/);

    if (!exists  $coords2->{$tr_id}->{$gtf_fields[3]}) {
	$coords2->{$tr_id}->{$gtf_fields[3]} = $gtf_fields[4] if ($line =~ m/\texon\t/);
    } else {
	$io->error("Found a duplicate coordinate for transcript id: $tr_id");
    }
}

close $gtf_fh;

my $inf_ann_id = 0;

while (my $line = <$inf_fh>) {
    chomp $line; 
    next if ($line =~ m/^#/);
    $inf_ann_id++;

    my ($gene_name, $gene_id, $query, $q_acc, $mdl, $mdl_from, $mdl_to, $seq_from, $seq_to, $strand, $trunc, $pass, $gc, $bias, $score, $e_value, $inc, @desc) = split(/\s+/, $line);

    my $descr = join(' ', @desc);
    my $equery = $query;

    $equery =~ s/\./\\\./g;

    my $contig_id = `grep -P "\\ttranscript\\t.+?\\"$equery\\".+" $final_gtf | awk '{print \$1}'`;
    chomp $contig_id;

    my $signi = "no";

    if ($inc eq '!') {
	$signi="yes";
    }

    my $first_ex_start = (sort {$a <=> $b} keys %{$coords2->{$query}})[0];
    my $match_coords = {};
    my $match_coords2 = {};

    # For each transcript these are the coordinates. Store only once.
    if (!exists $match_coords->{$query}) {
	
	# Transcribed mRNA.
	my $ex_len = 1;

	foreach my $coord ( sort {$a <=> $b} keys %{$coords2->{$query}} ) {
	    # Debug only  
	    #print $coords2->{$query}->{$coord} . "-" . $first_ex_start . "+ 1 - " . $coord . "-" . $first_ex_start . "+ 1 + 1\n";
	    
	    # First base
	    #if (($coord - $first_ex_start) == 0) {
	    
	    $match_coords->{$query}->{$ex_len} = $coord;
	    $match_coords2->{$query}->{$ex_len} = $coords2->{$query}->{$coord};
	    #}
	    
	    #if (($coord - $first_ex_start) != 0) {
		#$match_coords->{$query}->{$ex_len} = $coord;
		#$match_coords2->{$query}->{$ex_len} = $coords2->{$query}->{$coord};
	    #}
	    
	    $ex_len += ($coords2->{$query}->{$coord} - $first_ex_start + 1) - ($coord - $first_ex_start + 1) + 1;
	 }
     }

    # Debug only  
    #$Data::Dumper::Sortkeys=1;
    
    if (exists $match_coords->{$query}) {
	
	foreach my $ex_start ( sort {$b <=> $a} keys %{$match_coords->{$query}} ) {
	    
	    if ($ex_start <= $seq_from) {
		my $chr_ex_start = $match_coords->{$query}->{$ex_start};
		my $inf_hit_start = my $inf_hit_end = 0;
		
		# Debug only
		#print "$ex_start, $seq_from, $chr_ex_start, $query.$inf_ann_id\n";
		
		if ($strand eq "+") {
		    $inf_hit_start = $chr_ex_start + ($seq_from - $ex_start) + 1;
		    $inf_hit_end = $chr_ex_start + ($seq_to - $ex_start) + 1;
		}
		elsif ($strand eq "-") {
		    $inf_hit_start = $chr_ex_start + ($seq_to - $ex_start) + 1;
		    $inf_hit_end = $chr_ex_start + ($seq_from - $ex_start) + 1;
		}
		
		# Debug only. Need to handle hits spanning junctions.
		#print "$inf_hit_end, $match_coords->{$query}->{$ex_start} - $match_coords2->{$query}->{$ex_start}\n";
		
		if ($inf_hit_end <= $match_coords2->{$query}->{$ex_start}) {	 
		
		    print STDOUT "$contig_id\tlncRNApipe-Infernal\texon\t$inf_hit_start\t$inf_hit_end\t$score\t$strand\t.\tgene_id \"$query\"; transcript_id \"$query.$inf_ann_id\"; Rfam_match_gene_id \"$gene_id\"; Rfam_match_gene_name \"$gene_name\"; exon_number \"1\" e_value \"$e_value\"; significant_match \"$signi\"; description \"$descr\";\n" if ($inf_hit_start && $inf_hit_end);
		    last;
		}
	    }
	}
    }
}

__END__

=head1 NAME

gen_infernalHits_gtf.pl

=head1 SYNOPSIS

This script will print to STDOUT all the infernal hits in genome coordinate space.

Examples:

    perl gen_infernalHits_gtf.pl -h

    perl gen_infernalHits_gtf.pl -q --tbl infernalHits.txt -final lncRNApipe.final.gtf

=head1 DESCRIPTION

When non coding potential need to be estimated with CPC or to search for any possible ncRNA
signatures using Infernal, introns need to be spliced out. This creates a problem later 
when trying to generate infernal hits GTF file in genome coordinate space. This script will
use exon start coordinates in genome space as indices and tries to generate Infernal hits
in genome coordinate space using match positions from the table file generated by Infernal.
All of the required input files to this script are automatically generated by C<< lncRNApipe >>
if << -inf >> option is used. The output is printed to STDOUT.

=head1 OPTIONS

gen_infernalHits_gtf.pl takes the following arguments:

=over 4

=item -h or --help (Optional)

  Displays this helpful message.

=item -q or --quiet (Optional)

  Providing this option suppresses the log messages to the shell.
  Default: disabled

=item -tbl or --tbl-infernal (Required)

  Infernal hits in space-delimited format as generated by C<< cmscan >> command.

=item -final or --final-gtf (Required)

  A list of putative lncRNAs in GTF format with proper transcript-exon structure
  as generated by C<< lncRNApipe >> pipeline.
  
=back

=head1 AUTHOR

Kranti Konganti, E<lt>konganti@tamu.eduE<gt>.

=head1 COPYRIGHT

This program is distributed under the Artistic License.

=head1 DATE

Sept-29-2017

=cut
