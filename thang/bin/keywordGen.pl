#!/usr/bin/perl -wT
# Author: Luong Minh Thang <luongmin@comp.nus.edu.sg>, generated at Tue, 02 Jun 2009 01:30:42

# Modified from template by Min-Yen Kan <kanmy@comp.nus.edu.sg>

require 5.0;
use strict;

# I do not know a better solution to find a lib path in -T mode.
# So if you know a better solution, I'd be glad to hear.
# See this http://www.perlmonks.org/?node_id=585299 for why I used the below code
use FindBin;
my $path;
BEGIN {
  if ($FindBin::Bin =~ /(.*)/) {
        $path = $1;
      }
}
use lib "$path/../../lib";

use Getopt::Long;
use SectLabel::Config;

### USER customizable section
$0 =~ /([^\/]+)$/; my $progname = $1;
my $outputVersion = "1.0";
### END user customizable section

sub License {
  print STDERR "# Copyright 2009 \251 by Luong Minh Thang\n";
}

### HELP Sub-procedure
sub Help {
  print STDERR "Create keyword info from a tagged header file\n";
  print STDERR "usage: $progname -h\t[invokes help]\n";
  print STDERR "       $progname -in taggedFile -out outFile [-n topN -nGram numNGram -no-lowercase]\n";
  print STDERR "Options:\n";
  print STDERR "\t-q\tQuiet Mode (don't echo license)\n";
  print STDERR "\t-n: Default topN = 100.\n";
  print STDERR "\t-nGram: Default numNGram = 1.\n";
  print STDERR "\t-no-lowercase: lowercase by default.\n";
}
my $QUIET = 0;
my $HELP = 0;
my $outFile = undef;
my $inFile = undef;
my $topN = 100;
my $numNGram = 1;
my $isLowercase = 1;
$HELP = 1 unless GetOptions('in=s' => \$inFile,
			    'out=s' => \$outFile,
			    'n=i' => \$topN,
			    'nGram=i' => \$numNGram,
			    'lowercase!' => \$isLowercase,
			    'h' => \$HELP,
			    'q' => \$QUIET);

if ($HELP || !defined $inFile || !defined $outFile) {
  Help();
  exit(0);
}

if (!$QUIET) {
  License();
}

### Untaint ###
$inFile = untaintPath($inFile);
$outFile = untaintPath($outFile);
$ENV{'PATH'} = '/bin:/usr/bin:/usr/local/bin';
### End untaint ###

my $funcFile = $SectLabel::Config::funcFile;
$funcFile = "$FindBin::Bin/../$funcFile";
my %funcWord = ();
loadListHash($funcFile, \%funcWord);

# keyword statistics
my %keywords = (); #hash of hash $keywords{"affiliation"}->{"Institute"} = freq of "Institute" for affiliation tag

my $allTags = $SectLabel::Config::tags;

processFile($inFile, $outFile, $numNGram);

