
BEGIN { require 5.005; }

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

#--- Installation check

sub chk_version
{
 my($pkg,$wanted,$msg) = @_;

 $| = 1;
 print "Checking for $pkg...";

 eval { my $p; ($p = $pkg . ".pm") =~ s#::#/#g; require $p; };

 my $vstr = ${"${pkg}::VERSION"} ? "found v" . ${"${pkg}::VERSION"}
                                 : "not found";
 my $vnum = ${"${pkg}::VERSION"} || 0;

 print $vnum >= $wanted ? "ok\n" : " " . $vstr . "\n";

 $vnum >= $wanted;
}

#--- Check for Packages

if (!chk_version(Device::SerialPort => 0.09) &&
    !chk_version(Win32::SerialPort => 0.07)) {
    warn  "\n"
	. "'Device::SerialPort' version 0.09 or better or\n"
	. "'Win32::SerialPort' version 0.07 or better is required.\n"
        . "Look for Device-SerialPort-x.xx.tar.gz on CPAN in:\n"
	. "\thttp://cpan.perl.org/modules/by-module/Device/\n\n";
    $fail=1;
}

if (!chk_version(Mail::Send => 1.08)) {
    warn  "\n"
	. "'Mail::MailTools' version 1.08 or better is required.\n"
        . "Look for MailTools-x.xx.tar.gz on CPAN in:\n"
        . "\thttp://cpan.perl.org/authors/id/G/GB/GBARR/\n\n";
    $fail=1;
}

if (!chk_version(Net::SNPP => 1.10)) {
    warn  "\n"
	. "'Net::SNPP' version 1.10 or better is required.\n"
        . "Look for Net::SNPP-x.xx.tar.gz on CPAN (or the libnet package).\n\n";
    $fail=1;
}

die "Aborting: you need other packages.\n" if (defined($fail));

my @list=<lib/Sendpage/*.pm>;

WriteMakefile(
    'NAME'      => 'sendpage',
    'VERSION_FROM' => 'sendpage', # finds $VERSION
    AUTHOR  => 'Kees Cook <cook@cpoint.net>',
    ABSTRACT_FROM => 'sendpage',
    EXE_FILES => [qw(sendpage snpp email2page)],
    dist         => { COMPRESS => 'gzip -9f', SUFFIX => '.tar.gz', }
);

