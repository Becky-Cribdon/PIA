#!/usr/bin/perl

######################################################
##################### PIA_inner.pl ###################
######################################################
#########  Phylogenetic Intersection Analysis ########
############## Robin Allaby, UoW 2013 ################
######################################################
############## Version 4.9, 2019-09-12 ###############
######################################################

# Edited by Roselyn Ware, UoW 2015
# A method of metagenomic phylogenetic assignation, designed to be robust to partial representation of organisms in the database		
		
# Further edited by Becky Cribdon, UoW 2019.
# - Added a log.
# - Made variable names more consistent and meaningful.
# - Removed $blastfile2 and functions that were not fully implemented.
# - Uses pre-made DBM index files for nodes.dmp and names.dmp
# - Only one BLAST hit is looked at per hit score. But instead of just taking the first one, it now takes an intersection of all hits with that hit score, and the taxonomic diversity of all of those hits still counts towards the diversity score. Note that if $cap was already being reached, $cap will now be reached earlier (with closer BLAST hits).
# - Intersections are taken wherever possible. No stopping at class.
# - Takes BLAST input not in standard format, but as "-outfmt 6 std staxid".

# Please report any problems to r.cribdon@warwick.ac.uk.

# This usually runs inside PIA.pl. To run independently, PIA.pl must already have made a header file containing the name and length of every sequence in the FASTA. 
# Then run PIA_inner.pl giving the header file as -f and a BLAST file as -b.
# > perl PIA_inner.pl -f [header file] -b [BLAST file]



	use strict;
	use warnings;
	use Getopt::Std;
    use DB_File;
    use Fcntl;
	use Data::Dumper qw(Dumper); # Only used for testing
    

######################################################										#####################
########### Check arguments and Input Data ###########										###### Modules ######
######################################################										#####################

##### Get arguments from command line #####
	my %options=();
	getopts('hf:b:c:C:m:s:', \%options); 														#Getopt::Std
    
	# If other text found on command line, do:
	print "Other things found on the command line:\n" if $ARGV[0];
	foreach (@ARGV)	{
        print "$_\n";
	}			

##### Display help file and exit if -h flag called #####
	my $helpfile="Helpfile_PIA.txt";
	if ($options{h}){
        print "Usage: perl PIA.pl -f <file> -b <blast.txt> [options]

Main Arguments
	Option	Description			Input		Explanation
	-f	FASTA or header filename	Y		FASTA of reads to PIA. Sequence names must be short enough for BLAST to not crop them.
	-b	BLAST filename			Y		BLAST filename containing entries for all reads in the FASTA (can contain other entries too).


Optional
	Option	Description			Input		Explanation
 	-c 	cap				Optional	Maximum unique BLAST taxa examined. Impacts taxonomic diversity score. Default is 100.
	-C	min % coverage			Optional	Minimum percentage coverage a top BLAST hit must have for a read to be taken forward. Default is 95.
	-h	help				N		Print this help text.
	-s	min tax diversity score		Optional	Minimum taxonomic diversity score for a read to make it to Summary_Basic.txt. Depends on cap. Default is 0.1.
	-t	threads				Optional	PIA.pl only. Split the header file into x subfiles and run PIA_inner.pl on each one. Default is 2.
";
        exit;
	}

##### Check header filename and open file #####
	# The header file is the read names (headers) extracted from a FASTA file. PIA.pl makes the header file.
	my $header_filename = ($options{f});
	
##### Check BLAST filename and open file #####
 	my $blast_filename = ($options{b});

##### See if cap input #####
	# BLAST hits are all assigned to taxa. $cap is the maximum number of taxa to be looked at. If $cap is hit, no more BLAST hits will be considered. $cap is used to calculate the taxonomic diversity score, so affects the minimum score threshold (option s). Default is 100.	
	my $cap_opt = ($options{c});
	my $cap = 100;
	if ($cap_opt) { $cap = $cap_opt;} # If there is an option, overwrite the default.

