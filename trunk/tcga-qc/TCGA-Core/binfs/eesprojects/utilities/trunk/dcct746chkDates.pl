#! /usr/bin/perl -w
####################################################################################################
our	$pgm_name		= "dcct746chkDates.pl";
our	$VERSION		= "v1.0.2 (dev)";
our	$start_date		= "Tue Aug 23 19:35:57 EDT 2011";
our	$rel_date		= "";
####################################################################################################
#	Eric E. Snyder (c) 2011
#	SRA International, Inc.
#	2115 East Jefferson St.
#	Rockville, MD 20852-4902
#	USA
####################################################################################################
=head1 NAME

dcct746chkDates.pl

=head1 SYNOPSIS

dcct746chkDates.pl file_list

=head1 USAGE

I<dcct746chkDates.pl> reads a list of .xsd files and parses them looking for (day|month|year)
elements with inconsistent suffixes.  The program which obscures dates to a HIPPA-compliant
form requires that the date elements have a common ending.  The elements are re-named with a
"days_since" (or something like that) suffix.  In the words of the ticket:

<xs:sequence>
<xs:element ref="day_of_performance_status_follow_up_score" />
<xs:element ref="month_of_performance_status_follow_up_score_event" />
<xs:element ref="year_of_performance_status_follow_up_score" />
</xs:sequence>
will not get properly obscured since day_of_ and month_of_ do not share the same ending
( performance_status_follow_up_score != performance_status_follow_up_score_event).

Each line of the XSD file is grepped with the following regex:

	/xs:element name="(day|month|year)_of_(\w+)"/

The variable $1 corresponds to the epoch (day, month or year), while $2 is the tag used for tabulation.
For an individual file, if each tag gets 3 hits, the situation is considered normal.  If a tag
gets a single hit and the epoch is "year", that is also considered normal.  If, however, there are a
pair of tags with a total of 3 hits and one tag is a substring of another, that is indicative of the
situation where element suffixes are inconsistent.  The tags and their corresponding epochs are
written to STDOUT for manual review.

=cut
####################################################################################################
#	Testbed:	/home/eesnyder/projects/nih/XSD/tickets/DCCT-746/tumor
#	Cmdline:	dcct746chkDates.pl ../xsdDateList
####################################################################################################
#	History:
#	v1.0.0:		Write majority of code
#	v1.0.1:		Add comments and cmd-line options to allow more control over output (stringency, etc.)
#	v1.0.2:
####################################################################################################
use strict;
use warnings;
use MyUsage;
use EESnyder;

my @t0 = ( time, (times)[0] );									# start execution timer
my %opts	= ();												# init cmdline arg hash

my %usage 	= (													# init paras for getopts
	'B' => {
		'type'     => "boolean",
		'usage'    => "print program banner to STDOUT",
		'required' => 0,
		'init'     => 1,
	},
	'D' => {
		'type'     => "boolean",
		'usage'    => "print copious debugging information",
		'required' => 0,
		'init'     => 0,
	},
	'V' => {
		'type'     => "boolean",
		'usage'    => "print version information",
		'required' => 0,
		'init'     => 0,
	},
	'd' => {
		'type'     => "boolean",
		'usage'    => "print debugging information",
		'required' => 0,
		'init'     => 0,
	},
	'h' => {
		'type'     => "boolean",
		'usage'    => "print \"help\" information",
		'required' => 0,
		'init'     => 0,
	},
	'v' => {
		'type'     => "boolean",
		'usage'    => "verbose execution information",
		'required' => 0,
		'init'     => 0,
	},
);

my @infiles = qw( XSDfileNameList );
my $banner = &Usage( \%usage, \%opts, \@infiles );	# read cmdline parameters
print $banner unless $opts{'B'};    				# print program banner w/parameters to STDOUT
my $verbose = 0;
$verbose = 1 if $opts{'v'};							# set verbose flag (print all filenames examined)

print $pgm_name ."_$VERSION\n" .
	"Start date:	$start_date\n" .
	"End date:	$rel_date\n\n" if $opts{'V'};

####################################################################################################
################################## Put Main Between Here ... #######################################
#	read and process list of files to be examined, typically generated by a command such as:
#		find . -name '*.xsd' -exec egrep 'element name="(day|month|year)_of_' {} ';' -fprintf xsdDateList "%h/%f\n"
#	results in @files, comtaining array of filenames with relative paths

my $fileList = shift @ARGV;
open( FILE, $fileList ) or die "Cannot open file: \"$fileList\" for reading.\n";
my @files = ();
while( <FILE> ){
	chomp;
	next if /^\s*$/;
	next if /^#/;
	push( @files, $_ );
}
close( FILE );

my %tag_count = ();					# HoH keyed on filename and date element suffix (without "day_of_" prefix, etc.)
my $max_tag_length = 0;				# tag length for output formatting purposes
foreach my $file ( @files ){
	open( FILE, "$file" ) or die "Cannot open XSD file: \"$file\" for reading.\n";
	while ( <FILE> ){
		chomp;
		next if /^\s*$/;
		next if /^#/;
		my $tag = "";												# element name without "(day|month|year)_of_" prefix
		my $epoch = "";												# day, month or year
		if ( m/xs:element name="(day|month|year)_of_(\w+)"/ ){		# parse element name into epoch and suffix ("_of_" is lost)
			$epoch	 = $1;
			$tag	 = $2;
			if ( exists $tag_count{ $file }{ $tag } ){
				push ( @{$tag_count{ $file }{ $tag }}, $epoch );
			} else {
				@{$tag_count{ $file }{ $tag }} = ( $epoch );
			}
		}
		my $tag_length = length( $tag );							# measure tag length
		if ( $tag_length > $max_tag_length ){
			$max_tag_length = $tag_length;							# watch for maximum
		}
	}
	close( FILE );
}

my %tag_alert = ();											# is tag unusual?
my %file_alert = ();										# does file contain unusual tags?
foreach my $file ( @files ){								# loop over files
	$file_alert{ $file } = 0;								# set files as uninteresting by default
	foreach my $tag ( keys %{$tag_count{ $file }} ){		# loop over tags in given file
		if ( @{$tag_count{ $file }{ $tag }} != 3 ){			# if there is NOT a tag for each epoch
			$tag_alert{ $file }{ $tag } = "alert";			# set tag "alert"
			$file_alert{ $file }++;							# increment counter of unusual tags for each file
		} else {											# if there IS a tag for each epoch
			$tag_alert{ $file }{ $tag } = undef;			# set alert to undefined
		}
	}
	print "$file\n" if $verbose;							# print the file name (in every case)
	if ( $file_alert{ $file } ){							# if file alert status is TRUE
		print "$file\n" unless $verbose;					# print the file name (only in case of alert)
		foreach my $tag ( keys %{$tag_count{ $file }} ){	# foreach tag
			if ( $tag_alert{ $file }{ $tag } ){				# if tag alert is TRUE...
				printf("%+$max_tag_length" . "s %d\t\"%s\"\n",
					$tag,												# print the tag name
					scalar @{$tag_count{ $file }{$tag}},				# the number of associated epochs
					join("\", \"", @{$tag_count{ $file }{ $tag }} ) );	# the list of epochs for that tag
			}
		}
	}
}
##################################      ... and Here         ########################################
####################################################################################################

print "\nDone at ", time-$t0[0], " sec, ", (times)[0]-$t0[1], " cpu\n" ;

####################################################################################################
######################################## Subroutines ###############################################
####################################################################################################

####################################################################################################
#### end of template ###############################################################################
####################################################################################################