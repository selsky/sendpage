use vars qw($serialport_driver $serialport_version);
BEGIN {
	require 5.006;

	# Architecture check for SerialPort driver
	$serialport_driver="Device::SerialPort";
	$serialport_version="1.0";
	if( $^O =~ /Win/io ) {
		$serialport_driver="Win32::SerialPort";
		$serialport_version="0.07";
	}
}
use ExtUtils::MakeMaker;
use strict;
use warnings;
use Config;

# Don't need these yet
#use File::Spec::Functions;
#use File::Basename;

my %args = (
	pkg_name => 'sendpage',
	name     => 'sendpage',
	DESTDIR  => undef,
);
my @pass_args;
while (my $arg = shift @ARGV) {
    my ($key, $value) = split /=/, $arg;
        if (exists $args{$key}) {
        $args{$key} = $value;
    } else {
        push @pass_args, $arg;
    }
}
@ARGV = @pass_args;


my %opts=(
    'INSTALLDIRS'   => 'site',
    'NAME'          => $args{'name'},
    'AUTHOR'        => 'Kees Cook <kees@outflux.net>',
    'VERSION_FROM'  => 'sendpage', # finds $VERSION
    'ABSTRACT_FROM' => 'sendpage',
    'EXE_FILES'     => [ qw(
    				sendpage
				snpp
				email2page
				sendmail2snpp
				sendpage-db
			) ],
    'PREREQ_PM'     => {
		'Net::SNPP' => 1.10,
		'Mail::Send' => 1.08,
		$serialport_driver => $serialport_version,		
	},
);

if ($ExtUtils::MakeMaker::VERSION > 5.45) {
        $opts{'PREREQ_FATAL'} = 1,
}

# This puts us in the site_perl directory, not dependant on any version
# of perl.
if (defined($Config{'sitelib_stem'}) && $Config{'sitelib_stem'} ne "") {
        #print "stem is: $Config{'sitelib_stem'}\n";
        $opts{'INSTALLSITELIB'} = "";
        $opts{'INSTALLSITELIB'} = $args{'DESTDIR'}
                if (($] >= 5.008 && $] < 5.008005) ||
                    $ExtUtils::MakeMaker::VERSION =~ /5\.9[1-6]|6\.0[0-5]/);
        $opts{'INSTALLSITELIB'} .= $Config{'sitelib_stem'};
}

WriteMakefile(%opts);

# /* vi:set ai ts=4 sw=4 expandtab: */
