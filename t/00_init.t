#!/usr/bin/perl -w -I../lib
use Test::More tests => 10;

BEGIN {
    use_ok( 'Sendpage::KeesConf' );         #  1
    use_ok( 'Sendpage::KeesLog' );          #  2
    use_ok( 'Sendpage::Modem' );            #  3
    use_ok( 'Sendpage::Page' );             #  4
    use_ok( 'Sendpage::Queue' );            #  5
    use_ok( 'Sendpage::PageQueue' );        #  6
    use_ok( 'Sendpage::Recipient' );        #  7
    use_ok( 'Sendpage::PagingCentral' );    #  8
    use_ok( 'Sendpage::SNPPServer' );       #  9
    use_ok( 'Sendpage::Db' );               # 10
    #use_ok( 'Sendpage::Utilities' );        # 11
    #use_ok( 'Sendpage::Device' );           # 12
}
