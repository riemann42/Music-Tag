use Test::More;
use strict;
eval { require Test::Kwalitee; Test::Kwalitee->import() };
plan(skip_all => 'Test::Kwalitee not installed; skipping') if $@;

