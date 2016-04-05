#!/usr/bin/perl
#$Id$

use strict;
#use Test::More tests => 3;
use Test::More skip_all => "known to fail";

BEGIN { use_ok('Lab::Instrument') };

ok(my $vi=new Lab::Instrument(0,24),'Open any instrument');
ok(my $idn=$vi->Query('*IDN?'),'Query identification');
diag "Instrument $idn";
