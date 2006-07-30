#!/usr/bin/perl
# -*- Mode: CPerl -*-
# Sendpage-KeesConf.t -- unit test for Sendpage::KeesConf
# $Id$
#
# Copyright (C)  2006  Zak B. Elep
# zakame@spunge.org, http://zakame.spunge.org
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License,
# or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
#
# After installation, run as `perl Sendpage-KeesConf.t'

use strict;
use warnings;

use Test::More tests => 57;
BEGIN { use_ok( 'Sendpage::KeesConf' ) or die }

CONSTRUCTOR: {
  my $config = new Sendpage::KeesConf;
  isa_ok( $config, 'Sendpage::KeesConf' );
  my @functions = qw( dump define instance_exists ifset exists
                      fallbackget get instances file set breakdown );
  can_ok( $config, $_ ) foreach @functions;
}

CONFIG_WITH_DEFAULTS: {
  my %defaults =
    (
     boolean => { ARGCOUNT => 0, DEFAULT => "true", },
     scalar  => { ARGCOUNT => 1, DEFAULT => "foo" },
     list    => { ARGCOUNT => 2, DEFAULT => [ qw(bar baz) ], },
    );

  my $config = Sendpage::KeesConf->new();
  isa_ok( $config, 'Sendpage::KeesConf' );
  foreach (keys %defaults) {
    $config->define( $_, $defaults{ $_ } );
    isnt( $config->exists( $_ ),
          1,
          qq(exists("$_") as DEFAULT) );
    isnt( $config->ifset( $_ ),
          1,
          qq(ifset("$_") as DEFAULT) );
    is_deeply( $config->get( $_ ),
               $defaults{ $_ }{DEFAULT},
               qq(get("$_") as DEFAULT) );
    is_deeply( $config->fallbackget( $_ ),
               $defaults{ $_ }{DEFAULT},
               qq(fallbackget("$_") as DEFAULT) );
  }
}

CONFIG_FROM_FILE: {
  # populate our data
  my %settings =
    (
     modem =>
     {
      DEFAULT   => { baud    => 56000, flowctl => 'hardware', },
      sportster => { baud    => 115200 },
      hayes     => { flowctl => 'software' },
      dummy     => { },
     },
    );

  my $config = new Sendpage::KeesConf;
  isa_ok( $config, 'Sendpage::KeesConf' );

  # populate defaults
  for my $section (keys %settings) {
    for my $var (keys %{ $settings{$section}{DEFAULT} }) {
      $config->define( "$section:$var",
                       { DEFAULT => $settings{$section}{DEFAULT}{$var} } );
    }
  }

  # make the tempfile
  use File::Temp ();
  my $tfh = new File::Temp( UNLINK => 1 );
  isa_ok( $tfh, 'File::Temp', $tfh );
  my $fname = $tfh->filename;

  # populate the tempfile with sample config
  for my $section (keys %settings) {
    for my $instance (keys %{ $settings{$section} }) {
      next if $instance =~ /DEFAULT/;
      print $tfh "[$section:$instance]\n";
      for my $var (keys %{ $settings{$section}{$instance} }) {
        print $tfh "$var = $settings{$section}{$instance}{$var}\n";
      }
      print $tfh "\n";
    }
  }
  close $tfh;

  is( $config->file($fname), 1, "file($fname) read" );

  # test settings from %settings
  for my $section (keys %settings) {
    is_deeply( [ "DEFAULT", $config->instances($section) ],
               [ sort keys %{ $settings{$section} } ],
               qq(instances("$section")) );

    # test instances
    for my $instance (keys %{ $settings{$section} }) {
      next if $instance =~ /DEFAULT/;
      is( $config->instance_exists("$section:$instance"),
          1,
          qq(instance_exists("$section:$instance") from $fname) );

      # test overriden settings
      for my $var (keys %{ $settings{$section}{$instance} }) {
        is_deeply( [ $config->breakdown("$section:$instance\@$var") ],
                   [ $section, $instance, $var ],
                   qq(breakdown("$section:$instance\@$var")) );
        is( $config->exists("$section:$instance\@$var"),
            1,
            qq(exists("$section:$instance\@$var") from $fname) );
        is( $config->get("$section:$instance\@$var"),
            $settings{$section}{$instance}{$var},
            qq(get("$section:$instance\@$var") from $fname) );
        is( $config->fallbackget("$section:$instance\@$var"),
            $settings{$section}{$instance}{$var},
            qq(fallbackget("$section:$instance\@$var") from $fname) );
        is( $config->ifset("$section:$instance\@$var"),
            $settings{$section}{$instance}{$var},
            qq(ifset("$section:$instance\@$var") from $fname) );
      }

      # test defaults
      for my $default (keys %{ $settings{$section}{DEFAULT} }) {
        my @vars = keys %{ $settings{$section}{$instance} };
        next if "@vars" =~ /$default/;
        isnt( $config->exists("$section:$instance\@$default"),
              1,
              qq(exists("$section:$instance\@$default") from DEFAULT) );
        is( $config->fallbackget("$section:$instance\@$default"),
            $settings{$section}{DEFAULT}{$default},
            qq(fallbackget("$section:$instance\@$default") from DEFAULT) );
        is( $config->ifset("$section:$instance\@$default"),
            undef,
            qq(ifset("$section:$instance\@$default") from DEFAULT) );
      }
    }
  }

  # cleanup
  is( unlink($fname),
      1,
      "Remove $tfh" );
  ok( !-e $fname, "$tfh gone" );
}
