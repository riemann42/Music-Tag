#!/usr/bin/perl -w
use strict;
use Test::More;
eval "use Test::Strict";
plan skip_all => "Test::Strict required for testing strict" if $@;

all_perl_files_ok();
#all_cover_ok(50);
