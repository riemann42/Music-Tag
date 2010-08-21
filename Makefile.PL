use strict;
use ExtUtils::MakeMaker;
WriteMakefile( NAME         => 'Music::Tag',
               VERSION_FROM => 'lib/Music/Tag.pm',
               ABSTRACT_FROM=> 'lib/Music/Tag.pm',
               AUTHOR       => 'Edward Allen (ealleniii _at_ cpan _dot_ org)',
               EXE_FILES    => [ 'bin/musictag' ],
			   LICENSE		=> 'perl',
               PREREQ_PM => { 'Config::Options'         => 0.07,
                              'Data::Dumper'            => 2.0,
                              'Digest::SHA1'            => 2.11,
                              'Encode'                  => 2.12,
                              'File::Spec'              => 3.24,
                              'IO::File'                => 1.13,
                              'Locale::Country'         => 2.07,
							  'Test::More'				=> 0,
							  'File::Copy'				=> 0,
							  'Time::Local'				=> 1.1901,
							  'Scalar::Util'            => 1.21,
                              'DateTimeX::Easy'         => 0,
                            },
             );