##### See if min % coverage input #####
	# The minimum percentage coverage a top BLAST hit must have for a read to be taken forward. Default is 95.
	my $min_coverage_perc_opt = ($options{C});
	my $min_coverage_perc = 95;
	if ($min_coverage_perc_opt) { $min_coverage_perc = $min_coverage_perc_opt;} # If there is an option, overwrite the default.
    
##### See if min taxonomic diversity score input #####
	# The minimum taxonomic diversity score a read must have to make it to Summary_Basic.txt. Depends on $cap. Defaults to 0.1.
	my $min_taxdiv_score_opt = ($options{s});
	my $min_taxdiv_score = 0.1;
	if ($min_taxdiv_score_opt) { $min_taxdiv_score = $min_taxdiv_score_opt;} # If there is an option, overwrite the default.


######################################
########### Start log file ###########
######################################

    my $log_filename = $header_filename . '_PIA_inner_log.txt';
    open( my $log_filehandle, '>', $log_filename) or die "Cannot open $log_filename for writing: $!\n"; # This will overwrite old logs.
    use IO::Handle; # Enable autoflush.
    $log_filehandle -> autoflush(1); # Set autoflush to 1 for the log filehandle. This means that Perl won't buffer its output to the log, so the log will be updated in real time.
    
    # Print run parameters to log.
    print $log_filehandle "#####################################\nOther things found on the command line:\n" if $ARGV[0];
    foreach (@ARGV)	{
        print $log_filehandle "$_\n";
    }    
    print $log_filehandle "\n****$header_filename****\n\n";


######################################################
######### Make copies of the DBM index files #########
######################################################
    my $nodesfileDBM = 'Reference_files/nodes.dmp.dbm' . "_$header_filename";
    system ("cp Reference_files/nodes.dmp.dbm $nodesfileDBM");
    my %nodesfileDBM = ();

    my $namesfileDBM = 'Reference_files/names.dmp.dbm' . "_$header_filename";
    system ("cp Reference_files/names.dmp.dbm $namesfileDBM");
    my %namesfileDBM = ();


######################################################
###################### Run PIA #######################
######################################################
	
	my $corename = PIA($header_filename, $blast_filename, $cap, $min_coverage_perc); # PIA() returns a base name for this sample file. The base name is [header file]_out.
	#print "\nPIA() subroutine finished.\n\n";
    #print $log_filehandle "\nPIA() subroutine finished.\n\n";
    
	#my $corename = '50.header_out'; # IF NOT ACTUALLY RUNNING THE PIA; FOR TESTING


######################################################	
################## Summarise Data ####################
######################################################

##### Extract simple summary from the intersects file
	my $intersects_filename = "$corename"."/"."$corename.intersects.txt";
	my $summary_basic_filename = simple_summary($intersects_filename, $min_taxdiv_score);


######################################################
##################### Tidy Up ########################
######################################################

##### Remove un-necessary files	
	unlink("$corename"."/"."temp_blast_entry.txt");
	unlink("$corename"."/"."TEMP");
	unlink("$corename"."/"."hittempfile");
    unlink $namesfileDBM;
    unlink $nodesfileDBM;

# Finish the log and move it into the output directory.
    print "\nThis run of PIA_inner.pl is finished.\n\n";
    print $log_filehandle "\n****This run of PIA_inner.pl is finished.****\n\n\n\n";
    close $log_filehandle;
    my $log_final_destination = $corename . '/' . $corename . '_PIA_inner_log.txt';
    system("mv $log_filename $log_final_destination");



######################################################	
######################################################
#################### SUBROUTINES #####################
######################################################
######################################################


