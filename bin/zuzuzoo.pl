#!/usr/bin/env perl

use utf8;
use strict;
use warnings;

use FindBin qw( $Bin );
use lib "$Bin/../lib";

use Zuzuzoo::CLI;

my $exit_code = Zuzuzoo::CLI::run(@ARGV);
exit $exit_code;