## 
# main routine to count frequent keywords/bigrams in $inFile and output to $outFile
##
sub processFile {
  my ($inFile, $outFile, $numNGram) = @_;
  
  if (!(-e $inFile)) { die "# $progname crash\t\tFile \"$inFile\" doesn't exist"; }
  open (IF, "<:utf8", $inFile) || die "# $progname crash\t\tCan't open \"$inFile\"";
  
  while (<IF>) { #each line contains a header
    if (/^\#/) { next; }			# skip comments
    elsif (/^\s+$/) { next; }		# skip blank lines
    elsif(/^(.+) \|\|\| (.+)$/) {
      my $tag = $1;
#      if(!defined $allTags->{$tag} || !$allTags->{$tag}){
#	next;
#      }

      my $line = $2;
      countKeywords($line, $tag, $numNGram);
    }
  } # end while IF
  close IF;

  ## obtain top keyWords
  my %topKeywords = ();
  foreach my $tag (keys %keywords){
    $topKeywords{$tag} = ();

    my %freqs = %{$keywords{$tag}};
    my @sorted_keys = sort { $freqs{$b} <=> $freqs{$a} } keys %freqs;
    
    my $count = 0;    
    foreach my $keyWord (@sorted_keys){
      $topKeywords{$tag}->{$keyWord} = $freqs{$keyWord};

      $count++;
      if($count == $topN){
	last;
      }      
    }
  }

  ## filter duplcate keywords
  my %filteredKeywords = ();
  filterDuplicate(\%topKeywords, \%filteredKeywords);

  ## output results
  outputKeywords(\%filteredKeywords, $outFile);
}

##
# Output keyword hash to file
##
sub outputKeywords {
  my ($hash, $outFile) = @_;

  open(OF, ">:utf8", "$outFile") || die"#Can't open file \"$outFile\"\n";

  ### checkTags
  foreach my $tag (keys %{$hash}){
    if(!defined $allTags->{$tag}){
      print STDERR "# Warning tag $tag is not defined\n";
    }
  }

  my @sorted_tags = sort {$a cmp $b} keys %{$allTags};
  foreach my $tag (@sorted_tags){
    if($allTags->{$tag} == 0) { next; }

    print OF "$tag:";

    my @keywords = sort{$a cmp $b} keys %{$hash->{$tag}};    
    foreach my $keyword (@keywords){
      print OF " $keyword";
    }

    print OF "\n";
  }
  close OF;
}

##
# Remove keywords that appear in more than one field
##
sub filterDuplicate {
  my ($hash, $filteredHash) = @_;

  my @tags = keys %{$hash};
  foreach my $tag (@tags){
    if(!defined $allTags->{$tag} || $allTags->{$tag} == 0){ #
      next;
    }

    $filteredHash->{$tag} = ();
    my @keywords = keys %{$hash->{$tag}};
    
    foreach my $keyword (@keywords){
      my $isDuplicated = 0;

      # check for duplication
      foreach(@tags){
	if($_ ne $tag && defined $allTags->{$_} && $allTags->{$_} == 1){ # a different tag
	  if(defined $hash->{$_}->{$keyword}) {# && $hash->{$_}->{$keyword} > $hash->{$tag}->{$keyword}){ # duplicated
#	    print STDERR "Duplicate \"$keyword\" $hash->{$tag}->{$keyword} $hash->{$_}->{$keyword}:\t$tag vs $_\n";
	    $isDuplicated = 1;
	    last;
	  }
	}
      } # end for @tags

      if(!$isDuplicated){
	$filteredHash->{$tag}->{$keyword} = 1;
      }
    }
  }
}

##
# Count keyword or nGrams
##
sub countKeywords {
  my ($line, $tag, $numNGram) = @_;

#  if($isLowercase){
#    $line = lc($line);
#  }

  my @tmpTokens = split(/\s+/, $line);

  #filter out tokens
  my @tokens = ();
  foreach my $token (@tmpTokens){ 
    if($token ne ""){
      $token =~ s/^\s+//g; # strip off leading spaces
      $token =~ s/\s+$//g; # strip off trailing spaces
      $token =~ s/^\p{P}+//g; #strip out leading punctuations
      $token =~ s/\p{P}+$//g; #strip out trailing punctuations
      $token =~ s/\d/0/g; #canocalize number into "0"

      if($token =~ /(\w.*)@(.*\..*)/){ #email pattern, try to normalize
	#	 $token =~ /(http:\/\/|www\.)/){
	$token = $1;
	my $remain = $2;
	$token =~ s/\w+/x/g;
	$token =~ s/\d+/0/g;
	$token .= "@".$remain;
      } 

      push(@tokens, $token);
    }
  }

  my $count = 0;  
  for(my $i=0; $i<=$#tokens; $i++){
    if(($#tokens-$i + 1) < $numNGram) { last; }; # not enough ngrams
    my $nGram = "";
    for(my $j=$i; $j <= ($i+$numNGram-1); $j++){
      my $token = $tokens[$j];

      if($j < ($i+$numNGram-1)){
	$nGram .= "$token-";
      } else {
	$nGram .= "$token";
      }
    }

    if($nGram =~ /^\s*$/){ next; } #skip those with white spaces
    if($nGram =~ /^\d*$/){ next; } #skip those with only digits
    if($funcWord{$nGram}){ next; } #skip function words, matter for nGram = 1
#    print STDERR "$count\t$nGram\n";
    if(!$keywords{$tag}->{$nGram}){
      $keywords{$tag}->{$nGram} = 0;
    }

    $keywords{$tag}->{$nGram}++;

    $count++;
    if($count == 4){
      last;
    }
  } # end while true
}

sub loadListHash {
  my ($inFile, $hash) = @_;

  open(IF, "<:utf8", $inFile) || die "#Can't open file \"$inFile\"";

  while(<IF>){
    chomp;

    $hash->{$_} = 1;
  }

  close IF;
}

sub untaintPath {
  my ($path) = @_;

  if ( $path =~ /^([-_\/\w\.]+)$/ ) {
    $path = $1;
  } else {
    die "Bad path $path\n";
  }

  return $path;
}

sub untaint {
  my ($s) = @_;
  if ($s =~ /^([\w \-\@\(\),\.\/]+)$/) {
    $s = $1;               # $data now untainted
  } else {
    die "Bad data in $s";  # log this somewhere
  }
  return $s;
}

sub execute {
  my ($cmd) = @_;
  print STDERR "Executing: $cmd\n";
  $cmd = untaint($cmd);
  system($cmd);
}

sub newTmpFile {
  my $tmpFile = `date '+%Y%m%d-%H%M%S-$$'`;
  chomp($tmpFile);
  return $tmpFile;
}