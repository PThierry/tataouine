#!/usr/bin/perl -l
use strict;

#---
# Usage: ./gen_ld.pl <.config_file>
#---

$,=' ';

# Check the inputs

@ARGV == 1 or usage();
( -f "$ARGV[0]" ) or die "$ARGV[0] is not a regular as is ought to be";

my $out_header_ada = "kernel/Ada/generated/config.def";
open my $OUTHDR_ADA, ">", "$out_header_ada" or die "unable to open $out_header_ada";

my %hash;

#---
# Main
#---

#
# Slurp the config file and parse it
#
get_apps_from_config();

#
# Ada header
#

  print $OUTHDR_ADA <<EOF
------------------------------------------------------------------------
----      Copyright (c) 15-01-2018, ANSSI
----      All rights reserved.
----
---- This file is autogenerated by tools/gen_autoconf_ada.pl
----
---- This file describes the .config content, as a file parsable by Ada
---- Please see the above script for details.
----
--------------------------------------------------------------------------

EOF
;

my $slot = 1;

foreach my $i (sort(keys(%hash))) {

  if ($hash{$i} eq "y") {
    print $OUTHDR_ADA "CONFIG_$i := true"
  } elsif ($hash{$i} eq "n") {
    print $OUTHDR_ADA "CONFIG_$i := false"
  } elsif ( $hash{$i} =~ /^[0-9]+$/ ) {
    my $val = $hash{$i};
    print $OUTHDR_ADA "CONFIG_$i := $val";
  } elsif ( $hash{$i} =~ /^0x[0-9a-fA-F]+$/ ) {
    my ($val) = $hash{$i} =~ /^0x([0-9a-fA-F]+)$/;
    print $OUTHDR_ADA "CONFIG_$i := 16#$val#";
  } else {
    my $val = $hash{$i};
    print $OUTHDR_ADA "CONFIG_$i := $val";
  }

#  if ($hash{"${i}_PERM_CRYPTO_USER"} eq "y") {
#    $capa_crypto_user = 1;
#  }
#  if ($hash{"${i}_PERM_EXT_IO"} eq "y") {
#    $capa_ext_io = 1;
#  }
}

print $OUTHDR_ADA <<EOF
EOF
;

#---
# Utility functions
#---

sub usage()
{
  print STDERR "usage: $0 <.config_file>";
  exit(1);
}


sub get_apps_from_config()
{
  local $/;
  my $tmp=<>;
  # A config file line can be one of : empty/start with # /or start with CONFIG
  $tmp =~ /^(\s+\n|\s*#.*\n|\s*CONFIG([^=]+)=(.*)\n)*$/
  	or die "WARNING: your config file does not look correct";

  %hash = ($tmp =~ /^CONFIG_([^=]+)=(.*)/mg);
}