sub find_taxonomic_intersect {
##### Find intersection of two taxa by comparing their routes down the phlyogenetic tree
	my ($first_route, $second_route) = @_; # Routes are the taxonomic IDs of successive parent taxa.
	my $intersect_ID = 0; # If either the first or second route aren't defined, return the intersect ID 0.
	if (defined $first_route && defined $second_route){
		my @first_route = split (/\t/, $first_route);
		my @second_route = split (/\t/, $second_route);
		my $connected = 0; # The $connected flag activates when the first shared ID is stored as $intersect_ID and prevents it from being overwritten. Because the routes go from lower to higher taxa, higher shared IDs are ignored.
		foreach my $first_ID (@first_route) { # Start with each ID in the first route.
			foreach my $second_ID (@second_route) { # Take the IDs in the second route.
				if ($first_ID == $second_ID) { # If the IDs match,
					unless ($connected == 1) { # And if they're not yet flagged as connected,
						$connected = 1; # Flag them as connected.
						$intersect_ID = $first_ID; # $intersect_ID becomes this shared rank.
					} # If the routes are already flagged as connected, move on to the next ID in the second route. TO DO: stop processing when a connection is found?
				}
			}
		}
	}
	return $intersect_ID;	
}


sub PIA {
##### Run phylogenetic intersection analysis

	# Summary
	#--------
	# Retrieve the header and sequence length for each read.
    #
    # Look at the BLAST file line by line.
    #
    #   If a line is just another hit to the current header,
    #       Skip if we've already seen a hit to this taxon.
    #       Otherwise, list hits by E value.
    #
    #   If a line is the first hit to a new header (the top hit),
    #       First, finish processing the hits from the last header.
    #           Collapse multiple hits with the same E value to their intersection. So, in the end there's just one hit per E value.
    #           If a new "hits" is to an existing taxon, discard all but the hit with the highest E value.
    #           Calculate the taxonomic diversity score. This affects which reads make it to the summary basic.
    #           Find the intersection between the top and second-top hits. This is the taxon the read is assigned to.
    #           Find the intersection between the top and bottom hits. This is just for interest.
    #           Output all information for this header to the intersects file.
    #       Then,
    #           If the new header isn't in our list, skip it.
    #           Check coverage of the top hit. If insufficient, skip the header.
    #           Note the Identities score and E value for the top hit.
    #
	# Return $corename.
    
	my ($header_filename, $blast_filename, $cap, $min_coverage_perc) = @_;
	
	my $corename = $header_filename . "_out"; # # Generate a core name: a base name for naming things linked to this sample. For example, "test_sample.header_out".
	`mkdir $corename`; # Create a separate directory for outputs (makes folder organisation tidier).
    
    
	# Retrieve the header and sequence length for each read
	#------------------------------------------------------
	open (my $header_filehandle, $header_filename) or die "Cannot open $header_filename\n!$\n"; # Extract headers from the header file. A header is the ID number given to a read, like a name, so a header represents a read. "Header" and "read" are used somewhat interchangably in this code, but it never deals directly with a read. It always works via the header.

	my %headers = ();
	
	while (my $header_line = <$header_filehandle>) {
        chomp $header_line;
        my @header_line = split ("\t", $header_line);
        $headers{$header_line[0]} = $header_line[1]; # Element 0 is the actual header: the sequence identifier. Element 1 is the length of the corresponding read.
	}
	close $header_filehandle;
	#print Dumper \%headers; print "\n\n";
    
	my $number_of_headers = scalar(keys %headers);
    print "\n$number_of_headers reads to process.\n\n";
	print $log_filehandle "$number_of_headers reads to process.\n\n";

    
	# Search the BLAST file for entries for reads in @headers
	#--------------------------------------------------------   
    open (my $blast_filehandle, $blast_filename) or die "Cannot open $blast_filename: $!"; # Open the BLAST file.
    
    my $current_header = 'none';
    my $current_header_number = '0'; # Interestingly, the first header will be labelled "1". This is only for humans to read though, so eh.
    my $skip = 0; # 1 for skip, 0 for continue.
    my $tophit_identities; my $tophit_e_value; # Calculated early on and simply exported to the intersects file.
    my %hit_taxa = (); # A list of the unique BLAST taxa. Used to check whether hits are to taxa that have already been seen.
    my %hit_e_values; # A list of the unique E values. Used to check whether hits share E values. E values with multiple hits are "averaged" into one "hit" by taking the intersection of the taxa involved.
    my $number_of_hits; # A count of hits per header.
    
    BLASTLINE: while (1) {  # Run this loop until "last" is called.
        
        if (!keys %headers) { last BLASTLINE; } # If there aren't any headers left to find, stop looking in the BLAST file (note that it does look at one more line before stopping in order to finish off the last header).
        
        my $line = <$blast_filehandle>; # Otherwise, look at every line.
        if (! defined $line) { $line = "swan\tsong"; } # If there is no next line, give $line a stand-in string so we can just finish off the last header.
        my @line = split ("\t", $line);
        
        #======================================================================================================================================================================
        if ($line[0] ne $current_header) { # If this is the top hit for a new header,
            
            
            #------------------------------------------------------------------------------------------------------------------------------------------------------------------
            if (%hit_taxa) { # If there was a previous header, now that we have all of its hits, finish processing them:
                
                # Find the intersection of any hits with the same score
                #------------------------------------------------------
                # For each entry in %hit_e_values, if the value contains more than one ID, find the intersection of those IDs and save it as the new value.
                foreach my $query_e_value (keys %hit_e_values) {
                    my @IDs_per_e_value = split ("\t", $hit_e_values{$query_e_value});
                    my $number_of_IDs = @IDs_per_e_value;
                    if ($number_of_IDs > 1) { # If there is more than one ID under this score,
                        my $zeroth_route = retrieve_taxonomic_structure($IDs_per_e_value[0], $nodesfileDBM);
                        my $first_route = retrieve_taxonomic_structure ($IDs_per_e_value[1], $nodesfileDBM);
                        my $intersection_ID = find_taxonomic_intersect ($zeroth_route, $first_route); # This is the initial intersection.

                        if ($number_of_IDs > 2) { # If there are also additional IDs, find their intersection with the initial one.
                            foreach my $next_ID (@IDs_per_e_value[2 .. $#IDs_per_e_value]) { # This is an array slice. We don't want to process elements 0-1 of @IDs_per_score again.
                                my $intersection_route = retrieve_taxonomic_structure($intersection_ID, $nodesfileDBM);
                                my $next_route = retrieve_taxonomic_structure ($next_ID, $nodesfileDBM);
                                my $intersection_next_temp = find_taxonomic_intersect($intersection_route, $next_route);
                                $intersection_ID = find_taxonomic_intersect($intersection_route, $next_route);  # The next intersection will always be at least as high as the current 
                            } 
                        }
                        
                        $hit_e_values{$query_e_value} = $intersection_ID;
                        
                    } # If there was only one ID, leave it alone.
                }
                
                # %hit_e_values now contains a list of unique E values paired with a single taxonomic ID. Each ID represents either a real BLAST hit or an 'average' for hits with the same score.
                # However, some of the IDs might now be repeated. If IDs are represented more than once, remove all but the hit with the best E value.
                my %hit_e_values_IDcheck = (); # Like %hit_e_values, but where keys are IDs and values are E values, instead of the other way around. Just used for checking.
                foreach my $query_e_value (sort keys %hit_e_values) {
                    my $ID = $hit_e_values{$query_e_value};
                    
                    if (exists $hit_e_values_IDcheck{$ID}) {
                        my $previous_e_value = $hit_e_values_IDcheck{$ID};
                        # We only want one hit per taxon, and that hit should have best E value available (remember that the E values are all unique).
                        if ($previous_e_value < $query_e_value) {
                            delete $hit_e_values{$query_e_value}; # If the previous hit E value is smaller than the current one, it has priority, so delete the current hit from %hit_e_values.
                        } else {
                            delete $hit_e_values{$previous_e_value}; # If the current hit E value is smaller than the previous one, it has priority, so delete the previous hit from %hit_e_values.
                        }
       
                    } else {
                        $hit_e_values_IDcheck{$ID} = $query_e_value; # If we haven't noted this ID yet, do so. Pair it with the current E value.
                    }
                    
                };

                
                # To recreate the list of BLAST hits, sort by E value (ascending; score is descending).  We don't need the E values themselves any more.
                my @hit_taxa_finished = ();
                foreach my $ID (sort {$a <=> $b} keys %hit_e_values) {
                    push (@hit_taxa_finished, $hit_e_values{$ID});
                }
                
                
                # Look up the more information about the finished hits using their IDs
                #---------------------------------------------------------------------
                my @all_hit_info;
                foreach my $finished_hit_ID (@hit_taxa_finished) {
                    my $finished_hit_name = retrieve_name ($finished_hit_ID, $namesfileDBM);
                    my $finished_hit_info = $finished_hit_ID . "\t" . $finished_hit_name;
                    push (@all_hit_info, $finished_hit_info); # Add the [ID\tname] for this finished BLAST hit to the end of @all_hit_info.
                }
                
                my $number_of_finished_blast_hits = @all_hit_info;
                if ($number_of_finished_blast_hits == 0) {
                    print "\t\tNo hits identified for this read. Something might have gone wrong.\n";
                    print $log_filehandle "\t\tNo hits identified for this read. Something might have gone wrong.\n";
                    next BLASTENTRY; # Move on to the next read (for which there is a BLAST entry)
                }


                # Calculate the taxonomic diversity score
                #----------------------------------------
                my $number_of_hit_taxa = keys %hit_taxa; # Note that this is based on the number of taxa in the BLAST hits, not the number of hits after filtering by E value.
                my $tax_diversity_score = ($number_of_hit_taxa/$cap) - (1/$cap); # Remember, $cap defaults to 100.
                
                my $contrastinghit_ID = 0; my $contrastinghit_name = 'none found'; # contrastinghit is second BLAST hit: number 1 if you're counting from 0. Default the values to null.
                if ($number_of_finished_blast_hits > 1) { # If there is more than one finished hit:
                        my @contrastinghit_info = split ("\t", $all_hit_info[1]);
                        $contrastinghit_ID = $contrastinghit_info[0]; # Fetch the contrasting hit ID and name from its info array.
                        $contrastinghit_name = $contrastinghit_info[1]; 
                }
   
                
                # Find the intersection between the top and contrasting hits
                #-----------------------------------------------------------
                # This is the taxon the read will be assigned to.
                my $intersect_ID = 0; my $intersect_name = 'none found'; my $tophit_ID = 0; my $tophit_route = 0; # Default the intersect values to null.
                my @tophit_info = split ("\t", $all_hit_info[0]); # tophit is the top BLAST hit. Unless the top hit wasn't identified, it's also the first BLAST taxon. We ignore unidentified hits.
        
                $tophit_ID = $tophit_info[0];
                
                if ($number_of_finished_blast_hits > 1) { # If there is more than one BLAST hit:
                        unless ($tophit_ID == 0) { # The BLAST taxa might not all be the same, but if the top taxon has ID 0, a proper ID was never found and we can't calculate an intersect.
                            $tophit_route = retrieve_taxonomic_structure ($tophit_ID, $nodesfileDBM); # retrieve_taxonomic_structure() returns the route from this taxon down to the root.
                            my $contrastinghit_route = retrieve_taxonomic_structure ($contrastinghit_ID, $nodesfileDBM);
                            $intersect_ID = find_taxonomic_intersect ($tophit_route, $contrastinghit_route); # find_taxonomic_intersect() returns the lowest shared rank between the two routes. If there wasn't any shared taxon or if one or more routes were undefined, it returns an ID of 0.
                            
                            if ($intersect_ID == 0) {
                                    $intersect_name = 'none found';
                            } else { # If there was an intersect, find its name.
                                    $intersect_name = retrieve_name ($intersect_ID, $namesfileDBM);
                            }	
                        }
                }
                
            
                # Find the intersection between the top and bottom hits
                #------------------------------------------------------
                # We also find the intersection between the top hit and the bottom (within $cap): bottom_intersect. This isn't used in any calculations, but it is printed in the intersects file and might be useful one day.
                my $tophit_name = 'none found'; my $tophit_rank = 'none found'; # Default to null.
                if ($tophit_info[1]) {
                    $tophit_name = $tophit_info[1];
                }  
                
                my $bottom_intersect_ID = 0; my $bottom_intersect_name = 'none found'; my $bottomhit_ID = 0; my $bottomhit_name = 'none found'; # Default to null values.
                
                if ($number_of_finished_blast_hits == 1) { # If there was only one hit in the end, the bottom hit is the same as the top hit, as is the intersect.
                    $bottom_intersect_ID = $tophit_ID; $bottom_intersect_name = $tophit_name;
                    $bottomhit_ID = $tophit_ID; $bottomhit_name = $tophit_name; 
                }

                if ($number_of_finished_blast_hits == 2) { # If there were only two hits in the end, the top intersect is the same as the intersect and the bottom hit is the same as the contrasting hit.
                    $bottom_intersect_ID = $intersect_ID; $bottom_intersect_name = $intersect_name;
                    $bottomhit_ID = $contrastinghit_ID; $bottomhit_name = $contrastinghit_name; 
                }
                
                if ($number_of_finished_blast_hits > 2) { # If there were more than two hits in the end, it gets more complicated.
                        my $bottomhit = pop @all_hit_info; # $bottom is the final BLAST hit after filtering. The least good BLAST match (within our standards).
                        my @bottomhit_info = split ("\t", $bottomhit);
                        $bottomhit_ID = $bottomhit_info[0];
                        $bottomhit_name = $bottomhit_info[1];
        
                        unless ($bottomhit_ID == 0) { # If the bottom hit doesn't have an ID, we can't calculate a top intersection.
                            my $bottomhit_route = retrieve_taxonomic_structure ($bottomhit_ID, $nodesfileDBM);
                            $bottom_intersect_ID = find_taxonomic_intersect ($tophit_route, $bottomhit_route);
                        }
                        
                        if ($bottom_intersect_ID == 0) {			
                            $bottom_intersect_name = 'none found';
                        } else {
                            $bottom_intersect_name = retrieve_name ($bottom_intersect_ID, $namesfileDBM);
                        }
                }
                
                
                # Print all of this information to the intersects.txt file
                #---------------------------------------------------------
                if ($skip == 0) { # If $skip is 1, this will print mostly null values for a header that should have been skipped. Don't want that.
                    open (my $intersects_filehandle, ">>".$corename."/"."$corename".".intersects.txt") or die "Cannot write intersects file ".$corename.".intersects.txt: $!\n"; # Open intersect file for appending.
            
                    print $intersects_filehandle "Query: $current_header, first hit: $tophit_name ($tophit_ID), expect: $tophit_e_value, identities: $tophit_identities, next hit: $contrastinghit_name ($contrastinghit_ID), last hit up to cap: $bottomhit_name ($bottomhit_ID), phylogenetic range of hits up to cap: $bottom_intersect_name ($bottom_intersect_ID), number of identifiable hits: $number_of_hits, taxonomic diversity: $number_of_hit_taxa, taxonomic diversity score: $tax_diversity_score, classification intersect: $intersect_name ($intersect_ID)\n";
                }
            }
            
            if ($line eq "swan\tsong") { last BLASTLINE; } # If this was the stand-in line, exit the loop now. You've processed the whole file.
            
            delete $headers{$current_header}; # Otherwise, delete the last header from the headers hash so there's fewer to check against next time.
            #------------------------------------------------------------------------------------------------------------------------------------------------------------------
            
            
            # Back to the new header.
            unless (exists $headers{$line[0]}) { # If the qseqid (query sequence ID) for this line doesn't match a header we're looking for, skip it.
                $current_header = $line[0]; # Define the current header.
                $skip = 1;
                next BLASTLINE;
            }

            $current_header = $line[0]; # Define the current header.
            $current_header_number ++;
            print "\t$current_header_number of $number_of_headers: $line[0]\n";
            print $log_filehandle "\t$current_header_number of $number_of_headers: $line[0]\n";
            
            $number_of_hits = 0; %hit_taxa = (); %hit_e_values = (); # Each header gets its own hit count, %hit_taxa and %hit_e_values.
                
            # Check coverage of the top hit:
            my $read_length = $headers{$line[0]};
            my $coverage = $line[3] / $headers{$line[0]}; # Coverage = [match length] / [read length]
            my $min_coverage = $min_coverage_perc / 100;
            if ($coverage < $min_coverage) { # If the top BLAST hit doesn't have at least $min_coverage, activate $skip for this header.
                #print "\t\tTop hit doesn't have sufficient coverage. Skipping.\n";
                #print $log_filehandle "\t\tTop hit doesn't have sufficient coverage. Skipping.\n";
                $skip = 1;
                next BLASTLINE;
            } else { $skip = 0 }; # Otherwise, turn $skip off.
                
            $tophit_identities = $line[2]; # Note the Identities score.
            $tophit_e_value = $line[10]; # Note the E value. These will eventually be exported in the intersects file.     
        }
        #======================================================================================================================================================================
        
        # For all lines until the next header:
        if ($skip == 1) {
            $number_of_hits ++; # Count the hit, but then move on.
            next BLASTLINE;
        }

        $number_of_hits ++; # Count the hit.
        
        my $ID = $line[12]; # Note the taxonomic ID of the organism this hit comes from.
        chomp $ID;

        if (exists $hit_taxa{$ID} or $ID eq 'N/A') { next BLASTLINE; } # If we already have a hit from this organism, or if the ID is 'N/A', move on to the next hit.
        $hit_taxa{$ID} = undef; # Otherwise, note the ID in %hit_taxa.
        
        my $e_value = $line[10]; # Note the E value (Perl recognises that something like 3.14e-10 is a number).
        if (exists $hit_e_values{$e_value}) {
            $hit_e_values{$e_value} = $hit_e_values{$e_value} . "\t" . $ID; # If other hits have had this E value, list this ID with them. We'll find their intersection at the end.
        } else {
            $hit_e_values{$e_value} = $ID; # If the E value is new, make a note.
        }
        
    }

	return $corename; # Return the $corename path for use in other subroutines.
}


sub retrieve_name {
##### Use taxonomic ID to get name
	my ($query_ID, $namesfileDBM) = @_; # $query_ID is the taxonomic ID in question. We want to find its name.
	my $name = 'none found'; # Default to null.
    
    unless ($query_ID == 0) { # ID 0 is null. It's not in the names file.
        my %namesfileDBM = (); # Set up a fresh hash to hold the names DBM file.
        tie (%namesfileDBM, "DB_File", $namesfileDBM, O_RDONLY, 0666, $DB_BTREE) or die "Can't open $namesfileDBM: $!\n";
        
        if (exists $namesfileDBM{$query_ID}) {
            $name = $namesfileDBM{$query_ID};
        }
    }
    untie %namesfileDBM;
	return $name; 
}


sub retrieve_taxonomic_structure {
##### Get hierarchy from nodes.dmp file
	my ($query_ID, $nodesfileDBM) = @_; # $query_ID is a non-0 taxonomic ID. $nodesfileDBM is the path to the nodes index file.

    my $route = undef; # Default the route to undef.
    
    unless ($query_ID == 0) { # I've had it before where $query_ID is "N/A".
        my $exit = 0; # When to exit the do loop below.
        my $next_level_ID; # The ID of the parent node.
        my @route = (); # @route is a list of tab-separated taxonomic IDs moving down from the current node.
        my %nodesfileDBM = (); # Set up a fresh hash to hold the nodes DBM file.
        tie (%nodesfileDBM, "DB_File", $nodesfileDBM, O_RDONLY, 0666, $DB_BTREE) or die "Can't open $nodesfileDBM: $!\n";
        
        do {
            push (@route, $query_ID); # Add the current ID to @route.
            
            if ($query_ID == 1) { # If the current node has ID 1, it's the root. We have a route.
                $exit = 1;
            }
            
            if (exists $nodesfileDBM{$query_ID}) { # Extract the ID of the parent node from the nodes file.
                    my @node_info = split("\t", $nodesfileDBM{$query_ID});
                    $next_level_ID = $node_info[0];
            } else {
                print "\t\tID $query_ID was not found in nodes file. Truncating route here.\n";
                print $log_filehandle "\t\tID $query_ID was not found in nodes file. Truncating route here.\n";
                $exit = 1;
            }
            $query_ID = $next_level_ID; # Move on to the current parent node.
            
        } until ($exit == 1);
        
        untie %nodesfileDBM;
        $route = join ("\t", @route);
    }
    return $route;
}


sub simple_summary {
#### Create simple summary of output. The intersects file is more informative, but this is what most people will take as the output.
	my ($intersects_filename, $min_taxdiv_score) = @_;
    
    unless (-e $intersects_filename) { # If there was no intersects file:
        print "No reads passed the coverage check. No intersects file produced.\n";
        print $log_filehandle "No reads passed the coverage check. No intersects file produced.\n";
        return 'none';
    }
    
	open (my $intersects_filehandle, $intersects_filename) or die "Cannot open intersects file for generating summary basic: $!\n";			
	my %intersects = (); # Keys are intersect names and IDs in the format "name (ID)". Values are the number of times that name (ID) occurs.
    
    # Get a list of classification intersects where the taxa diversity score was at least $min_taxdiv_score.
	foreach my $line (readline ($intersects_filehandle)){
		my @row= split(/, classification intersect: |, id confidence class: /, $line); # Split on the classification intersect field first (note that it won't match to "most distant classification intersect"), followed by the ID confidence field. This is not an 'or'. It's one after the other, chopping off text from the left and right sides to leave just the classification intersect value in the middle.
		my @check= split(/ diversity score: |, classification intersect: /, $line); # Similarly, leave just the taxonomic diversity score.
        
        if ($check[1] >= $min_taxdiv_score ){ # $check[1] is the taxa diversity score. 'none found' means there was no intersect.
            
            # Change the format of the name field ($row[1]) for outputting.
            my $name_field = $row[1];
            my @name_field = split (/ /, $name_field);
            my $ID = pop @name_field; # The ID is the last word.
            chomp $ID;
            $ID =~ tr/()//d; # Remove the parentheses from it (this is transliterate with delete).
            $name_field = join (" ", @name_field); # Join the remaining words back together. These are the taxon name.
            my $ID_and_name = $ID . "\t" . $name_field; # Join the ID and namewith a tab.
            
            if (exists $intersects{$ID_and_name}) {
                $intersects{$ID_and_name} = $intersects{$ID_and_name} + 1;
            } else {
                $intersects{$ID_and_name} = 1;
            }
        }
	}
    close $intersects_filehandle;
    
	my @name=split ("\/",$intersects_filename); # Pick out a sample name from $PIAinputname to use in the output file.
	my $name=$name[0];
    
    my $summary_basic_filename = $name."_Summary_Basic.txt";
	open (my $summary_basic_filehandle, ">", $intersects_filename . "_Summary_Basic.txt") or die "Cannot write output file: $!\n";
	print $summary_basic_filehandle "#Series:\t$name\n"; # Output $name as a header.

    foreach my $intersect (keys %intersects) {
        unless ($intersect eq "0\tnone found") {
            print $summary_basic_filehandle $intersect . "\t" . $intersects{$intersect} . "\n";
        }
    }

	close $summary_basic_filehandle;
	return $summary_basic_filename;
}