#perl! -w

if(@ARGV<4){

    print "perl run_samtools_to_hmm_v3.pl id_list genome1 genome2 read_length\n"; exit;

}#usage

my $infile1=shift(@ARGV); chomp $infile1;
open IN, $infile1 or die "cannot open sim id list\n";

my $genome1=shift(@ARGV); chomp $genome1;

my $genome2=shift(@ARGV); chomp $genome2;

my $read_length=shift(@ARGV); chomp $read_length;

open OUT, ">$infile1"."_bamlist";
my $outfile="$infile1"."_bamlist";

my $aims_list="current_aims_file"; chomp $aims_list;
open AIMSLIST, $aims_list or die "cannot open AIMs list\n";

my $aims=<AIMSLIST>; chomp $aims;
print "using AIMs in file $aims\n";

my @parfilelist=();
my @indivfilelist=();
while (my $id = <IN>){

    chomp $id;
    my $line1="$id".".par1.sam";
    my $line2="$id".".par2.sam";

    my $bam1="$line1".".bam";

    print "$bam1\n";

    system("samtools fixmate -O bam $line1 $bam1");
    
    $sorted1="$bam1".".sorted";
    $sorted1=~ s/\.bam//g;

    $sorted1="$sorted1".".bam";
    
    print "$sorted1\n";

    system("samtools sort $bam1 -o $sorted1");

    system("samtools index $sorted1");

    my $dedup1="sorted1".".deup";
    my $metrics1="$line1".".metrics";
#!    system("java -jar ./../bin/picard-tools-1.118/MarkDuplicates.jar INPUT=$sorted1 OUTPUT=$dedup1 METRICS_FILE=$metrics1");

    my $unique1 = "$sorted1".".unique.bam";
    $unique1 =~ s/sorted.bam.unique/sorted.unique/g;

    system("samtools view -b -q 30 $sorted1 > $unique1"); # this is for mapped reads with poor mapping quality

    print OUT "$unique1\n";

###now parent2

    my $bam2="$line2".".bam";

    print "$bam2\n";

    system("samtools fixmate -O bam $line2 $bam2");

    $sorted2="$bam2".".sorted";
    $sorted2=~ s/\.bam//g;

    $sorted2="$sorted2".".bam";

    print "$sorted2\n";

    system("samtools sort $bam2 -o $sorted2");

    system("samtools index $sorted2");

    my $dedup2="sorted2".".deup";
    my $metrics2="$line2".".metrics";
#!    system("java -jar ./../bin/picard-tools-1.118/MarkDuplicates.jar INPUT=$sorted2 OUTPUT=$dedup2 METRICS_FILE=$metrics2");

    my $unique2 = "$sorted2".".unique.bam";
    $unique2 =~ s/sorted.bam.unique/sorted.unique/g;

    system("samtools view -b -q 30 $sorted2 > $unique2"); # this is for mapped reads with poor mapping quality                  

    print OUT "$unique2\n";

#####JOINT FILTERING
    my $par1_pass="$unique1"."_par1_passlist";
    my $par2_pass="$unique2"."_par2_passlist";

    $par1_pass=~ s/_read_1.fastq.gz.par1.sam.sorted.unique.bam//g;
    $par2_pass=~ s/_read_1.fastq.gz.par2.sam.sorted.unique.bam//g;

    system("samtools view -F 4 $unique1 | cut -f 1 > $par1_pass");
    system("samtools view -F 4 $unique2 | cut -f 1 > $par2_pass");

    my $pass_both="$par1_pass"."_both";
    $pass_both =~ s/_par1//g;

    ###intersect
    my $file1 = $par1_pass;
    my $file2 = $par2_pass;
    open F2, $file2 or die $!;
    open JOINT, ">$pass_both";
    while (<F2>) { $h2{$_}++ };
    open F1, $file1 or die;
    $total=$.; $printed=0;
    while (<F1>) { $total++; if ($h2{$_}) { print JOINT $_; $h2{$_} = ""; $printed++; } }

    ###filter
    my $finalbam1="$unique1";
    $finalbam1=~ s/sorted.unique/sorted.pass.unique/g;
    
    my $finalbam2="$unique2";
    $finalbam2=~s/sorted.unique/sorted.pass.unique/g;

    system("bamutils filter $unique1 $finalbam1 -whitelist $pass_both");
    system("bamutils filter $unique2 $finalbam2 -whitelist $pass_both");


#####VARIANT CALLING
    my $mpileup1 = "$unique1".".bcf";
    if(! -f $mpileup1){
    system("samtools mpileup -go $mpileup1 -f $genome1 $finalbam1");
    } else{
	print "$mpileup1 exists, not overwriting\n";
    }#only write if does not exist 

    my $vcf1 = "$unique1".".vcf.gz";

    system("bcftools call -vmO z -o $vcf1 $mpileup1");

    system("gunzip $vcf1");

    $vcf1 = "$unique1".".vcf";

    system("perl vcf_to_counts.pl $vcf1");

    my $mpileup2 = "$unique2".".bcf";

    if(! -f $mpileup2){
    system("samtools mpileup -go $mpileup2 -f $genome2 $finalbam2");
    } else{
	print "$mpileup2 exists, not overwriting\n";
    }#only write if does not exist

    my $vcf2 = "$unique2".".vcf.gz";

    system("bcftools call -vmO z -o $vcf2 $mpileup2");

    system("gunzip $vcf2");

    $vcf2 = "$unique2".".vcf";

    system("perl vcf_to_counts.pl $vcf2");

    my $counts1="$vcf1"."_counts";
    my $counts2="$vcf2"."_counts";

    my $hmmsites1="$counts1".".hmm";
    my $hmmsites2="$counts2".".hmm";

    if((! -f $hmmsites1) or (! -f $hmmsites2)){
    system("perl overlap_AIMs_and_counts_v5.pl $aims $counts1");
    system("perl overlap_AIMs_and_counts_v5.pl $aims $counts2");
    } else{
	print "$hmmsites1 and $hmmsites2 files exist, not overwriting\n";
    }

    my $hmm="$line1".".hmm.combined";
    $hmm =~ s/par1\.//g;

##snippet from FAS scriptome
    system("perl combine_FAS_scriptome_snippet.pl $hmmsites1 $hmmsites2 $hmm");
   
    system("perl collapse_parental_counts_1SNPfilter_v2.pl $hmm $read_length");

    my $parfilecurr="$hmm"."parental.format";
    my $indivfilecurr="$hmm".".pass.formatted";
    push(@parfilelist, $parfilecurr);
    push(@indivfilelist,$indivfilecurr);

}

open LISTPAR, ">HMM.parental.files.list."."$infile1";
open LISTHYB, ">HMM.hybrid.files.list"."$infile1";

for my $j (0..scalar(@parfilelist)-1){

    print LISTPAR "$parfilelist[$j]\n";

}#parent file list

for my $l (0..scalar(@indivfilelist)-1){

    print LISTHYB "$indivfilelist[$l]\n";

}#parent file list 


